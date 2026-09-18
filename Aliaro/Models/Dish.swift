import Foundation
import SwiftData

/// A dish in the household's own catalog (e.g. "Lentils", "Omelette"). Created
/// once and then chosen for lunch or dinner on any day of the weekly menu.
@Model
final class Dish {
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
