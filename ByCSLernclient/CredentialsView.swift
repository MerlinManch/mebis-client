import SwiftUI

struct CredentialsView: View {
    @ObservedObject var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var saveError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ByCS-Kennung", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Die Zugangsdaten werden nur auf diesem Gerät im iOS-Schlüsselbund gespeichert. Die App meldet dich damit auf auth.bycs.de an, wenn deine Sitzung abläuft.")
                }

                Section {
                    Button("Speichern und automatisch anmelden") {
                        if browser.saveCredentials(username: username, password: password) {
                            password = ""
                            dismiss()
                        } else {
                            saveError = true
                        }
                    }
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }

                if browser.hasSavedCredentials {
                    Section {
                        Button("Gespeicherte Zugangsdaten löschen", role: .destructive) {
                            browser.removeCredentials()
                            password = ""
                            dismiss()
                        }
                    } footer: {
                        Text("Nach dem Löschen bleibt eine bereits aktive ByCS-Sitzung bis zum Abmelden oder ihrem Ablauf bestehen.")
                    }
                }
            }
            .navigationTitle("Anmeldedaten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear { username = browser.savedUsername ?? "" }
            .onDisappear { password = "" }
            .alert("Speichern fehlgeschlagen", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Der iOS-Schlüsselbund ist derzeit nicht verfügbar.")
            }
        }
    }
}
