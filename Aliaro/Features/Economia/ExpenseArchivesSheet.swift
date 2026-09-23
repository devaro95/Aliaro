import SwiftUI
import SwiftData
import QuickLook

/// "Archive" sheet of the Finances tab: closes off the current finances
/// (saves every transaction under a name and starts the list again from
/// zero) and lists the finances archived before, each one viewable in
/// detail and downloadable as a PDF.
struct ExpenseArchivesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
    @Query(sort: \ExpenseArchive.createdAt, order: .reverse) private var allArchives: [ExpenseArchive]
    /// Fresh fetch for the same reason as `expenses`.
    private var archives: [ExpenseArchive] {
        _ = allArchives.count
        let descriptor = FetchDescriptor<ExpenseArchive>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @State private var showNamePrompt = false
    @State private var archiveName = ""
    @State private var isArchiving = false
    @State private var errorMessage: String?
    /// PDF being previewed (Quick Look: view it, then share / save to Files).
    @State private var previewURL: URL?
    @State private var showPaywall = false

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    /// Archiving removes every transaction from the live list, so it
    /// needs the same permission as deleting one.
    private var canArchive: Bool { currentMember?.can(.financesDelete) ?? true }
    /// Premium (`financeArchive`): when locked, the sheet still opens as a
    /// preview — sample data (never the group's real finances or
    /// archives), blurred and non-interactive, with a banner leading to
    /// the paywall.
    private var isArchiveLocked: Bool { premium.isLocked(.financeArchive) }

    /// What "Current finances" shows: the real transactions, or this
    /// month's sample ones while locked.
    private var shownExpenses: [Expense] {
        guard isArchiveLocked else { return expenses }
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return [] }
        return EconomiaDemoData.expenses.filter { $0.occurredAt >= month.start }
    }

    private var archiveRows: [ArchiveRowData] {
        if isArchiveLocked { return Self.demoArchiveRows }
        return archives.map { ArchiveRowData(id: $0.id, name: $0.name, period: $0.periodText) }
    }

    /// The three previous months, as sample archives for the locked preview.
    private static var demoArchiveRows: [ArchiveRowData] {
        let calendar = Calendar.current
        let nameFormatter = DateFormatter()
        nameFormatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return (1...3).compactMap { offset -> ArchiveRowData? in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: .now),
                  let month = calendar.dateInterval(of: .month, for: date) else { return nil }
            let end = month.end.addingTimeInterval(-1)
            return ArchiveRowData(
                id: UUID(),
                name: nameFormatter.string(from: date).capitalized,
                period: "\(month.start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
            )
        }
    }

    private var currentPeriod: String? {
        guard let first = shownExpenses.last?.occurredAt, let last = shownExpenses.first?.occurredAt else { return nil }
        let start = first.formatted(date: .abbreviated, time: .omitted)
        if Calendar.current.isDate(first, inSameDayAs: last) { return start }
        return "\(start) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currentCard

                    Text("Archived finances")
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)

                    if archiveRows.isEmpty {
                        ALIEmptyState(
                            emoji: "🗂️",
                            title: "Nothing archived yet",
                            subtitle: "Archived finances will show up here, ready to review or download as PDF."
                        )
                    } else {
                        ALICard(padding: EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 12)) {
                            VStack(spacing: 0) {
                                // Plain values, not the models: SwiftUI re-runs a
                                // ForEach row on its own when its object changes,
                                // including when it's deleted — reading a deleted
                                // SwiftData object there crashes.
                                let rows = archiveRows
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    archiveRow(row)
                                    if index < rows.count - 1 {
                                        Divider().overlay(ALIColors.outline)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .aliPremiumPreview(isArchiveLocked)
            }
            .aliPremiumPreviewBanner(isArchiveLocked, buttonTitle: "Unlock archive") { showPaywall = true }
            .background(ALIColors.background)
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                if let archive = archives.first(where: { $0.id == id }) {
                    ExpenseArchiveDetailView(archive: archive, canDelete: canArchive)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Archive finances", isPresented: $showNamePrompt) {
                TextField("Name", text: $archiveName)
                Button("Cancel", role: .cancel) {}
                Button("Archive") { Task { await archiveCurrent() } }
                    .disabled(archiveName.trimmed.isEmpty)
            } message: {
                Text("All current transactions will be saved under this name and Finances will start again from zero.")
            }
            .alert("Couldn't archive", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .quickLookPreview($previewURL)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Current finances

    private var currentCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current finances")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                if shownExpenses.isEmpty {
                    Text("There are no transactions to archive.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(shownExpenses.count) transactions")
                            .font(ALITypography.titleLarge)
                            .foregroundStyle(ALIColors.ink)
                        if let currentPeriod {
                            Text(currentPeriod)
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.mutedInk)
                        }
                    }
                }
                Text("Save them under a name and start again from zero. You can check them or download them as PDF at any time.")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                if isArchiving {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 54)
                } else {
                    if canArchive {
                        ALIPrimaryButton(text: "Archive and start over", enabled: !shownExpenses.isEmpty, accent: ALIColors.economiaAccent) {
                            archiveName = defaultName
                            showNamePrompt = true
                        }
                    }
                    if !shownExpenses.isEmpty {
                        ALISecondaryButton(text: "View PDF without archiving") {
                            previewURL = try? ExpenseArchivePDF.makeCurrent(
                                expenses: expenses, categories: categories, members: members
                            )
                        }
                    }
                }
            }
        }
    }

    /// Suggested name: the month (or month range) the transactions cover.
    private var defaultName: String {
        guard let first = expenses.last?.occurredAt, let last = expenses.first?.occurredAt else { return "" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let end = formatter.string(from: last).capitalized
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .month) { return end }
        let startFormatter = DateFormatter()
        startFormatter.setLocalizedDateFormatFromTemplate("LLLL")
        return "\(startFormatter.string(from: first).capitalized) – \(end)"
    }

    private func archiveCurrent() async {
        guard let familyID = familySession.familyID else { return }
        let name = archiveName.trimmed
        guard !name.isEmpty, !expenses.isEmpty else { return }

        let current = expenses
        let ids = current.map(\.id)
        let dates = current.map(\.occurredAt)
        let actorName = familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) }
        let archive = ExpenseArchive(
            name: name,
            startDate: dates.min() ?? .now,
            endDate: dates.max() ?? .now,
            archivedByName: actorName,
            snapshot: ExpenseArchiveSnapshot(expenses: current, categories: categories, members: members)
        )

        isArchiving = true
        defer { isArchiving = false }
        do {
            try await dataSync.archiveExpenses(archive, expenseIDs: ids, familyID: familyID)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Real time may have already applied part of this (the archive
        // insert, some expense deletes) while we awaited — only touch
        // what's still pending locally.
        let archiveID = archive.id
        let existing = try? modelContext.fetch(FetchDescriptor<ExpenseArchive>(predicate: #Predicate { $0.id == archiveID }))
        if existing?.isEmpty ?? true { modelContext.insert(archive) }
        for id in ids {
            if let expense = try? modelContext.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first {
                modelContext.delete(expense)
            }
        }
        try? modelContext.save()

        dataSync.logActivity(
            entityType: "expense_archive", entityName: name, action: "created",
            actorID: familySession.memberID, actorName: actorName,
            familyID: familyID, modelContext: modelContext
        )
    }

    // MARK: Archived list

    private struct ArchiveRowData: Identifiable {
        let id: UUID
        let name: String
        let period: String
    }

    private func archiveRow(_ row: ArchiveRowData) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: row.id) {
                HStack(spacing: 12) {
                    Text("🗂️").font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name)
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(ALIColors.ink)
                            .lineLimit(1)
                        Text(row.period)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                let id = row.id
                if let archive = try? modelContext.fetch(FetchDescriptor<ExpenseArchive>(predicate: #Predicate { $0.id == id })).first {
                    previewURL = try? ExpenseArchivePDF.make(for: archive)
                }
            } label: {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ALIColors.ink)
                    .frame(width: 40, height: 40)
                    .background(ALIColors.surfaceVariant)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View PDF")
        }
        .padding(.vertical, 10)
    }
}

