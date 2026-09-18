import Foundation
import SwiftData

/// An item in the household's own catalog (e.g. "Milk", "Toilet paper").
/// Created once and then added as many times as needed to the
/// active shopping list.
@Model
final class GroceryItem {
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
