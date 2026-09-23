import SwiftUI
import SwiftData

/// Sheet to create or edit a group expense or income: name, amount,
/// who carried it out (who paid the expense, or who received the
/// income), and one or more categories. With that, `EconomiaScreen`
/// calculates the split among everyone and `EconomiaStatsScreen` breaks
/// totals down by category.
struct AddExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @Query(sort: \ExpenseCategory.createdAt) private var categories: [ExpenseCategory]

    let expenseToEdit: Expense?

    @State private var name = ""
    @State private var amountText = ""
    @State private var isIncome = false
    @State private var personID: UUID?
    @State private var categoryIDs: Set<UUID> = []
    @State private var showAddCategorySheet = false
    @State private var showPaywall = false

    private var isEditing: Bool { expenseToEdit != nil }

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        !name.trimmed.isEmpty && (amount ?? 0) > 0 && personID != nil
    }

    var body: some View {
        trackedBody.trackScreen("expense_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("", selection: $isIncome) {
                        Text("Expense").tag(false)
                        Text("Income").tag(true)
                    }
                    .pickerStyle(.segmented)

                    ALITextField(placeholder: "Name (e.g. Supermarket)", text: $name)

                    HStack(spacing: 8) {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(ALITypography.displayMedium)
                            .foregroundStyle(ALIColors.ink)
                        Text("€")
                            .font(ALITypography.displayMedium)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ALIColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ALIColors.outline, lineWidth: 1)
                    )

                    personCard
                    categoryCard

                    ALIPrimaryButton(text: "Save", enabled: canSave, accent: ALIColors.economiaAccent) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationTitle(isEditing ? (isIncome ? "Edit income" : "Edit expense") : (isIncome ? "New income" : "New expense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let expense = expenseToEdit {
                    name = expense.name
                    amountText = expense.amount.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(expense.amount))
                        : String(format: "%.2f", expense.amount)
                    isIncome = expense.isIncome
                    personID = expense.personID
                    categoryIDs = Set(expense.categoryIDs)
                }
                if personID == nil {
                    personID = familySession.memberID ?? members.first?.id
                }
            }
            .sheet(isPresented: $showAddCategorySheet) {
                AddCategorySheet { newCategory in
                    categoryIDs.insert(newCategory.id)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
        .presentationDetents([.large])
    }

    private var personCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text(isIncome ? "Who received it?" : "Who paid it?")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                if members.isEmpty {
                    Text("There's no one in the family group yet.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 8) {
                        ForEach(members) { member in
                            personChip(member)
                        }
                    }
                }
            }
        }
    }

    private func personChip(_ member: FamilyMember) -> some View {
        let isSelected = personID == member.id
        return Button {
            personID = member.id
        } label: {
            Text(member.name)
                .lineLimit(1)
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(isSelected ? ALIColors.economiaAccent.opacity(0.3) : ALIColors.surfaceVariant)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? ALIColors.economiaAccent : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    /// Multi-select: any number of categories can apply to the same
    /// expense (e.g. a trip that's both "Travel" and "Dining out"). A
    /// full-width list instead of a chip grid so every name reads in full,
    /// no matter how long, and it's obvious at a glance what's selected.
    private var categoryCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Categories")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                VStack(spacing: 0) {
                    ForEach(categories) { category in
                        categoryRow(category, locked: lockedCategoryIDs.contains(category.id))
                        Divider().overlay(ALIColors.outline)
                    }
                    newCategoryRow
                }
            }
        }
    }

    private func categoryRow(_ category: ExpenseCategory, locked: Bool) -> some View {
        let isSelected = categoryIDs.contains(category.id)
        return Button {
            if locked {
                showPaywall = Track.paywall("locked_category")
            } else if isSelected {
                Track.event("expense_category_toggle", ["selected": false, "is_default": category.isDefault])
                categoryIDs.remove(category.id)
            } else {
                Track.event("expense_category_toggle", ["selected": true, "is_default": category.isDefault])
                categoryIDs.insert(category.id)
            }
        } label: {
            HStack(spacing: 12) {
                Text(category.emoji)
                    .font(.system(size: 20))
                Text(category.name)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.ink)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? ALIColors.economiaAccent : ALIColors.outline)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .opacity(locked ? 0.55 : 1)
            .aliPremiumLockOverlay(locked)
        }
        .buttonStyle(.plain)
    }

    /// Beyond 3 custom categories, creating another one needs a
    /// subscription if `extraCategories` is currently premium (the
    /// default categories don't count towards this limit).
    private var isNewCategoryLocked: Bool {
        categories.filter { !$0.isDefault }.count >= 3 && premium.isLocked(.extraCategories)
    }

    /// If the group loses premium, only the first 3 custom categories it
    /// ever created stay usable (the defaults never count/lock) — the
    /// rest get locked behind the paywall instead of being deleted.
    private var lockedCategoryIDs: Set<UUID> {
        guard premium.isLocked(.extraCategories) else { return [] }
        let extra = categories.filter { !$0.isDefault }.sorted { $0.createdAt < $1.createdAt }.dropFirst(3)
        return Set(extra.map(\.id))
    }

    private var newCategoryRow: some View {
        Button {
            if isNewCategoryLocked { showPaywall = Track.paywall("new_category") } else {
                Track.event("expense_category_new_tap", ["custom_categories": categories.filter { !$0.isDefault }.count])
                showAddCategorySheet = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(ALIColors.mutedInk)
                    .aliPremiumLockOverlay(isNewCategoryLocked)
                Text("New category")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let amount, let personID else { return }
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return }
        let personName = members.first(where: { $0.id == personID })?.name ?? ""
        // Keeps the categories in the order they're shown, rather than
        // Set's arbitrary order.
        let orderedCategoryIDs = categories.map(\.id).filter { categoryIDs.contains($0) }
        let wasEditing = expenseToEdit != nil
        let selected = categories.filter { categoryIDs.contains($0.id) }
        Track.event(wasEditing ? "expense_edited" : "expense_new", [
            "is_income": isIncome,
            "categories": selected.count,
            "custom_categories": selected.filter { !$0.isDefault }.count,
            "paid_by_me": personID == familySession.memberID,
            "members": members.count
        ])

        let expense: Expense
        if let existing = expenseToEdit {
            existing.name = trimmedName
            existing.amount = amount
            existing.isIncome = isIncome
            existing.personID = personID
            existing.personName = personName
            existing.categoryIDs = orderedCategoryIDs
            expense = existing
        } else {
            expense = Expense(
                name: trimmedName,
                amount: amount,
                isIncome: isIncome,
                personID: personID,
                personName: personName,
                categoryIDs: orderedCategoryIDs
            )
            modelContext.insert(expense)
        }
        if let familyID = familySession.familyID {
            dataSync.pushExpense(expense, familyID: familyID)
            dataSync.logActivity(
                entityType: "expense",
                entityName: trimmedName,
                action: wasEditing ? "updated" : "created",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID,
                modelContext: modelContext
            )
        }
        dismiss()
    }
}

