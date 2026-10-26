import SwiftUI
import UIKit
import VisionKit
import PDFKit

/// A file ready to be saved as a family document.
struct DocumentDraft {
    let data: Data
    let type: FamilyDocument.FileType
    let pageCount: Int
    /// Suggested title (e.g. an imported PDF's file name).
    var suggestedTitle: String = ""
    /// Preview shown in the sheet.
    let preview: UIImage?
}

enum DocumentImport {
    /// Longest side of a page/photo once stored (keeps files small but readable).
    private static let maxPixelSide: CGFloat = 2000

    /// Scanned pages → one PDF.
    static func pdf(from pages: [UIImage]) -> DocumentDraft? {
        guard !pages.isEmpty else { return nil }
        let pageWidth: CGFloat = 595 // A4 width in points
        let images = pages.map { downscaled($0) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageWidth * 1.414))
        let data = renderer.pdfData { context in
            for image in images {
                let ratio = image.size.height / max(image.size.width, 1)
                let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageWidth * ratio)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                // Re-encoded as JPEG so the PDF embeds a compressed image.
                let jpeg = image.jpegData(compressionQuality: 0.7).flatMap(UIImage.init(data:)) ?? image
                jpeg.draw(in: bounds)
            }
        }
        return DocumentDraft(data: data, type: .pdf, pageCount: images.count, preview: images.first)
    }

    /// A photo (camera or library) → compressed JPEG.
    static func image(from data: Data) -> DocumentDraft? {
        guard let image = UIImage(data: data) else { return nil }
        let scaled = downscaled(image)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.8) else { return nil }
        return DocumentDraft(data: jpeg, type: .image, pageCount: 1, preview: scaled)
    }

    /// A PDF picked from Files.
    static func pdf(at url: URL) -> DocumentDraft? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let pdf = PDFDocument(data: data) else { return nil }
        let preview = pdf.page(at: 0)?.thumbnail(of: CGSize(width: 400, height: 560), for: .cropBox)
        return DocumentDraft(
            data: data, type: .pdf, pageCount: max(pdf.pageCount, 1),
            suggestedTitle: url.deletingPathExtension().lastPathComponent, preview: preview
        )
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let side = max(image.size.width, image.size.height) * image.scale
        guard side > maxPixelSide else { return image }
        let factor = maxPixelSide / side
        let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// The system document scanner (edge detection, perspective correction,
/// several pages). Only present it when `DocumentScannerView.isAvailable`.
struct DocumentScannerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onScan: ([UIImage]) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(pages)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
