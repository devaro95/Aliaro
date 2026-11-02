import Foundation
import SwiftData

/// A household list (a "tab"): groups `ShoppingListEntry` items under a
/// name (e.g. "Groceries", "Pharmacy", "Gifts"). Every family has at least
/// one, created automatically when the group is created.
///
/// A list can be private: chosen when it's created (can't be changed
/// later), only its creator (`ownerMemberID`) sees it and its products —
/// Supabase doesn't send it to anyone else.
@Model
final class ShoppingList {
    var id: UUID
    var name: String
    var position: Int
    var createdAt: Date
    var ownerMemberID: UUID?

    init(id: UUID = UUID(), name: String, position: Int = 0, ownerMemberID: UUID? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.position = position
        self.ownerMemberID = ownerMemberID
        self.createdAt = createdAt
    }

    var isPrivate: Bool { ownerMemberID != nil }

    /// English name of the default list. Groups created from iOS before
    /// 1.2 stored it untranslated, so it's shown translated.
    static let defaultName = "Shopping list"

    /// Name to show: the default list translated, any other as typed.
    var displayName: String {
        name == ShoppingList.defaultName ? String(localized: "Shopping list") : name
    }
}
