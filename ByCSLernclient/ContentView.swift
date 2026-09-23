import SwiftUI

struct ContentView: View {
    @StateObject private var browser = BrowserModel()
    @State private var showClearConfirmation = false
    @State private var showCredentials = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Lernplattform")
                        .font(.headline)
                    Text(browser.currentURL?.host ?? "lernplattform.bycs.de")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Menu {
                    Button {
                        showCredentials = true
                    } label: {
                        Label(browser.hasSavedCredentials ? "Anmeldedaten ändern" : "Anmeldedaten speichern",
                              systemImage: "key")
                    }
                    if let url = browser.currentURL, url.scheme == "https" {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Label("In Safari öffnen", systemImage: "safari")
                        }
                    }
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Weitere Optionen")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)

            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Seite wird geladen")
            }

            if let notice = browser.automaticLoginNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            BrowserView(webView: browser.webView)

            Divider()
            HStack {
                control("books.vertical", "Meine Kurse") { browser.goHome() }
                Spacer()
                control("chevron.left", "Zurück", disabled: !browser.canGoBack) {
                    browser.webView.goBack()
                }
                Spacer()
                control("chevron.right", "Vorwärts", disabled: !browser.canGoForward) {
                    browser.webView.goForward()
                }
                Spacer()
                control("arrow.clockwise", "Neu laden") { browser.reload() }
                Spacer()
                ShareLink(item: browser.currentURL ?? BrowserModel.homeURL) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Link teilen")
            }
            .font(.title3)
            .padding(.horizontal, 16)
        }
        .confirmationDialog("Abmelden und Zugangsdaten löschen?", isPresented: $showClearConfirmation) {
            Button("Abmelden", role: .destructive) {
                browser.removeCredentials()
                browser.clearSession()
            }
        } message: {
            Text("Cookies, Website-Daten und gespeicherte Zugangsdaten werden entfernt.")
        }
        .sheet(isPresented: $showCredentials) {
            CredentialsView(browser: browser)
        }
        .alert("Hinweis", isPresented: Binding(
            get: { browser.errorMessage != nil },
            set: { if !$0 { browser.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { browser.errorMessage = nil }
        } message: {
            Text(browser.errorMessage ?? "")
        }
        .sheet(item: $browser.downloadedFile) { file in
            VStack(spacing: 24) {
                Image(systemName: "doc.fill")
                    .font(.largeTitle)
                Text(file.url.lastPathComponent)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                ShareLink(item: file.url) {
                    Label("Datei speichern oder teilen", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                Button("Schließen") { browser.downloadedFile = nil }
            }
            .padding(28)
            .presentationDetents([.medium])
        }
    }

    private func control(_ symbol: String, _ label: String, disabled: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}
