import Foundation
import SwiftData

/// A household shopping list (a "tab"): groups `ShoppingListEntry` items
/// under a name (e.g. "Groceries", "Furniture"). Every family has at least
/// one, created automatically when the group is created.
@Model
final class ShoppingList {
    var id: UUID
    var name: String
    var position: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, position: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.position = position
        self.createdAt = createdAt
    }

    /// English name of the default list. Groups created from iOS before
    /// 1.2 stored it untranslated, so it's shown translated.
    static let defaultName = "Shopping list"

    /// Name to show: the default list translated, any other as typed.
    var displayName: String {
        name == ShoppingList.defaultName ? String(localized: "Shopping list") : name
    }
}
