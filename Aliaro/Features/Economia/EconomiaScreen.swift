import SwiftUI
import SwiftData

/// "Finances" tab: family group expenses and income, split equally
/// among all its members. Shows the resulting balance (who owes
/// whom), the transaction history (with search and date filter), and
/// gives access to week/month/year statistics.
struct EconomiaScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query(sort: \Expense.occurredAt, order: .reverse) private var expenses: [Expense]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @Query(sort: \ExpenseCategory.createdAt) private var categories: [ExpenseCategory]

    @State private var showAddSheet = false
    @State private var showStats = false
    @State private var expensePendingDelete: Expense?
    @State private var expenseToEdit: Expense?
    @State private var showPaywall = false

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    private var canAdd: Bool { currentMember?.can(.financesAdd) ?? true }
    private var canEdit: Bool { currentMember?.can(.financesEdit) ?? true }
    private var canDelete: Bool { currentMember?.can(.financesDelete) ?? true }
    /// Statistics need a subscription if `economiaStats` is currently premium.
    private var isStatsLocked: Bool { premium.isLocked(.economiaStats) }

    @State private var searchText = ""
    @State private var showDateFilterSheet = false
    @State private var filterStartDate: Date?
    @State private var filterEndDate: Date?

    var body: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Finances", accent: ALIColors.economiaAccent) {
                    HStack(spacing: 10) {
                        Button {
                            if isStatsLocked { showPaywall = true } else { showStats = true }
                        } label: {
                            Image(systemName: "chart.pie.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(ALIColors.ink)
                                .frame(width: 40, height: 40)
                                .background(ALIColors.surfaceVariant)
                                .clipShape(Circle())
                                .aliPremiumLockOverlay(isStatsLocked)
                        }
                        if canAdd {
                            ALIFloatingButton(accent: ALIColors.economiaAccent) { showAddSheet = true }
                                .scaleEffect(0.72)
                        }
                    }
                }

                if members.count > 1 {
                    balancesCard
                }

                if !expenses.isEmpty {
                    searchAndFilterBar
                }

                if expenses.isEmpty {
                    ALIEmptyState(
                        emoji: "💶",
                        title: "No transactions",
                        subtitle: "Add the group's first expense or income."
                    )
                } else if filteredExpenses.isEmpty {
                    ALIEmptyState(
                        emoji: "🔍",
                        title: "No results",
                        subtitle: "Try another name, amount, or date."
                    )
                } else {
                    ALICard {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredExpenses.enumerated()), id: \.element.id) { index, expense in
                                ExpenseRow(
                                    expense: expense,
                                    categories: categories.filter { expense.categoryIDs.contains($0.id) },
                                    canEdit: canEdit,
                                    canDelete: canDelete,
                                    onEdit: { expenseToEdit = expense },
                                    onDelete: { expensePendingDelete = expense }
                                )
                                if index < filteredExpenses.count - 1 {
                                    Divider().overlay(ALIColors.outline)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .sheet(isPresented: $showAddSheet) {
            AddExpenseSheet(expenseToEdit: nil)
        }
        .sheet(item: $expenseToEdit) { expense in
            AddExpenseSheet(expenseToEdit: expense)
        }
        .sheet(isPresented: $showStats) {
            EconomiaStatsScreen(expenses: expenses, categories: categories)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showDateFilterSheet) {
            EconomiaDateFilterSheet(startDate: filterStartDate, endDate: filterEndDate) { start, end in
                filterStartDate = start
                filterEndDate = end
            }
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { expensePendingDelete != nil }, set: { if !$0 { expensePendingDelete = nil } }),
            itemName: expensePendingDelete?.name ?? ""
        ) {
            if let expense = expensePendingDelete {
                let id = expense.id
                let expenseName = expense.name
                modelContext.delete(expense)
                dataSync.deleteExpense(id: id)
                if let familyID = familySession.familyID {
                    dataSync.logActivity(
                        entityType: "expense", entityName: expenseName, action: "deleted",
                        actorID: familySession.memberID,
                        actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                        familyID: familyID, modelContext: modelContext
                    )
                }
            }
            expensePendingDelete = nil
        }
    }

    // MARK: Search and filter

    private var filteredExpenses: [Expense] {
        expenses.filter { expense in
            let trimmedQuery = searchText.trimmed
            if !trimmedQuery.isEmpty {
                let query = trimmedQuery.lowercased()
                let nameMatches = expense.name.lowercased().contains(query)
                let amountMatches = expense.amount.matchesAmountQuery(query)
                guard nameMatches || amountMatches else { return false }
            }
            if let start = filterStartDate {
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: start)
                let endDay = filterEndDate ?? start
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDay)) ?? dayStart
                guard expense.occurredAt >= dayStart && expense.occurredAt < dayEnd else { return false }
            }
            return true
        }
    }

    private var searchAndFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ALIColors.mutedInk)
                    TextField("Search by name or amount", text: $searchText)
                        .foregroundStyle(ALIColors.ink)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(ALIColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ALIColors.outline, lineWidth: 1)
                )

                Button {
                    showDateFilterSheet = true
                } label: {
                    Image(systemName: filterStartDate != nil ? "calendar.badge.checkmark" : "calendar")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(filterStartDate != nil ? ALIColors.economiaAccent : ALIColors.ink)
                        .frame(width: 48, height: 48)
                        .background(ALIColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(filterStartDate != nil ? ALIColors.economiaAccent : ALIColors.outline, lineWidth: 1)
                        )
                }
            }

            if let start = filterStartDate {
                HStack(spacing: 6) {
                    Text(dateFilterLabel(start: start, end: filterEndDate))
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                    Button {
                        filterStartDate = nil
                        filterEndDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dateFilterLabel(start: Date, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        if let end, !Calendar.current.isDate(end, inSameDayAs: start) {
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
        return formatter.string(from: start)
    }

    // MARK: Balances

    /// Net balance for each member, splitting every expense/income
    /// equally among everyone: positive = owed to them, negative = owes the group.
    private var balances: [UUID: Double] {
        guard members.count > 1 else { return [:] }
        let n = Double(members.count)
        var result: [UUID: Double] = [:]
        for member in members { result[member.id] = 0 }
        for expense in expenses {
            let share = expense.amount / n
            let sign: Double = expense.isIncome ? -1 : 1
            for member in members {
                if member.id == expense.personID {
                    result[member.id, default: 0] += sign * (expense.amount - share)
                } else {
                    result[member.id, default: 0] -= sign * share
                }
            }
        }
        return result
    }

    /// Pairs debtors with creditors to settle all balances with the
    /// fewest possible transfers.
    private var settlements: [(from: FamilyMember, to: FamilyMember, amount: Double)] {
        var creditors: [(FamilyMember, Double)] = []
        var debtors: [(FamilyMember, Double)] = []
        for member in members {
            let balance = balances[member.id] ?? 0
            if balance > 0.01 { creditors.append((member, balance)) }
            else if balance < -0.01 { debtors.append((member, -balance)) }
        }
        creditors.sort { $0.1 > $1.1 }
        debtors.sort { $0.1 > $1.1 }

        var result: [(from: FamilyMember, to: FamilyMember, amount: Double)] = []
        var i = 0, j = 0
        while i < debtors.count, j < creditors.count {
            let amount = min(debtors[i].1, creditors[j].1)
            result.append((from: debtors[i].0, to: creditors[j].0, amount: amount))
            debtors[i].1 -= amount
            creditors[j].1 -= amount
            if debtors[i].1 < 0.01 { i += 1 }
            if creditors[j].1 < 0.01 { j += 1 }
        }
        return result
    }

    private var balancesCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Balance between you")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                if settlements.isEmpty {
                    Text(expenses.isEmpty ? "There's nothing to split yet." : "You're all even, no one owes anything.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(settlements.enumerated()), id: \.offset) { _, settlement in
                            HStack(spacing: 6) {
                                Text(settlement.from.name).fontWeight(.semibold)
                                Text("owes")
                                Text(settlement.to.name).fontWeight(.semibold)
                                Spacer()
                                Text(settlement.amount.formattedEuros)
                                    .foregroundStyle(ALIColors.error)
                            }
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.ink)
                        }
                    }
                }
            }
        }
    }
}

