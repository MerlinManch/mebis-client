import QuickLook
import SwiftUI

struct FileManagerView: View {
    @ObservedObject var store: LocalFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var preview: LocalFile?
    @State private var fileToDelete: LocalFile?
    @State private var isSelecting = false
    @State private var selectedURLs: [URL] = []
    @State private var isExporting = false
    @State private var exportedPDF: ExportedPDF?
    @State private var temporaryExportURL: URL?

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
                    List {
                        ForEach(store.files) { file in
                            Button {
                                if isSelecting {
                                    guard file.canExportAsPDF else { return }
                                    if let index = selectedURLs.firstIndex(of: file.url) {
                                        selectedURLs.remove(at: index)
                                    } else {
                                        selectedURLs.append(file.url)
                                    }
                                } else {
                                    preview = file
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    if isSelecting {
                                        Image(systemName: selectedURLs.contains(file.url) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundStyle(.tint)
                                    }
                                    Image(systemName: file.isImage ? "photo" : "doc.fill")
                                        .font(.title2)
                                        .frame(width: 32)
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.name)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text("\(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) · \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if isSelecting {
                                            Text(selectionDetail(for: file))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isSelecting && !file.canExportAsPDF)
                            .swipeActions {
                                if !isSelecting {
                                    Button("Löschen", role: .destructive) { fileToDelete = file }
                                        .tint(.red)
                                    ShareLink(item: file.url) {
                                        Label("Teilen", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                        if isSelecting {
                            Text("Die Auswahlreihenfolge bestimmt die Reihenfolge der Seiten im PDF.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("Dateimanager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isSelecting && store.files.contains(where: \.canExportAsPDF) {
                        Button("Auswählen") { isSelecting = true }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSelecting ? "Abbrechen" : "Fertig") {
                        if isSelecting {
                            selectedURLs.removeAll()
                            isSelecting = false
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isExporting)
                }
                ToolbarItem(placement: .bottomBar) {
                    if isSelecting {
                        if isExporting {
                            ProgressView("PDF wird erstellt …")
                        } else {
                            Button {
                                exportSelection()
                            } label: {
                                Label("Als PDF exportieren (\(selectedURLs.count))", systemImage: "doc.richtext")
                            }
                            .disabled(selectedURLs.isEmpty)
                        }
                    }
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
            .sheet(item: $exportedPDF, onDismiss: removeTemporaryExport) { export in
                NavigationStack {
                    FilePreview(url: export.url)
                        .navigationTitle("Gesammelte Dateien.pdf")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Fertig") { exportedPDF = nil }
                            }
                            ToolbarItem(placement: .bottomBar) {
                                ShareLink(item: export.url) {
                                    Label("Teilen oder in Dateien sichern", systemImage: "square.and.arrow.up")
                                }
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

    private func selectionDetail(for file: LocalFile) -> String {
        if !file.canExportAsPDF { return "Nur PDF-Dateien und Bilder exportierbar" }
        if let index = selectedURLs.firstIndex(of: file.url) { return "Position \(index + 1) im PDF" }
        return "Zum PDF hinzufügen"
    }

    private func exportSelection() {
        guard !selectedURLs.isEmpty else { return }
        let urls = selectedURLs
        isExporting = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try PDFMergeService.export(urls) }
            await MainActor.run {
                isExporting = false
                switch result {
                case .success(let url):
                    temporaryExportURL = url
                    exportedPDF = ExportedPDF(url: url)
                    selectedURLs.removeAll()
                    isSelecting = false
                case .failure(let error):
                    store.errorMessage = "PDF-Export fehlgeschlagen: \(error.localizedDescription)"
                }
            }
        }
    }

    private func removeTemporaryExport() {
        if let url = temporaryExportURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            temporaryExportURL = nil
        }
    }
}

private struct ExportedPDF: Identifiable {
    let id = UUID()
    let url: URL
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