/// Read-only view of an archived period: totals, the balance between
/// members when it was archived, and every transaction.
struct ExpenseArchiveDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let archive: ExpenseArchive
    let canDelete: Bool

    /// PDF being previewed (Quick Look: view it, then share / save to Files).
    @State private var previewURL: URL?
    @State private var showDeleteConfirm = false

    var body: some View {
        let snapshot = archive.snapshot
        ScrollView {
            VStack(spacing: 16) {
                ALICard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(archive.name)
                            .font(ALITypography.headlineMedium)
                            .foregroundStyle(ALIColors.ink)
                        Label(archive.periodText, systemImage: "calendar")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.ink)
                        Text(archivedLine)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                }

                HStack(spacing: 10) {
                    tile("Spent", snapshot.totalExpenses)
                    tile("Income", snapshot.totalIncome)
                    tile("Net expense", snapshot.net, highlighted: true)
                }

                if !snapshot.settlements.isEmpty {
                    ALICard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Balance between you")
                                .font(ALITypography.labelLarge)
                                .foregroundStyle(ALIColors.mutedInk)
                            ForEach(Array(snapshot.settlements.enumerated()), id: \.offset) { _, s in
                                HStack(spacing: 6) {
                                    Text(s.from).fontWeight(.semibold)
                                    Text("owes")
                                    Text(s.to).fontWeight(.semibold)
                                    Spacer()
                                    Text(s.amount.formattedEuros).foregroundStyle(ALIColors.error)
                                }
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.ink)
                            }
                        }
                    }
                }

                ALICard {
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item)
                            if index < snapshot.items.count - 1 {
                                Divider().overlay(ALIColors.outline)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(ALIColors.background)
        .navigationTitle(archive.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    previewURL = try? ExpenseArchivePDF.make(for: archive)
                } label: {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel("View PDF")
                if canDelete {
                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
            .quickLookPreview($previewURL)
        .aliDeleteConfirmDialog(isPresented: $showDeleteConfirm, itemName: archive.name) {
            let id = archive.id
            let name = archive.name
            let context = modelContext
            let sync = dataSync
            let familyID = familySession.familyID
            let actorID = familySession.memberID
            // Pop back first: deleting the model while this view is still
            // on screen would make it read a detached SwiftData object.
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let archive = try? context.fetch(FetchDescriptor<ExpenseArchive>(predicate: #Predicate { $0.id == id })).first {
                    context.delete(archive)
                    try? context.save()
                }
                sync.deleteExpenseArchive(id: id)
                if let familyID {
                    sync.logActivity(
                        entityType: "expense_archive", entityName: name, action: "deleted",
                        actorID: actorID,
                        actorName: actorID.flatMap { context.familyMemberName(id: $0) },
                        familyID: familyID, modelContext: context
                    )
                }
            }
        }
    }

    private var archivedLine: String {
        let date = archive.createdAt.formatted(date: .abbreviated, time: .shortened)
        if let by = archive.archivedByName, !by.isEmpty {
            return String(localized: "Archived on \(date) by \(by)")
        }
        return String(localized: "Archived on \(date)")
    }

    private func tile(_ title: LocalizedStringKey, _ value: Double, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
            Text(value.formattedEuros)
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? ALIColors.economiaAccent.opacity(0.35) : ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ALIColors.outline, lineWidth: 1))
    }

    private func itemRow(_ item: ExpenseArchiveSnapshot.Item) -> some View {
        HStack(spacing: 12) {
            Text(item.emoji)
                .font(.system(size: 17))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(2)
                if !item.categoryNames.isEmpty {
                    Text(item.categoryNames.joined(separator: ", "))
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .lineLimit(2)
                }
                Text("\(item.personName) · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text((item.isIncome ? "+" : "-") + item.amount.formattedEuros)
                .font(ALITypography.bodyLarge)
                .fixedSize()
                .foregroundStyle(item.isIncome ? ALIColors.success : ALIColors.ink)
        }
        .padding(.vertical, 10)
    }
}
