import Foundation
import SwiftData

/// A document saved by the family (a receipt, an invoice, the vaccination
/// card…): a scanned or imported PDF, or a photo. The file lives in
/// Supabase Storage (`family-documents`) at `filePath`; the local copy is
/// cached on disk by `DocumentFileCache`, never in SwiftData.
/// Shared with the whole family group.
@Model
final class FamilyDocument {
    var id: UUID
    var title: String
    /// Reference to `DocumentCategory` (not a SwiftData relationship).
    /// `nil` when uncategorized (or its category was deleted).
    var categoryID: UUID?
    var filePath: String
    /// `FamilyDocument.FileType` raw value.
    var fileType: String
    var fileSize: Int
    var pageCount: Int
    var createdAt: Date
    var updatedAt: Date
    var createdByID: UUID?
    var createdByName: String?

    enum FileType: String {
        case pdf, image

        var fileExtension: String { self == .pdf ? "pdf" : "jpg" }
        var contentType: String { self == .pdf ? "application/pdf" : "image/jpeg" }
    }

    var type: FileType { FileType(rawValue: fileType) ?? .pdf }

    /// Maximum length of a title, also enforced by Postgres.
    static let maxTitleLength = 80
    /// Maximum file size, same as the bucket limit (20 MB).
    static let maxFileSize = 20 * 1024 * 1024

    init(
        id: UUID = UUID(),
        title: String,
        categoryID: UUID? = nil,
        filePath: String = "",
        fileType: FileType = .pdf,
        fileSize: Int = 0,
        pageCount: Int = 1,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.filePath = filePath
        self.fileType = fileType.rawValue
        self.fileSize = fileSize
        self.pageCount = pageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}

/// A folder for documents, created by the family. Every group starts with
/// the `isDefault` ones (seeded by Postgres), whose `name` is an English
/// key shown localized; custom ones show their name as typed.
@Model
final class DocumentCategory {
    var id: UUID
    var name: String
    /// `ALIIcon` token.
    var icon: String
    var isDefault: Bool
    var position: Int
    var createdAt: Date

    /// Maximum length of a name, also enforced by Postgres.
    static let maxNameLength = 40

    /// Icons a category can take.
    static let iconOptions: [String] = [
        ALIIcon.archive, ALIIcon.receipt, ALIIcon.euro, ALIIcon.coins, ALIIcon.user, ALIIcon.health,
        ALIIcon.pill, ALIIcon.home, ALIIcon.car, ALIIcon.school, ALIIcon.graduation, ALIIcon.pet,
        ALIIcon.plane, ALIIcon.laptop, ALIIcon.shopping, ALIIcon.bookmark,
    ]

    /// Name to show: default categories are translated.
    var displayName: String {
        isDefault ? String(localized: String.LocalizationValue(name)) : name
    }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = ALIIcon.archive,
        isDefault: Bool = false,
        position: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isDefault = isDefault
        self.position = position
        self.createdAt = createdAt
    }
}
