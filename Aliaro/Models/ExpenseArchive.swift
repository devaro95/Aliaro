import Foundation
import SwiftData

/// A closed-off period of the group's finances: when someone "archives"
/// the current finances, every transaction at that moment is frozen into
/// a `ExpenseArchiveSnapshot` under a name, and the live list starts
/// again from zero. The snapshot is self-contained (names, categories and
/// the balance between members are copied, not referenced), so an archive
/// keeps reading exactly as it was even if people leave the group or
/// categories are renamed later. Can be exported to PDF.
@Model
final class ExpenseArchive {
    var id: UUID
    var name: String
    /// Earliest and latest `occurredAt` among the archived transactions.
    var startDate: Date
    var endDate: Date
    var archivedByName: String?
    /// JSON-encoded `ExpenseArchiveSnapshot`.
    var snapshotData: Data
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        endDate: Date,
        archivedByName: String?,
        snapshot: ExpenseArchiveSnapshot,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.archivedByName = archivedByName
        self.snapshotData = (try? JSONEncoder().encode(snapshot)) ?? Data()
        self.createdAt = createdAt
    }

    var snapshot: ExpenseArchiveSnapshot {
        (try? JSONDecoder().decode(ExpenseArchiveSnapshot.self, from: snapshotData)) ?? ExpenseArchiveSnapshot(items: [], settlements: [])
    }
}

/// Frozen content of an `ExpenseArchive`. Dates are stored as seconds
/// since 1970 so the JSON reads the same locally and in Supabase (`jsonb`).
struct ExpenseArchiveSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var amount: Double
        var isIncome: Bool
        var personName: String
        /// Category names, already resolved (archives made before the SVG
        /// icons stored "<emoji> Name" labels instead).
        var categories: [String]
        var emoji: String
        var occurredAt: Double

        var date: Date { Date(timeIntervalSince1970: occurredAt) }

        /// Category names, dropping the leading emoji of legacy labels.
        var categoryNames: [String] {
            categories.map { label in
                let parts = label.split(separator: " ", maxSplits: 1)
                guard parts.count == 2, parts[0].unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) else { return label }
                return String(parts[1])
            }
        }
    }

    struct Settlement: Codable, Equatable {
        var from: String
        var to: String
        var amount: Double
    }

    /// Newest first, same order as the Finances list.
    var items: [Item]
    /// Who owed whom at the moment of archiving.
    var settlements: [Settlement]

    var totalExpenses: Double { items.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount } }
    var totalIncome: Double { items.filter(\.isIncome).reduce(0) { $0 + $1.amount } }
    /// Expenses minus income.
    var net: Double { totalExpenses - totalIncome }

    init(items: [Item], settlements: [Settlement]) {
        self.items = items
        self.settlements = settlements
    }

    /// Freezes the given transactions (and the balance between `members`).
    init(expenses: [Expense], categories: [ExpenseCategory], members: [FamilyMember]) {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = expenses
            .sorted { $0.occurredAt > $1.occurredAt }
            .map { expense in
                let cats = expense.categoryIDs.compactMap { byID[$0] }
                return Item(
                    id: expense.id,
                    name: expense.name,
                    amount: expense.amount,
                    isIncome: expense.isIncome,
                    personName: expense.personName,
                    categories: cats.map(\.name),
                    emoji: cats.first?.emoji ?? (expense.isIncome ? ALIIcon.coins : ALIIcon.receipt),
                    occurredAt: expense.occurredAt.timeIntervalSince1970
                )
            }
        settlements = FinanceBalances.settlements(expenses: expenses, members: members).map {
            Settlement(from: $0.from.name, to: $0.to.name, amount: $0.amount)
        }
    }
}
