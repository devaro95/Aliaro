import Foundation
import SwiftData

/// An entry in the active shopping list: a catalog item added to the
/// shopping list, markable as purchased. `itemID` references the source
/// `GroceryItem` (not a SwiftData relationship) — `name` is copied so
/// the entry stays readable even if the catalog item changes or is
/// deleted.
@Model
final class ShoppingListEntry {
    var id: UUID
    var itemID: UUID
    var listID: UUID = UUID()
    var name: String
    var isChecked: Bool
    var addedAt: Date
    var checkedAt: Date?

    init(
        id: UUID = UUID(),
        itemID: UUID,
        listID: UUID,
        name: String,
        isChecked: Bool = false,
        addedAt: Date = .now,
        checkedAt: Date? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.listID = listID
        self.name = name
        self.isChecked = isChecked
        self.addedAt = addedAt
        self.checkedAt = checkedAt
    }
}