/// Row for a transaction: name, who carried it out, when, and the
/// amount (green if it's income), with actions to edit or delete it.
private struct ExpenseRow: View {
    let expense: Expense
    /// This expense's own categories, already resolved (order matches
    /// `expense.categoryIDs`; empty if uncategorized or they were deleted).
    let categories: [ExpenseCategory]
    var canEdit: Bool = true
    var canDelete: Bool = true
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var subtitle: String {
        var parts: [String] = []
        if !categories.isEmpty { parts.append(categories.map(\.name).joined(separator: ", ")) }
        parts.append(expense.personName)
        parts.append(expense.occurredAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(categories.first?.emoji ?? (expense.isIncome ? "💰" : "🧾"))
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.name)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
            }
            Spacer()
            Text((expense.isIncome ? "+" : "-") + expense.amount.formattedEuros)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(expense.isIncome ? ALIColors.success : ALIColors.ink)
            if canEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }
}

/// Sheet to filter the history by date with a custom calendar: the
/// first tap marks the start day and the second the end day, joining
/// both with a continuous background so the range is visible at a
/// glance (if they match, the filter is left on that single day).
private struct EconomiaDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onApply: (Date?, Date?) -> Void

    @State private var startDate: Date?
    @State private var endDate: Date?

    init(startDate: Date?, endDate: Date?, onApply: @escaping (Date?, Date?) -> Void) {
        self.onApply = onApply
        _startDate = State(initialValue: startDate)
        _endDate = State(initialValue: endDate)
    }

    private var statusText: String {
        guard let start = startDate else { return String(localized: "Tap the start day on the calendar.") }
        guard let end = endDate else {
            return String(localized: "Start: \(formatted(start)). Tap the end day (or the same one, for a single day).")
        }
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return String(localized: "Single day: \(formatted(start)).")
        }
        return String(localized: "From \(formatted(start)) to \(formatted(end)).")
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                EconomiaRangeCalendar(startDate: $startDate, endDate: $endDate, accent: ALIColors.economiaAccent)

                Text(statusText)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                ALIPrimaryButton(text: "Apply filter", enabled: startDate != nil, accent: ALIColors.economiaAccent) {
                    onApply(startDate, endDate ?? startDate)
                    dismiss()
                }

                ALITextButton(text: "Remove filter") {
                    onApply(nil, nil)
                    dismiss()
                }
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationTitle("Filter by date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Custom monthly calendar (visible month + day grid) that allows
/// marking a start and end day by tapping them directly, joining the
/// range with a continuous background between them — something a
/// system `DatePicker` doesn't let you show.
private struct EconomiaRangeCalendar: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    let accent: Color

    @State private var visibleMonth: Date

    private let calendar = Calendar.current
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    init(startDate: Binding<Date?>, endDate: Binding<Date?>, accent: Color) {
        self._startDate = startDate
        self._endDate = endDate
        self.accent = accent
        self._visibleMonth = State(initialValue: startDate.wrappedValue ?? .now)
    }

    private enum DayRole { case none, single, start, end, between }

    /// Height of each calendar cell, and height of the indicator
    /// (selection circle and band connecting it to the next day) within
    /// it — the same for both, so the band doesn't look more "square"
    /// than the start and end circles.
    private let cellHeight: CGFloat = 40
    private let indicatorInset: CGFloat = 4
    private var indicatorHeight: CGFloat { cellHeight - indicatorInset * 2 }

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            daysGrid
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(ALIColors.ink)
                    .frame(width: 32, height: 32)
            }
            Spacer()
            Text(monthTitle)
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
            Spacer()
            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(ALIColors.ink)
                    .frame(width: 32, height: 32)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(daysInGrid.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: visibleMonth).capitalized
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) {
            visibleMonth = newMonth
        }
    }

    /// Days of the visible month, with `nil` padding for the gaps
    /// before day 1 (starting the week on Monday).
    private var daysInGrid: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstOfMonth = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstOfMonth) // 1 = Sunday ... 7 = Saturday
        let mondayFirstOffset = (weekday + 5) % 7 // 0 = Monday ... 6 = Sunday
        let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 30

        var result: [Date?] = Array(repeating: nil, count: mondayFirstOffset)
        for offset in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                result.append(date)
            }
        }
        return result
    }

    private func role(for date: Date) -> DayRole {
        let day = calendar.startOfDay(for: date)
        guard let start = startDate.map({ calendar.startOfDay(for: $0) }) else { return .none }
        guard let end = endDate.map({ calendar.startOfDay(for: $0) }) else {
            return day == start ? .single : .none
        }
        if start == end { return day == start ? .single : .none }
        if day == start { return .start }
        if day == end { return .end }
        if day > start && day < end { return .between }
        return .none
    }

    private func dayCell(_ date: Date) -> some View {
        let role = role(for: date)
        let isToday = calendar.isDateInToday(date)
        return Text("\(calendar.component(.day, from: date))")
            .font(ALITypography.bodyMedium)
            .fontWeight(isToday ? .bold : .regular)
            .foregroundStyle(role == .none ? ALIColors.ink : ALIColors.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(rangeBackground(for: role))
            .contentShape(Rectangle())
            .onTapGesture { select(date) }
    }

    /// Day background: a rectangle spanning the full cell width for
    /// days in the middle of the range (so they join without gaps
    /// between cells), and a solid circle for the selected day itself —
    /// including, for the start and end of a range, half a rectangle
    /// connecting it to the neighboring day.
    @ViewBuilder
    private func rangeBackground(for role: DayRole) -> some View {
        switch role {
        case .none:
            Color.clear
        case .single:
            Circle().fill(accent).frame(height: indicatorHeight)
        case .between:
            Rectangle().fill(accent.opacity(0.25)).frame(height: indicatorHeight)
        case .start:
            HStack(spacing: 0) {
                Color.clear
                Rectangle().fill(accent.opacity(0.25)).frame(height: indicatorHeight)
            }
            .overlay(Circle().fill(accent).frame(width: indicatorHeight, height: indicatorHeight))
        case .end:
            HStack(spacing: 0) {
                Rectangle().fill(accent.opacity(0.25)).frame(height: indicatorHeight)
                Color.clear
            }
            .overlay(Circle().fill(accent).frame(width: indicatorHeight, height: indicatorHeight))
        }
    }

    private func select(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        guard let start = startDate.map({ calendar.startOfDay(for: $0) }), endDate == nil else {
            startDate = day
            endDate = nil
            return
        }
        if day == start {
            endDate = start
        } else if day < start {
            startDate = day
            endDate = start
        } else {
            endDate = day
        }
    }
}

extension Double {
    /// Euro currency format, consistent across the whole finances section.
    var formattedEuros: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f €", self)
    }

    /// Indicates whether this amount matches a free-text search,
    /// accepting both comma and period as the decimal separator (e.g. "12,5" or "12.50").
    func matchesAmountQuery(_ query: String) -> Bool {
        let normalizedQuery = query.replacingOccurrences(of: ",", with: ".")
        let decimalForm = String(format: "%.2f", self)
        let wholeForm = truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : decimalForm
        return decimalForm.contains(normalizedQuery) || wholeForm.contains(normalizedQuery)
    }
}
