import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

enum PDFMergeError: LocalizedError {
    case noFiles
    case unreadable(String)
    case protected(String)
    case empty(String)
    case unsupported(String)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noFiles: "Wähle mindestens eine Datei aus."
        case .unreadable(let name): "„\(name)“ konnte nicht gelesen werden."
        case .protected(let name): "„\(name)“ ist passwortgeschützt und kann nicht zusammengeführt werden."
        case .empty(let name): "„\(name)“ enthält keine PDF-Seiten."
        case .unsupported(let name): "„\(name)“ ist weder ein unterstütztes Bild noch ein PDF."
        case .writeFailed: "Das Sammel-PDF konnte nicht gespeichert werden."
        }
    }
}

enum PDFMergeService {
    /// Appends the pages in selection order. PDF pages are copied to preserve their content.
    static func export(_ urls: [URL]) throws -> URL {
        guard !urls.isEmpty else { throw PDFMergeError.noFiles }

        let result = PDFDocument()
        for url in urls {
            let name = url.lastPathComponent
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .pdf) == true {
                guard let document = PDFDocument(url: url) else { throw PDFMergeError.unreadable(name) }
                guard !document.isLocked else { throw PDFMergeError.protected(name) }
                guard document.pageCount > 0 else { throw PDFMergeError.empty(name) }
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index)?.copy() as? PDFPage else {
                        throw PDFMergeError.unreadable(name)
                    }
                    result.insert(page, at: result.pageCount)
                }
            } else if type?.conforms(to: .image) == true {
                guard let image = UIImage(contentsOfFile: url.path), let page = PDFPage(image: image) else {
                    throw PDFMergeError.unreadable(name)
                }
                result.insert(page, at: result.pageCount)
            } else {
                throw PDFMergeError.unsupported(name)
            }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("Gesammelte Dateien.pdf")
        guard result.write(to: output) else {
            try? FileManager.default.removeItem(at: directory)
            throw PDFMergeError.writeFailed
        }
        return output
    }
}
