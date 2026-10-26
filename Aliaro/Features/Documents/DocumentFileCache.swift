import Foundation
import UIKit
import PDFKit

/// Local copies of family documents, keyed by their Storage path, in the
/// Caches folder (the system may purge it; files are downloaded again on
/// demand). Also renders and caches small thumbnails.
final class DocumentFileCache {
    static let shared = DocumentFileCache()

    private let directory: URL
    private let thumbnails = NSCache<NSString, UIImage>()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("family-documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(path: String, type: FamilyDocument.FileType) -> URL {
        var name = path.replacingOccurrences(of: "/", with: "_")
        if !name.hasSuffix(".\(type.fileExtension)") { name += ".\(type.fileExtension)" }
        return directory.appendingPathComponent(name)
    }

    func url(path: String, type: FamilyDocument.FileType) -> URL? {
        guard !path.isEmpty else { return nil }
        let url = fileURL(path: path, type: type)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func save(_ data: Data, path: String, type: FamilyDocument.FileType) -> URL? {
        let url = fileURL(path: path, type: type)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func remove(path: String) {
        guard !path.isEmpty else { return }
        thumbnails.removeObject(forKey: path as NSString)
        for type in [FamilyDocument.FileType.pdf, .image] {
            try? FileManager.default.removeItem(at: fileURL(path: path, type: type))
        }
    }

    func clear() {
        thumbnails.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// First page (PDF) or the photo itself, scaled down to `size`.
    func thumbnail(for url: URL, path: String, type: FamilyDocument.FileType, size: CGSize) -> UIImage? {
        if let cached = thumbnails.object(forKey: path as NSString) { return cached }
        let image: UIImage?
        switch type {
        case .pdf:
            image = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: size, for: .cropBox)
        case .image:
            if let full = UIImage(contentsOfFile: url.path), full.size.width > 0, full.size.height > 0 {
                let scale = max(size.width / full.size.width, size.height / full.size.height)
                image = full.preparingThumbnail(of: CGSize(width: full.size.width * scale, height: full.size.height * scale))
            } else {
                image = nil
            }
        }
        if let image { thumbnails.setObject(image, forKey: path as NSString) }
        return image
    }
}
