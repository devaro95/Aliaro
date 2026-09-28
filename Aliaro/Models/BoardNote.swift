import Foundation
import SwiftData

/// A short note pinned to the family's "Board": something everyone should
/// keep in mind (the Wi-Fi password, "the plumber comes Thursday"…). It has
/// no date — it stays on the Board and on Home until someone deletes it.
/// `position` is the order chosen on the Board (ascending), also used on Home.
/// A note is for everyone by default; assigned to specific people
/// (`memberIDs`) it only shows up for them (and, on the Board, for whoever
/// pinned it, so they can still edit or delete it).
@Model
final class BoardNote {
    var id: UUID
    var text: String
    /// Index into `BoardNote.colors` (sticky-note color).
    var colorIndex: Int
    /// Manual order on the Board (lower first). New notes go on top.
    var position: Int = 0
    /// For the whole family, or only for `memberIDs` (references to `FamilyMember`).
    var forEveryone: Bool = true
    var memberIDs: [UUID] = []
    var createdAt: Date
    var updatedAt: Date
    /// Who pinned it (reference to `FamilyMember`, not a SwiftData
    /// relationship). The name is copied so it survives them leaving.
    var createdByID: UUID?
    var createdByName: String?

    /// Whether the note is addressed to this member (Home shows only these).
    func isFor(_ memberID: UUID?) -> Bool {
        guard !forEveryone else { return true }
        guard let memberID else { return false }
        return memberIDs.contains(memberID)
    }

    /// Whether it appears on this member's Board: addressed to them, or
    /// pinned by them.
    func isVisibleOnBoard(to memberID: UUID?) -> Bool {
        isFor(memberID) || (memberID != nil && createdByID == memberID)
    }

    /// Maximum length of a note, also enforced by Postgres.
    static let maxLength = 500

    init(
        id: UUID = UUID(),
        text: String,
        colorIndex: Int = 0,
        position: Int = 0,
        forEveryone: Bool = true,
        memberIDs: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.colorIndex = colorIndex
        self.position = position
        self.forEveryone = forEveryone
        self.memberIDs = memberIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}
