import Foundation
import SwiftData

/// A product in a list's own catalog (e.g. "Milk", "Toilet paper").
/// Each product belongs to one list (`listID`): it's created once and then
/// added as many times as needed to that list. Other lists can copy it
/// ("add from another list"). `listID` nil = created before products
/// belonged to a list (treated as the first list's).
@Model
final class GroceryItem {
    var id: UUID
    var name: String
    var createdAt: Date
    var listID: UUID?

    init(id: UUID = UUID(), name: String, listID: UUID? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.listID = listID
        self.createdAt = createdAt
    }

    /// Whether it belongs to `list` (old products without a list count as
    /// the first list's).
    func belongs(to listID: UUID, firstListID: UUID?) -> Bool {
        self.listID == listID || (self.listID == nil && listID == firstListID)
    }
}
