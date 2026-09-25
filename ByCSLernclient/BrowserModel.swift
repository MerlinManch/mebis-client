import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    static let homeURL = URL(string: "https://lernplattform.bycs.de/my/courses.php")!

    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published var errorMessage: String?
    @Published var downloadedFile: DownloadedFile?
    @Published var previewFile: DownloadedFile?
    @Published var pendingAttachment: AttachmentPrompt?
    @Published private(set) var hasSavedCredentials = false
    @Published private(set) var savedUsername: String?
    @Published private(set) var automaticLoginNotice: String?

    let webView: WKWebView
    let files = LocalFileStore()
    private var observations: [NSKeyValueObservation] = []
    private var destinations: [ObjectIdentifier: (url: URL, choice: AttachmentChoice?)] = [:]
    private var attachmentRequests: [(url: URL, choice: AttachmentChoice)] = []
    private var downloadChoices: [ObjectIdentifier: AttachmentChoice] = [:]
    private var previewTemporaryURL: URL?
    private var pendingAttachmentDecision: ((WKNavigationResponsePolicy) -> Void)?
    private var attemptedAutomaticLogin = false
    private var automaticLoginPaused = false
    private var awaitingLoginLanding = false

    override init() {
        let configuration = WKWebViewConfiguration()
        // Persistent cookies keep ByCS SSO alive between app launches.
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        let saved = CredentialStore.load()
        hasSavedCredentials = saved != nil
        savedUsername = saved?.username
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.currentURL = view.url }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            }
        ]
        goHome()
    }

    func goHome() {
        errorMessage = nil
        webView.load(URLRequest(url: Self.homeURL))
    }

    func reload() {
        errorMessage = nil
        if webView.url == nil { goHome() } else { webView.reload() }
    }

    func clearSession() {
        // Remove cookies, cache, local storage and service workers of this app.
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            Task { @MainActor in self?.goHome() }
        }
    }

    func chooseAttachment(save: Bool) {
        guard let decision = pendingAttachmentDecision else { return }
        pendingAttachmentDecision = nil
        let url = pendingAttachment?.url
        pendingAttachment = nil
        if let url {
            attachmentRequests.append((url, save ? .save : .preview))
            decision(.download)
        } else {
            decision(.cancel)
        }
    }

    func closePreview() {
        if let url = previewTemporaryURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        previewTemporaryURL = nil
        previewFile = nil
    }

    func cancelAttachment() {
        guard let decision = pendingAttachmentDecision else { return }
        pendingAttachmentDecision = nil
        pendingAttachment = nil
        decision(.cancel)
    }

    func saveCredentials(username: String, password: String) -> Bool {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty, !password.isEmpty,
              CredentialStore.save(username: cleanUsername, password: password) else { return false }
        savedUsername = cleanUsername
        hasSavedCredentials = true
        attemptedAutomaticLogin = false
        automaticLoginPaused = false
        automaticLoginNotice = nil
        if !webView.isLoading { attemptAutomaticLogin(on: webView) }
        return true
    }

    func removeCredentials() {
        CredentialStore.delete()
        savedUsername = nil
        hasSavedCredentials = false
        attemptedAutomaticLogin = false
        automaticLoginPaused = true
        automaticLoginNotice = nil
    }

    private func isByCSLogin(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "auth.bycs.de" && (
            url.path == "/realms/bycs/protocol/openid-connect/auth" ||
            url.path == "/realms/bycs/login-actions/authenticate"
        )
    }

    private func handleFinishedPage(_ webView: WKWebView) {
        guard let url = webView.url else { return }
        if url.scheme == "https", url.host == "lernplattform.bycs.de", url.path.hasPrefix("/my/") {
            attemptedAutomaticLogin = false
            automaticLoginPaused = false
            automaticLoginNotice = nil
            if url.path == Self.homeURL.path {
                awaitingLoginLanding = false
            } else if awaitingLoginLanding && url.path == "/my/" {
                awaitingLoginLanding = false
                goHome()
            }
            return
        }
        guard isByCSLogin(url) else { return }
        awaitingLoginLanding = true
        if attemptedAutomaticLogin {
            webView.evaluateJavaScript(
                "Boolean(document.querySelector('form#kc-form-login input[name=password]'))"
            ) { [weak self] result, _ in
                let loginFormReturned = (result as? Bool) == true
                Task { @MainActor [weak self] in
                    guard let self, loginFormReturned else { return }
                    self.automaticLoginPaused = true
                    self.automaticLoginNotice = "Automatische Anmeldung pausiert. Bitte Passwort prüfen oder manuell anmelden."
                }
            }
            return
        }
        attemptAutomaticLogin(on: webView)
    }

    private func attemptAutomaticLogin(on webView: WKWebView) {
        guard !automaticLoginPaused, !attemptedAutomaticLogin,
              let url = webView.url, isByCSLogin(url),
              let credentials = CredentialStore.load(),
              let data = try? JSONSerialization.data(withJSONObject: [
                "username": credentials.username, "password": credentials.password
              ]),
              let json = String(data: data, encoding: .utf8) else { return }

        // The script also checks the main frame's origin and the form destination.
        // JSONSerialization quotes the user data; never concatenate raw input into JS.
        let script = """
        (() => {
            if (location.origin !== 'https://auth.bycs.de') return 'wrong-origin';
            const form = document.querySelector('form#kc-form-login');
            if (!form) return 'missing-form';
            const destination = new URL(form.action, location.href);
            if (destination.origin !== location.origin ||
                !destination.pathname.startsWith('/realms/bycs/login-actions/authenticate')) return 'wrong-form';
            const username = form.querySelector('input[name="username"][type="text"]');
            const password = form.querySelector('input[name="password"][type="password"]');
            const submit = form.querySelector('button[name="login"][type="submit"]');
            if (!username || !password || !submit) return 'missing-fields';
            const credentials = \(json);
            const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
            setter.call(username, credentials.username);
            setter.call(password, credentials.password);
            for (const input of [username, password]) {
                input.dispatchEvent(new Event('input', {bubbles: true}));
                input.dispatchEvent(new Event('change', {bubbles: true}));
            }
            form.requestSubmit(submit);
            return 'submitted';
        })()
        """
        attemptedAutomaticLogin = true
        webView.evaluateJavaScript(script) { [weak self] result, error in
            let submitted = error == nil && (result as? String) == "submitted"
            Task { @MainActor [weak self] in
                guard let self, !submitted else { return }
                self.automaticLoginPaused = true
                self.automaticLoginNotice = "Automatische Anmeldung nicht möglich. Bitte manuell anmelden."
            }
        }
    }
}

