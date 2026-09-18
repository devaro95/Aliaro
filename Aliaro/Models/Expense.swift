import Foundation
import SwiftData

/// An expense or income for the family group. `isIncome` distinguishes
/// whether the amount left (expense) or entered (income) the shared pot.
/// `personID`/`personName` is who carried it out — who paid the expense,
/// or who received the income — and is the basis for calculating, by
/// splitting each amount equally among all members, how much each one
/// owes the rest. `categoryIDs` classifies it under one or more
/// `ExpenseCategory` (e.g. "Groceries" + "Travel") for the statistics
/// breakdown by category.
@Model
final class Expense {
    var id: UUID
    var name: String
    var amount: Double
    var isIncome: Bool
    /// Reference to `FamilyMember`, not a SwiftData relationship.
    var personID: UUID
    /// Copied so it stays readable even if that person leaves the group.
    var personName: String
    /// References to `ExpenseCategory`, not SwiftData relationships. Empty
    /// for expenses left uncategorized, or created before categories existed.
    var categoryIDs: [UUID]
    var occurredAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        isIncome: Bool = false,
        personID: UUID,
        personName: String,
        categoryIDs: [UUID] = [],
        occurredAt: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.isIncome = isIncome
        self.personID = personID
        self.personName = personName
        self.categoryIDs = categoryIDs
        self.occurredAt = occurredAt
        self.createdAt = createdAt
    }
}