/// Small sheet to create a new spending category on the fly, without
/// leaving `AddExpenseSheet`: a name and an emoji from a short curated set.
private struct AddCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    let onCreate: (ExpenseCategory) -> Void

    @State private var name = ""
    @State private var emoji = "🏷️"

    private let emojiOptions = [
        "🏷️", "🛒", "🏠", "💡", "🚗", "🍽️", "💊", "🎬",
        "🛍️", "📚", "🐾", "✈️", "🎁", "💻", "🧾", "🏋️"
    ]

    private var canSave: Bool { !name.trimmed.isEmpty }

    var body: some View {
        trackedBody.trackScreen("expense_category_new")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ALITextField(placeholder: "Category name", text: $name)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
                    ForEach(emojiOptions, id: \.self) { option in
                        emojiButton(option)
                    }
                }

                Spacer()

                ALIPrimaryButton(text: "Add category", enabled: canSave, accent: ALIColors.economiaAccent) {
                    save()
                }
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationTitle("New category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func emojiButton(_ option: String) -> some View {
        let isSelected = emoji == option
        return Button {
            emoji = option
        } label: {
            Text(option)
                .font(.system(size: 22))
                .frame(width: 48, height: 48)
                .background(isSelected ? ALIColors.economiaAccent.opacity(0.3) : ALIColors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? ALIColors.economiaAccent : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return }
        let category = ExpenseCategory(name: trimmedName, emoji: emoji)
        Track.event("expense_category_created", ["emoji": emoji])
        modelContext.insert(category)
        if let familyID = familySession.familyID {
            dataSync.pushCategory(category, familyID: familyID)
        }
        onCreate(category)
        dismiss()
    }
}
