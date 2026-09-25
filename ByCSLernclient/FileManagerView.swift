import QuickLook
import SwiftUI

struct FileManagerView: View {
    @ObservedObject var store: LocalFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var preview: LocalFile?
    @State private var fileToDelete: LocalFile?

    var body: some View {
        NavigationStack {
            Group {
                if store.files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Noch keine Dateien").font(.headline)
                        Text("Öffne ein PDF oder Bild in der Lernplattform und wähle „Im Dateimanager speichern“.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(store.files) { file in
                        Button { preview = file } label: {
                            HStack(spacing: 12) {
                                Image(systemName: file.isImage ? "photo" : "doc.fill")
                                    .font(.title2)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).lineLimit(2)
                                    Text("\(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) · \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Löschen", role: .destructive) { fileToDelete = file }
                            ShareLink(item: file.url) {
                                Label("Teilen", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Dateimanager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear { store.refresh() }
            .sheet(item: $preview) { file in
                NavigationStack {
                    FilePreview(url: file.url)
                        .navigationTitle(file.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Fertig") { preview = nil }
                            }
                            ToolbarItem(placement: .bottomBar) {
                                ShareLink(item: file.url) { Label("Teilen", systemImage: "square.and.arrow.up") }
                            }
                        }
                }
            }
            .alert(item: $fileToDelete) { file in
                Alert(
                    title: Text("„\(file.name)“ löschen?"),
                    primaryButton: .destructive(Text("Datei löschen")) { store.delete(file) },
                    secondaryButton: .cancel()
                )
            }
            .alert("Hinweis", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

struct FilePreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
