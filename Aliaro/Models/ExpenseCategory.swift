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
        emoji: String = ALIIcon.tag,
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
    /// Name to show. Default categories are stored with their English key
    /// ("Groceries") and shown translated; the family's own ones as typed.
    var displayName: String {
        guard isDefault else { return name }
        switch name {
        case "Groceries": return String(localized: "Groceries")
        case "Housing": return String(localized: "Housing")
        case "Transport": return String(localized: "Transport")
        case "Dining out": return String(localized: "Dining out")
        case "Entertainment": return String(localized: "Entertainment")
        // Own key: "Shopping" alone is the shopping list tab ("Compra").
        case "Shopping": return String(localized: "expense_category_shopping", defaultValue: "Shopping")
        case "Other": return String(localized: "Other")
        default: return name
        }
    }

    /// The 7 categories every family group starts out with.
    static let defaults: [(name: String, emoji: String)] = [
        ("Groceries", ALIIcon.cart),
        ("Housing", ALIIcon.home),
        ("Transport", ALIIcon.car),
        ("Dining out", ALIIcon.dining),
        ("Entertainment", ALIIcon.film),
        ("Shopping", ALIIcon.shopping),
        ("Other", ALIIcon.bookmark)
    ]
}
