import Foundation
import SwiftData

/// A spending category within the family group (e.g. "Groceries",
/// "Transport"), used to classify expenses/income and break down the
/// statistics. Every group starts out with `defaults`, and members can
/// add their own categories on top of those.
@Model
final class ExpenseCategory {
    var id: UUID
    var name: String
    var emoji: String
    var isDefault: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🏷️",
        isDefault: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.isDefault = isDefault
        self.createdAt = createdAt
    }
}

extension ExpenseCategory {
    /// The 7 categories every family group starts out with.
    static let defaults: [(name: String, emoji: String)] = [
        ("Groceries", "🛒"),
        ("Housing", "🏠"),
        ("Transport", "🚗"),
        ("Dining out", "🍽️"),
        ("Entertainment", "🎬"),
        ("Shopping", "🛍️"),
        ("Other", "🔖")
    ]
}
