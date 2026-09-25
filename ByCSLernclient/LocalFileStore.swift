import Combine
import Foundation
import UniformTypeIdentifiers

struct LocalFile: Identifiable {
    let url: URL
    let size: Int64
    let modified: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isImage: Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true }
}

@MainActor
final class LocalFileStore: ObservableObject {
    @Published private(set) var files: [LocalFile] = []
    @Published var errorMessage: String?

    private let folder: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Dateimanager", isDirectory: true)
        refresh()
    }

    func refresh() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            files = try urls.compactMap { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                guard values.isRegularFile == true else { return nil }
                return LocalFile(url: url, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast)
            }.sorted { $0.modified > $1.modified }
        } catch {
            errorMessage = "Dateien konnten nicht geladen werden: \(error.localizedDescription)"
        }
    }

    func destination(for suggestedName: String, mimeType: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = (suggestedName as NSString).lastPathComponent
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." { name = "Datei" }

        let extensionFromType = mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
        if (name as NSString).pathExtension.isEmpty, let extensionFromType {
            name += ".\(extensionFromType)"
        }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name, isDirectory: false)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = "\(base) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = folder.appendingPathComponent(nextName, isDirectory: false)
            suffix += 1
        }
        return candidate
    }

    func didSaveFile() { refresh() }

    func saveTemporaryFile(_ source: URL) -> Bool {
        do {
            let target = try destination(for: source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: target)
            refresh()
            return true
        } catch {
            errorMessage = "Datei konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ file: LocalFile) {
        do {
            try FileManager.default.removeItem(at: file.url)
            refresh()
        } catch {
            errorMessage = "Datei konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}
