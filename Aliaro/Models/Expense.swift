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

/// A reimbursement between two members ("X pays Y"): settles all or part of
/// what one owes the other in the balance. It isn't an expense or income
/// of the family, so it doesn't count in totals or statistics — only in
/// the balance (`FinanceBalances`). Kept in its own table
/// (`expense_settlements`) so older app versions don't read it as an expense.
/// Archiving the finances clears them (a database trigger) after copying
/// them into the archive's snapshot.
@Model
final class ExpenseSettlement {
    var id: UUID
    /// Who pays (the member who owed money).
    var fromMemberID: UUID
    var fromName: String
    /// Who gets paid.
    var toMemberID: UUID
    var toName: String
    var amount: Double
    var occurredAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        fromMemberID: UUID,
        fromName: String,
        toMemberID: UUID,
        toName: String,
        amount: Double,
        occurredAt: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.fromMemberID = fromMemberID
        self.fromName = fromName
        self.toMemberID = toMemberID
        self.toName = toName
        self.amount = amount
        self.occurredAt = occurredAt
        self.createdAt = createdAt
    }
}

