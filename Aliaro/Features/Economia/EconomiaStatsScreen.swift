import SwiftUI
import Charts

/// Expense statistics, grouped by week, month or year. Income isn't
/// shown as a separate concept: each income is simply subtracted from
/// the expenses of the period it occurs in. Also breaks down expenses
/// of the current period by category.
struct EconomiaStatsScreen: View {
    @Environment(\.dismiss) private var dismiss
    let expenses: [Expense]
    let categories: [ExpenseCategory]

    private enum Period: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }

        var lowercaseLabel: String {
            switch self {
            case .week: return String(localized: "week")
            case .month: return String(localized: "month")
            case .year: return String(localized: "year")
            }
        }

        var component: Calendar.Component {
            switch self {
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }

        var bucketCount: Int {
            switch self {
            case .week: return 8
            case .month: return 6
            case .year: return 4
            }
        }
    }

    private struct Bucket: Identifiable {
        let id = UUID()
        let start: Date
        let label: String
        /// Expenses for the period minus income for the same period. Can
        /// come out negative if there was more income than expenses.
        var net: Double = 0
    }

    private struct CategoryTotal: Identifiable {
        let id: UUID
        let name: String
        let emoji: String
        var amount: Double = 0
    }

    @State private var period: Period = .week

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("", selection: $period) {
                        ForEach(Period.allCases) { p in
                            Text(LocalizedStringKey(p.rawValue)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    summaryCard
                    chartCard
                    categoryCard
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var buckets: [Bucket] {
        let calendar = Calendar.current
        guard let currentStart = calendar.dateInterval(of: period.component, for: .now)?.start else { return [] }

        var starts: [Date] = []
        for offset in stride(from: period.bucketCount - 1, through: 0, by: -1) {
            if let date = calendar.date(byAdding: period.component, value: -offset, to: currentStart) {
                starts.append(date)
            }
        }

        var result = starts.map { Bucket(start: $0, label: label(for: $0)) }

        for expense in expenses {
            guard let bucketStart = calendar.dateInterval(of: period.component, for: expense.occurredAt)?.start,
                  let index = result.firstIndex(where: { $0.start == bucketStart }) else { continue }
            result[index].net += expense.isIncome ? -expense.amount : expense.amount
        }
        return result
    }

    private func label(for date: Date) -> String {
        let formatter = DateFormatter()
        switch period {
        case .week: formatter.dateFormat = "d MMM"
        case .month: formatter.dateFormat = "MMM"
        case .year: formatter.dateFormat = "yyyy"
        }
        return formatter.string(from: date)
    }

    private var totalNet: Double { buckets.reduce(0) { $0 + $1.net } }

    private var summaryCard: some View {
        ALICard {
            HStack {
                summaryItem(title: "Expenses", value: totalNet, color: totalNet >= 0 ? ALIColors.error : ALIColors.success)
            }
        }
    }

    private func summaryItem(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
            Text(value.formattedEuros)
                .font(ALITypography.titleLarge)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private var chartCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Expenses by \(period.lowercaseLabel)")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                if buckets.allSatisfy({ $0.net == 0 }) {
                    Text("There are no transactions in this period yet.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart(buckets) { bucket in
                        BarMark(
                            x: .value("Period", bucket.label),
                            y: .value("Amount", bucket.net)
                        )
                        .foregroundStyle(bucket.net >= 0 ? ALIColors.error : ALIColors.success)
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    // MARK: Category breakdown

    /// Expenses (not income) that fall within the current week/month/year,
    /// matching whatever period is selected above.
    private var currentPeriodExpenses: [Expense] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: period.component, for: .now) else { return [] }
        return expenses.filter { !$0.isIncome && $0.occurredAt >= interval.start && $0.occurredAt < interval.end }
    }

    /// An expense with several categories counts its full amount under
    /// each one (e.g. a 100€ trip tagged "Travel" + "Dining out" adds 100€
    /// to both totals) — this is a breakdown by tag, not a split of the
    /// spend, so the total across categories can exceed the period's total.
    private var categoryTotals: [CategoryTotal] {
        var totals: [UUID: CategoryTotal] = [:]
        var uncategorizedAmount: Double = 0
        for expense in currentPeriodExpenses {
            if expense.categoryIDs.isEmpty {
                uncategorizedAmount += expense.amount
                continue
            }
            for categoryID in expense.categoryIDs {
                guard let category = categories.first(where: { $0.id == categoryID }) else { continue }
                totals[categoryID, default: CategoryTotal(id: categoryID, name: category.name, emoji: category.emoji)].amount += expense.amount
            }
        }
        var result = Array(totals.values)
        if uncategorizedAmount > 0 {
            result.append(CategoryTotal(id: UUID(), name: "Uncategorized", emoji: "❔", amount: uncategorizedAmount))
        }
        return result.sorted { $0.amount > $1.amount }
    }

    private var categoryTotalSum: Double { categoryTotals.reduce(0) { $0 + $1.amount } }

    private var categoryCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("By category this \(period.lowercaseLabel)")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                if categoryTotals.isEmpty {
                    Text("There are no expenses in this period yet.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 14) {
                        ForEach(categoryTotals) { total in
                            categoryRow(total)
                        }
                    }
                }
            }
        }
    }

    private func categoryRow(_ total: CategoryTotal) -> some View {
        let share = categoryTotalSum > 0 ? total.amount / categoryTotalSum : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(total.emoji) \(total.name)")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Spacer()
                Text(total.amount.formattedEuros)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ALIColors.surfaceVariant)
                    Capsule()
                        .fill(ALIColors.economiaAccent)
                        .frame(width: geometry.size.width * share)
                }
            }
            .frame(height: 8)
        }
    }
}