struct DownloadedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct AttachmentPrompt: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
}

private enum AttachmentChoice: Equatable {
    case save
    case preview
}

extension BrowserModel: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        handleFinishedPage(webView)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }

        switch scheme {
        case "https", "about", "blob", "file":
            decisionHandler(.allow)
        case "mailto", "tel":
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        default:
            // Do not send the user's authenticated session to insecure HTTP.
            decisionHandler(.cancel)
            errorMessage = "Dieser Link verwendet keine unterstützte sichere Verbindung."
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        let mime = response.mimeType?.lowercased() ?? ""
        let filename = response.suggestedFilename ?? response.url?.lastPathComponent ?? "Datei"
        let extensionType = UTType(filenameExtension: (filename as NSString).pathExtension)
        let mediaFile = mime == "application/pdf" || mime.hasPrefix("image/") ||
            ((mime.isEmpty || mime == "application/octet-stream") &&
             (extensionType?.conforms(to: .pdf) == true || extensionType?.conforms(to: .image) == true))
        if navigationResponse.isForMainFrame,
           let url = response.url, url.scheme == "https" || url.scheme == "blob",
           mediaFile {
            guard pendingAttachmentDecision == nil else {
                decisionHandler(.cancel)
                return
            }
            pendingAttachmentDecision = decisionHandler
            pendingAttachment = AttachmentPrompt(url: url, filename: filename)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        prepare(download)
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        prepare(download)
        download.delegate = self
    }

    private func prepare(_ download: WKDownload) {
        guard !attachmentRequests.isEmpty else { return }
        if let originalURL = download.originalRequest?.url,
           let index = attachmentRequests.firstIndex(where: { $0.url == originalURL }) {
            let request = attachmentRequests.remove(at: index)
            downloadChoices[ObjectIdentifier(download)] = request.choice
        } else if attachmentRequests.count == 1 {
            // A redirect can change the final response URL used for the prompt.
            let request = attachmentRequests.removeFirst()
            downloadChoices[ObjectIdentifier(download)] = request.choice
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let identifier = ObjectIdentifier(download)
        let choice = downloadChoices[identifier]
        do {
            let destination: URL
            if choice == .save {
                destination = try files.destination(for: suggestedFilename, mimeType: response.mimeType)
            } else {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var filename = (suggestedFilename as NSString).lastPathComponent
                if filename.isEmpty || filename == "." || filename == ".." { filename = "Download" }
                if choice == .preview,
                   let mime = response.mimeType,
                   let type = UTType(mimeType: mime),
                   (type.conforms(to: .pdf) || type.conforms(to: .image)),
                   let preferred = type.preferredFilenameExtension,
                   UTType(filenameExtension: (filename as NSString).pathExtension)?.conforms(to: type) != true {
                    filename += ".\(preferred)"
                }
                destination = directory.appendingPathComponent(filename.isEmpty ? "Download" : filename)
            }
            destinations[identifier] = (destination, choice)
            completionHandler(destination)
        } catch {
            downloadChoices.removeValue(forKey: identifier)
            errorMessage = "Die Datei konnte nicht gespeichert werden."
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let identifier = ObjectIdentifier(download)
        downloadChoices.removeValue(forKey: identifier)
        if let destination = destinations.removeValue(forKey: identifier) {
            switch destination.choice {
            case .some(.save):
                files.didSaveFile()
            case .some(.preview):
                previewTemporaryURL = destination.url
                previewFile = DownloadedFile(url: destination.url)
            case nil:
                downloadedFile = DownloadedFile(url: destination.url)
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let identifier = ObjectIdentifier(download)
        if let destination = destinations.removeValue(forKey: identifier) {
            try? FileManager.default.removeItem(at: destination.url)
        }
        downloadChoices.removeValue(forKey: identifier)
        errorMessage = "Der Download ist fehlgeschlagen: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = "Die Seite konnte nicht geladen werden: \(error.localizedDescription)"
    }
}
