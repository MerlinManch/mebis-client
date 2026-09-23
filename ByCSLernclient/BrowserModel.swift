import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    static let deskURL = URL(string: "https://lernplattform.bycs.de/my/")!

    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published var errorMessage: String?
    @Published var downloadedFile: DownloadedFile?

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var destinations: [ObjectIdentifier: URL] = [:]

    override init() {
        let configuration = WKWebViewConfiguration()
        // Persistent cookies keep ByCS SSO alive between app launches.
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
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
        goToDesk()
    }

    func goToDesk() {
        errorMessage = nil
        webView.load(URLRequest(url: Self.deskURL))
    }

    func reload() {
        errorMessage = nil
        if webView.url == nil { goToDesk() } else { webView.reload() }
    }

    func clearSession() {
        // Remove cookies, cache, local storage and service workers of this app.
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            Task { @MainActor in self?.goToDesk() }
        }
    }
}

struct DownloadedFile: Identifiable {
    let id = UUID()
    let url: URL
}

extension BrowserModel: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
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
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let filename = (suggestedFilename as NSString).lastPathComponent
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(filename.isEmpty ? "Download" : filename)
            destinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        } catch {
            errorMessage = "Die Datei konnte nicht gespeichert werden."
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let destination = destinations.removeValue(forKey: ObjectIdentifier(download)) {
            downloadedFile = DownloadedFile(url: destination)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
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
