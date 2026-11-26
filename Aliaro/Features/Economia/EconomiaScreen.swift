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

    @Query(sort: \Expense.occurredAt, order: .reverse) private var allExpenses: [Expense]
    /// What the screen actually renders: a fresh fetch, never the `@Query`
    /// array itself. When many expenses are deleted at once (archiving, or
    /// the burst of real-time deletes it triggers), `@Query` can hand back
    /// for one render objects SwiftData has already detached, and reading
    /// any attribute of those crashes ("backing data was detached…"). A
    /// fetch only ever returns live objects. `allExpenses` stays only as
    /// the trigger that re-renders this view when expenses change.
    private var expenses: [Expense] {
        _ = allExpenses.count
        let descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @Query(sort: \ExpenseCategory.createdAt) private var categories: [ExpenseCategory]
    @Query(sort: \ExpenseSettlement.occurredAt, order: .reverse) private var allReimbursements: [ExpenseSettlement]
    /// Fresh fetch, for the same reason as `expenses` (archiving deletes them all at once).
    private var reimbursements: [ExpenseSettlement] {
        _ = allReimbursements.count
        let descriptor = FetchDescriptor<ExpenseSettlement>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    @EnvironmentObject private var familyService: FamilyService

    @State private var showAddSheet = false
    /// One-time question to the admin: keep or hide the balance for everyone.
    @State private var showBalancePrompt = false
    @State private var balancePromptHandled = false
    /// Debt the user tapped "Paid" on, waiting for confirmation.
    @State private var pendingPayment: PendingPayment?
    @State private var reimbursementPendingDelete: ReimbursementRowData?

    struct PendingPayment: Identifiable {
        let id = UUID()
        let fromID: UUID
        let fromName: String
        let toID: UUID
        let toName: String
        let amount: Double
    }
    @State private var showStats = false
    @State private var showArchives = false
    @State private var expensePendingDelete: Expense?
    @State private var expenseToEdit: Expense?
    @State private var showPaywall = false
    /// Top card: just your expenses and the family's total (default), or who owes whom.
    @AppStorage("economia.summaryMode") private var summaryMode: SummaryMode = .totals

    enum SummaryMode: String { case totals, balance }

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    /// Creator or admin: the ones who can show/hide the balance.
    private var isAdmin: Bool { currentMember.map { $0.isCreator || $0.isAdmin } ?? false }
    /// The admin can hide the balance for the whole group (`nil` = not chosen yet, shown).
    private var isBalanceEnabled: Bool { familySession.showBalance != false }
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
        trackedBody.trackScreen("finances")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Finances", accent: ALIColors.economiaAccent) {
                    HStack(spacing: 10) {
                        Button {
                            Track.event("finances_archives_tap", ["locked": premium.isLocked(.financeArchive)])
                            showArchives = true
                        } label: {
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(ALIColors.ink)
                                .frame(width: 40, height: 40)
                                .background(ALIColors.surfaceVariant)
                                .clipShape(Circle())
                                .aliPremiumPreviewOverlay(premium.isLocked(.financeArchive))
                        }
                        .accessibilityLabel("Archive")
                        Button {
                            Track.event("finances_stats_tap", ["locked": isStatsLocked])
                            showStats = true
                        } label: {
                            Image(systemName: "chart.pie.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(ALIColors.ink)
                                .frame(width: 40, height: 40)
                                .background(ALIColors.surfaceVariant)
                                .clipShape(Circle())
                                .aliPremiumPreviewOverlay(isStatsLocked)
                        }
                        if canAdd {
                            ALIFloatingButton(accent: ALIColors.economiaAccent) {
                                Track.event("expense_add_tap", ["transactions": expenses.count, "members": members.count])
                                showAddSheet = true
                            }
                                .scaleEffect(0.72)
                        }
                    }
                }

                if !members.isEmpty {
                    balancesCard
                }

                if !expenses.isEmpty || !reimbursements.isEmpty {
                    searchAndFilterBar
                }

                if expenses.isEmpty && reimbursements.isEmpty {
                    ALIEmptyState(
                        icon: ALIIcon.euro,
                        title: "No transactions",
                        subtitle: "Add the group's first expense or income."
                    )
                } else if filteredExpenses.isEmpty && filteredReimbursements.isEmpty {
                    ALIEmptyState(
                        icon: ALIIcon.search,
                        title: "No results",
                        subtitle: "Try another name, amount, or date."
                    )
                } else {
                    transactionList(listSections(expenses: rowData(for: filteredExpenses), reimbursements: filteredReimbursements))
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
        .sheet(isPresented: $showArchives) {
            ExpenseArchivesSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showBalancePrompt) {
            BalancePromptSheet { show in
                Track.event("finances_balance_prompt_answer", ["show": show])
                showBalancePrompt = false
                Task { try? await familyService.updateShowBalance(show) }
            }
        }
        .task(id: members.count) { askAboutBalanceIfNeeded() }
        .onChange(of: familySession.showBalance) { _, newValue in
            // Already answered (e.g. from another device): drop the question.
            if newValue != nil { showBalancePrompt = false }
        }
        // Own dialog (not the system alert): a clear full-screen cover so it
        // also dims the bottom bar; the dialog fades/scales itself in and out.
        .fullScreenCover(item: $pendingPayment) { payment in
            PaymentConfirmDialog(payment: payment) { confirmed in
                if confirmed { registerPayment(payment) }
                setPendingPayment(nil)
            }
            .presentationBackground(.clear)
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { reimbursementPendingDelete != nil }, set: { if !$0 { reimbursementPendingDelete = nil } }),
            itemName: reimbursementPendingDelete.map { String(localized: "\($0.fromName) pays \($0.toName)") } ?? ""
        ) {
            if let row = reimbursementPendingDelete {
                deleteReimbursement(row)
            }
            reimbursementPendingDelete = nil
        }
        .sheet(isPresented: $showDateFilterSheet) {
            EconomiaDateFilterSheet(startDate: filterStartDate, endDate: filterEndDate) { start, end in
                Track.event(start == nil ? "finances_date_filter_removed" : "finances_date_filter_applied", [
                    "days": start.flatMap { s in end.flatMap { Calendar.current.dateComponents([.day], from: s, to: $0).day } }.map { $0 + 1 }
                ])
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

    /// Copies each expense into a plain value right here in `body`, so the
    /// `ForEach` below never touches a SwiftData object. SwiftUI re-runs a
    /// `ForEach` row closure on its own (with the element it captured)
    /// whenever that object changes — including when it gets deleted. If
    /// the closure read the model (e.g. `categoryIDs`), deleting several
    /// expenses at once (archiving) made it read already-detached objects
    /// and crash.
    private func rowData(for expenses: [Expense]) -> [ExpenseRowData] {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return expenses.map { expense in
            let cats = expense.categoryIDs.compactMap { byID[$0] }
            return ExpenseRowData(
                id: expense.id,
                name: expense.name,
                amount: expense.amount,
                isIncome: expense.isIncome,
                personName: expense.personName,
                occurredAt: expense.occurredAt,
                emoji: cats.first?.emoji ?? (expense.isIncome ? ALIIcon.coins : ALIIcon.receipt),
                categoryNames: cats.map(\.displayName)
            )
        }
    }

    /// Plain-value copies of the reimbursements that match the search and date filter.
    private var filteredReimbursements: [ReimbursementRowData] {
        reimbursements.compactMap { r in
            let trimmedQuery = searchText.trimmed
            if !trimmedQuery.isEmpty {
                let query = trimmedQuery.lowercased()
                let nameMatches = r.fromName.lowercased().contains(query) || r.toName.lowercased().contains(query)
                guard nameMatches || r.amount.matchesAmountQuery(query) else { return nil }
            }
            if let start = filterStartDate {
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: start)
                let endDay = filterEndDate ?? start
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDay)) ?? dayStart
                guard r.occurredAt >= dayStart && r.occurredAt < dayEnd else { return nil }
            }
            return ReimbursementRowData(id: r.id, fromName: r.fromName, toName: r.toName, amount: r.amount, occurredAt: r.occurredAt)
        }
    }

    private enum ListSection: Identifiable {
        case expenses([ExpenseRowData])
        case reimbursement(ReimbursementRowData)

        var id: UUID {
            switch self {
            case .expenses(let rows): return rows[0].id
            case .reimbursement(let row): return row.id
            }
        }
    }

    /// Merges expenses and reimbursements by date (newest first): runs of
    /// consecutive expenses share one card, each reimbursement gets its own.
    private func listSections(expenses: [ExpenseRowData], reimbursements: [ReimbursementRowData]) -> [ListSection] {
        var sections: [ListSection] = []
        var run: [ExpenseRowData] = []
        var i = 0, j = 0
        while i < expenses.count || j < reimbursements.count {
            let takeExpense = j >= reimbursements.count || (i < expenses.count && expenses[i].occurredAt >= reimbursements[j].occurredAt)
            if takeExpense {
                run.append(expenses[i]); i += 1
            } else {
                if !run.isEmpty { sections.append(.expenses(run)); run = [] }
                sections.append(.reimbursement(reimbursements[j])); j += 1
            }
        }
        if !run.isEmpty { sections.append(.expenses(run)) }
        return sections
    }

    private func transactionList(_ sections: [ListSection]) -> some View {
        VStack(spacing: 12) {
            ForEach(sections) { section in
                switch section {
                case .expenses(let rows):
                    expenseList(rows)
                case .reimbursement(let row):
                    ReimbursementCard(from: row.fromName, to: row.toName, amount: row.amount, date: row.occurredAt)
                        .contextMenu {
                            if canDelete {
                                Button(role: .destructive) {
                                    Track.event("finances_reimbursement_delete_tap")
                                    reimbursementPendingDelete = row
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        }
    }

    private func expenseList(_ rows: [ExpenseRowData]) -> some View {
        ALICard {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ExpenseRow(
                        row: row,
                        canEdit: canEdit,
                        canDelete: canDelete,
                        onEdit: {
                            Track.event("expense_open", ["is_income": row.isIncome, "categories": row.categoryNames.count])
                            expenseToEdit = liveExpense(id: row.id)
                        },
                        onDelete: {
                            Track.event("expense_delete_tap", ["is_income": row.isIncome])
                            expensePendingDelete = liveExpense(id: row.id)
                        }
                    )
                    if index < rows.count - 1 {
                        Divider().overlay(ALIColors.outline)
                    }
                }
            }
        }
    }

    private func liveExpense(id: UUID) -> Expense? {
        try? modelContext.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first
    }

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
                        .onSubmit {
                            Track.event("finances_search", ["results": filteredExpenses.count, "query_length": searchText.trimmed.count])
                        }
                        .onChange(of: searchText.isEmpty) { _, isEmpty in
                            if !isEmpty { Track.event("finances_search_started") }
                        }
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
                    Track.event("finances_date_filter_tap", ["active": filterStartDate != nil])
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

    private var settlements: [(from: FamilyMember, to: FamilyMember, amount: Double)] {
        FinanceBalances.settlements(expenses: expenses, reimbursements: reimbursements, members: members)
    }

    /// The first time the admin opens Finances in a shared group, asks
    /// whether to keep the balance or hide it for everyone.
    private func askAboutBalanceIfNeeded() {
        guard !balancePromptHandled, isAdmin, members.count > 1, familySession.showBalance == nil else { return }
        balancePromptHandled = true
        Track.event("finances_balance_prompt_shown")
        showBalancePrompt = true
    }

    /// Shows/hides the payment dialog without the full-screen cover's slide-up
    /// animation (the dialog animates itself).
    private func setPendingPayment(_ payment: PendingPayment?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { pendingPayment = payment }
    }

    /// Records "X pays Y" for the whole debt: a reimbursement that leaves
    /// their balance at zero and shows up in the list.
    private func registerPayment(_ payment: PendingPayment) {
        guard let familyID = familySession.familyID else { return }
        let amount = (payment.amount * 100).rounded() / 100
        let reimbursement = ExpenseSettlement(
            fromMemberID: payment.fromID, fromName: payment.fromName,
            toMemberID: payment.toID, toName: payment.toName,
            amount: amount
        )
        modelContext.insert(reimbursement)
        try? modelContext.save()
        dataSync.pushExpenseSettlement(reimbursement, familyID: familyID)
        Track.event("finances_reimbursement_created", ["members": members.count])
        dataSync.logActivity(
            entityType: "expense", entityName: String(localized: "\(payment.fromName) pays \(payment.toName)"), action: "created",
            actorID: familySession.memberID,
            actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
            familyID: familyID, modelContext: modelContext
        )
    }

    private func deleteReimbursement(_ row: ReimbursementRowData) {
        let id = row.id
        if let live = try? modelContext.fetch(FetchDescriptor<ExpenseSettlement>(predicate: #Predicate { $0.id == id })).first {
            modelContext.delete(live)
            try? modelContext.save()
        }
        dataSync.deleteExpenseSettlement(id: id)
        if let familyID = familySession.familyID {
            dataSync.logActivity(
                entityType: "expense", entityName: String(localized: "\(row.fromName) pays \(row.toName)"), action: "deleted",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID, modelContext: modelContext
            )
        }
    }

    /// Expenses (not income) paid by you / by the whole family.
    private var myExpensesTotal: Double {
        guard let me = currentMember?.id else { return 0 }
        return expenses.filter { !$0.isIncome && $0.personID == me }.reduce(0) { $0 + $1.amount }
    }
    private var totalExpenses: Double {
        expenses.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private func setSummaryMode(_ mode: SummaryMode) {
        guard mode != summaryMode else { return }
        Track.event("finances_summary_mode", ["mode": mode.rawValue])
        summaryMode = mode
    }

    private func totalRow(_ label: LocalizedStringKey, _ amount: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(amount.formattedEuros).fontWeight(.semibold)
        }
        .font(ALITypography.bodyMedium)
        .foregroundStyle(ALIColors.ink)
    }

    private func summaryChip(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(ALITypography.labelLarge)
                .foregroundStyle(selected ? ALIColors.onAccent : ALIColors.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? ALIColors.economiaAccent : ALIColors.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : ALIColors.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var balancesCard: some View {
        // Alone in the family there's no balance, and the admin can hide it
        // for everyone: just the totals.
        let shared = members.count > 1 && isBalanceEnabled
        let totals = !shared || summaryMode == .totals
        return ALICard {
            VStack(alignment: .leading, spacing: 10) {
                // Header: title + switch between totals and balance.
                HStack(spacing: 6) {
                    Text(totals ? LocalizedStringKey("Expenses") : LocalizedStringKey("Balance between you"))
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                    Spacer()
                    if shared {
                        summaryChip("Totals", selected: totals) { setSummaryMode(.totals) }
                        summaryChip("Balance", selected: !totals) { setSummaryMode(.balance) }
                    }
                }

                if totals {
                    if members.count > 1 { totalRow("Your expenses", myExpensesTotal) }
                    totalRow("Total expenses", totalExpenses)
                } else if settlements.isEmpty {
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
                                if canAdd {
                                    Button {
                                        Track.event("finances_mark_paid_tap")
                                        setPendingPayment(PendingPayment(
                                            fromID: settlement.from.id, fromName: settlement.from.name,
                                            toID: settlement.to.id, toName: settlement.to.name,
                                            amount: settlement.amount
                                        ))
                                    } label: {
                                        Text("Paid")
                                            .font(ALITypography.labelLarge)
                                            .foregroundStyle(ALIColors.onAccent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(ALIColors.economiaAccent)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
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

/// Plain-value copy of an `Expense` for its row (see `rowData(for:)`).
private struct ExpenseRowData: Identifiable {
    let id: UUID
    let name: String
    let amount: Double
    let isIncome: Bool
    let personName: String
    let occurredAt: Date
    let emoji: String
    let categoryNames: [String]
}

/// Plain-value copy of an `ExpenseSettlement` for its card.
struct ReimbursementRowData: Identifiable {
    let id: UUID
    let fromName: String
    let toName: String
    let amount: Double
    let occurredAt: Date
}

/// Card for a reimbursement ("Lucía pays Varo · Reimbursement · date"):
/// pistachio tint with the amount in green and no +/− sign, since it only
/// moves money between members.
struct ReimbursementCard: View {
    let from: String
    let to: String
    let amount: Double
    let date: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 40, height: 40)
                .background(ALIColors.economiaAccent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(from) pays \(to)")
                    .font(ALITypography.bodyLarge.weight(.semibold))
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(2)
                Text("Reimbursement · \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(amount.formattedEuros)
                .font(ALITypography.bodyLarge.weight(.semibold))
                .fixedSize()
                .foregroundStyle(ALIColors.economiaStrong)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALIColors.economiaAccent.opacity(0.18))
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ALIColors.economiaAccent, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Confirmation before registering a reimbursement, in the app's style
/// (not the system alert): who pays whom with their initials, the amount
/// in big green, and pistachio / plain buttons. Fades and scales in over a
/// dimmed background; tapping outside cancels.
private struct PaymentConfirmDialog: View {
    let payment: EconomiaScreen.PendingPayment
    /// `true` = mark as paid, `false` = cancel. Called once the dialog has animated out.
    let onFinish: (Bool) -> Void

    @State private var visible = false

    var body: some View {
        ZStack {
            Color.black.opacity(visible ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture { close(false) }

            if visible {
                card
                    .padding(.horizontal, 28)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .trackScreen("finances_mark_paid_dialog")
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { visible = true }
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                avatar(payment.fromName, color: ALIColors.error)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ALIColors.mutedInk)
                avatar(payment.toName, color: ALIColors.economiaAccent)
            }
            .padding(.top, 4)

            VStack(spacing: 6) {
                Text("Mark as paid?")
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                Text(payment.amount.formattedEuros)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(ALIColors.economiaStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(payment.fromName) pays \(payment.toName). It will show up as a reimbursement and their balance will be settled.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ALIPrimaryButton(text: "Mark as paid", accent: ALIColors.economiaAccent) { close(true) }
                ALISecondaryButton(text: "Cancel") { close(false) }
            }
        }
        .padding(22)
        .frame(maxWidth: 380)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(ALIColors.outline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
    }

    private func avatar(_ name: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(name.prefix(1)).uppercased())
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.7))
                .clipShape(Circle())
            Text(name)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
                .lineLimit(1)
                .frame(maxWidth: 90)
        }
    }

    private func close(_ confirmed: Bool) {
        withAnimation(.easeOut(duration: 0.18)) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onFinish(confirmed) }
    }
}

/// One-time question to the group admin (first visit to Finances in a
/// shared group): keep the "Balance between you" or hide it for everyone.
/// Shows a sample of the card so it's clear what it is. Must be answered
/// (can't be swiped away); it can be changed later in App features.
private struct BalancePromptSheet: View {
    let onAnswer: (Bool) -> Void

    var body: some View {
        trackedBody.trackScreen("finances_balance_prompt")
    }

    private var trackedBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            sampleCard
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(ALIColors.economiaAccent.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Show the balance between you?")
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                Text("It splits expenses equally and works out who owes whom. If your family doesn't use it, you can hide it for everyone. You can change this in App features.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ALIPrimaryButton(text: "Keep balance", accent: ALIColors.economiaAccent) { onAnswer(true) }
                ALISecondaryButton(text: "Hide balance") { onAnswer(false) }
            }
        }
        .padding(20)
        .padding(.top, 8)
        .background(ALIColors.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    /// Example of the balance card (sample names, not the group's data).
    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Balance between you")
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
            sampleRow(initial: "L", color: ALIColors.error, from: "Lucía", to: "Varo", amount: 42.5)
            sampleRow(initial: "P", color: ALIColors.familyAccent, from: "Pablo", to: "Varo", amount: 12)
        }
        .padding(14)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ALIColors.outline, lineWidth: 1))
        .shadow(color: ALIColors.economiaStrong.opacity(0.15), radius: 10, y: 6)
        .rotationEffect(.degrees(-1.5))
    }

    private func sampleRow(initial: String, color: Color, from: String, to: String, amount: Double) -> some View {
        HStack(spacing: 10) {
            Text(initial)
                .font(ALITypography.labelLarge.weight(.semibold))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.6))
                .clipShape(Circle())
            Text("\(from) owes \(to)")
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(amount.formattedEuros)
                .font(ALITypography.bodyMedium.weight(.semibold))
                .foregroundStyle(ALIColors.error)
        }
    }
}

/// Row for a transaction: name, categories, who carried it out and when,
/// and the amount (green if it's income), with actions to edit or delete it.
private struct ExpenseRow: View {
    let row: ExpenseRowData
    var canEdit: Bool = true
    var canDelete: Bool = true
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ALIIconView(icon: row.emoji, size: 20)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(2)
                if !row.categoryNames.isEmpty {
                    Text(row.categoryNames.joined(separator: ", "))
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .lineLimit(2)
                }
                Text("\(row.personName) · \(row.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text((row.isIncome ? "+" : "-") + row.amount.formattedEuros)
                .font(ALITypography.bodyLarge)
                .fixedSize()
                .foregroundStyle(row.isIncome ? ALIColors.success : ALIColors.ink)
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
        trackedBody.trackScreen("finances_date_filter")
    }

    @ViewBuilder
    private var trackedBody: some View {
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
            .navigationBarTitleDisplayMode(.large)
            .presentationDragIndicator(.visible)
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
