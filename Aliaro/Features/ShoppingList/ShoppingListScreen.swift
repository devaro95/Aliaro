import SwiftUI
import SwiftData

/// "Lists" tab: at the top, the group's lists as tabs (there's always at
/// least one; private ones only for their creator, with a lock); below,
/// the active list. Each list's products are managed from the add screen
/// (`AddToShoppingListScreen`, full screen sliding in from the right).
struct ShoppingListScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var screenChrome: ScreenChrome

    @Query(sort: \ShoppingList.position) private var allLists: [ShoppingList]
    @Query private var catalog: [GroceryItem]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @Query(sort: \ShoppingListEntry.addedAt, order: .reverse)
    private var allEntries: [ShoppingListEntry]

    @State private var selectedListID: UUID?
    @State private var showAddScreen = false
    @State private var confirmClearChecked = false
    @State private var entryPendingDelete: ShoppingListEntry?

    @State private var showNewListSheet = false
    @State private var renamingList: ShoppingList?
    @State private var renameListText = ""
    @State private var listPendingDelete: ShoppingList?
    @State private var showPaywall = false

    private var entries: [ShoppingListEntry] {
        guard let selectedListID else { return [] }
        return allEntries.filter { $0.listID == selectedListID }
    }
    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }

    /// Shared lists + this person's private ones (Supabase doesn't send
    /// anyone else's, this is just a safety net).
    private var lists: [ShoppingList] {
        allLists.filter { !$0.isPrivate || $0.ownerMemberID == currentMember?.id }
    }
    private var canAdd: Bool { currentMember?.can(.shoppingAdd) ?? true }
    private var canDelete: Bool { currentMember?.can(.shoppingDelete) ?? true }

    private var pending: [ShoppingListEntry] { entries.filter { !$0.isChecked } }
    private var checked: [ShoppingListEntry] {
        entries.filter(\.isChecked).sorted { ($0.checkedAt ?? .distantPast) > ($1.checkedAt ?? .distantPast) }
    }

    var body: some View {
        trackedBody.trackScreen("shopping_list")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Lists", accent: ALIColors.shoppingAccent) {
                    if canAdd {
                        ALIFloatingButton(accent: ALIColors.shoppingAccent) {
                            Track.event("shopping_add_tap", ["pending": pending.count, "lists": lists.count])
                            showAddScreen = true
                        }
                            .scaleEffect(0.72)
                    }
                }

                listTabs

                if entries.isEmpty {
                    ALIEmptyState(
                        icon: ALIIcon.list,
                        title: "The list is empty",
                        subtitle: "Tap the + to add something to it."
                    )
                } else {
                    if !pending.isEmpty {
                        sectionCard(title: String(localized: "Pending (\(pending.count))"), rows: pending)
                    }
                    if !checked.isEmpty {
                        sectionCard(title: String(localized: "Done (\(checked.count))"), rows: checked, dimmed: true)
                        if canDelete {
                            ALITextButton(text: "Clear done") { confirmClearChecked = true }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .onAppear { ensureSelection() }
        .onChange(of: lists.map(\.id)) { _, ids in
            if selectedListID == nil || !ids.contains(selectedListID!) {
                selectedListID = ids.first
            }
        }
        .onChange(of: premium.isLocked(.extraShoppingLists)) { _, locked in
            guard locked, let selected = lists.first(where: { $0.id == selectedListID }) else { return }
            if isListLocked(selected) { selectedListID = lists.first?.id }
        }
        // Add products: full screen over the list (and the bar), sliding in from the right.
        .overlay {
            if showAddScreen, let selectedListID {
                AddToShoppingListScreen(listID: selectedListID) { showAddScreen = false }
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showAddScreen)
        .toolbar(showAddScreen ? .hidden : .automatic, for: .navigationBar)
        .onChange(of: showAddScreen) { _, shown in
            withAnimation(.easeInOut(duration: 0.25)) { screenChrome.coversBottomBar = shown }
        }
        .onDisappear { screenChrome.coversBottomBar = false }
        .alert("Clear done items?", isPresented: $confirmClearChecked) {
            Button("Delete", role: .destructive) {
                Track.event("shopping_clear_bought", ["count": checked.count])
                clearChecked()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { entryPendingDelete != nil }, set: { if !$0 { entryPendingDelete = nil } }),
            itemName: entryPendingDelete?.name ?? ""
        ) {
            if let entry = entryPendingDelete { delete(entry) }
        }
        .sheet(isPresented: $showNewListSheet) {
            NewListSheet { name, isPrivate in createList(name: name, isPrivate: isPrivate) }
        }
        .alert(
            "Rename list",
            isPresented: Binding(get: { renamingList != nil }, set: { if !$0 { renamingList = nil } })
        ) {
            TextField("Name", text: $renameListText)
            Button("Cancel", role: .cancel) { renamingList = nil }
            Button("Save") { saveListRename() }
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { listPendingDelete != nil }, set: { if !$0 { listPendingDelete = nil } }),
            itemName: listPendingDelete?.displayName ?? ""
        ) {
            if let list = listPendingDelete { deleteList(list) }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// Beyond the first shopping list, creating another one needs a
    /// subscription if `extraShoppingLists` is currently premium.
    private var isNewListLocked: Bool {
        !lists.isEmpty && premium.isLocked(.extraShoppingLists)
    }

    /// If the group loses premium, only the first list (tab) stays usable —
    /// the rest get locked behind the paywall instead of being deleted, so
    /// tapping one opens `PaywallView` instead of switching to it.
    private func isListLocked(_ list: ShoppingList) -> Bool {
        guard premium.isLocked(.extraShoppingLists), let first = lists.first else { return false }
        return list.id != first.id
    }

    // MARK: List tabs

    @ViewBuilder
    private var listTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lists) { list in
                    listTab(list)
                }
                if canAdd {
                Button {
                    if isNewListLocked {
                        showPaywall = Track.paywall("new_shopping_list")
                    } else {
                        showNewListSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(width: 34, height: 34)
                        .background(ALIColors.surfaceVariant)
                        .clipShape(Circle())
                        .aliPremiumLockOverlay(isNewListLocked)
                }
                .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func listTab(_ list: ShoppingList) -> some View {
        let isSelected = list.id == selectedListID
        let locked = isListLocked(list)
        Button {
            if locked {
                showPaywall = Track.paywall("locked_shopping_list_tab")
            } else {
                if list.id != selectedListID {
                    Track.event("shopping_list_switch", ["position": list.position, "lists": lists.count])
                }
                withAnimation(.easeInOut(duration: 0.2)) { selectedListID = list.id }
            }
        } label: {
            HStack(spacing: 5) {
                if list.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityLabel(Text("Private"))
                }
                Text(list.displayName)
                    .lineLimit(1)
            }
            .font(ALITypography.labelLarge)
            .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(isSelected ? ALIColors.shoppingAccent : ALIColors.surfaceVariant)
            .clipShape(Capsule())
            .aliPremiumLockOverlay(locked)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if canAdd {
                Button {
                    Track.event("shopping_list_menu", ["action": "rename"])
                    renameListText = list.displayName
                    renamingList = list
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
            if lists.count > 1 && canDelete {
                Button(role: .destructive) {
                    listPendingDelete = list
                } label: {
                    Label("Delete list", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func sectionCard(title: String, rows: [ShoppingListEntry], dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
                .padding(.leading, 4)

            ALICard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        ShoppingListRow(entry: entry, dimmed: dimmed, canEdit: canAdd, canDelete: canDelete) {
                            toggle(entry)
                        } onSetQuantity: { value in
                            setQuantity(entry, value)
                        } onDelete: {
                            entryPendingDelete = entry
                        }
                        if index < rows.count - 1 {
                            Divider().overlay(ALIColors.outline)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions — entries

    private func toggle(_ entry: ShoppingListEntry) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            entry.isChecked.toggle()
            entry.checkedAt = entry.isChecked ? .now : nil
        }
        Track.event(entry.isChecked ? "shopping_item_checked" : "shopping_item_unchecked", [
            "item_name": entry.name,
            "minutes_in_list": Int(Date.now.timeIntervalSince(entry.addedAt) / 60)
        ])
        if let familyID = familySession.familyID { dataSync.pushShoppingListEntry(entry, familyID: familyID) }
        if entry.isChecked { ReviewPrompt.shared.registerPositiveAction("shopping_item_checked") }
    }

    /// Quantity from the inline − n + (nil = 1).
    private func setQuantity(_ entry: ShoppingListEntry, _ value: String?) {
        guard value != entry.quantity else { return }
        entry.quantity = value
        Track.event("shopping_item_quantity", ["has_quantity": value != nil, "where": "list_inline"])
        if let familyID = familySession.familyID { dataSync.pushShoppingListEntry(entry, familyID: familyID) }
    }

    private func delete(_ entry: ShoppingListEntry) {
        let entryID = entry.id
        Track.event("shopping_item_removed", ["item_name": entry.name, "was_checked": entry.isChecked])
        withAnimation { modelContext.delete(entry) }
        dataSync.deleteShoppingListEntry(id: entryID)
    }

    private func clearChecked() {
        withAnimation {
            for entry in checked {
                let entryID = entry.id
                modelContext.delete(entry)
                dataSync.deleteShoppingListEntry(id: entryID)
            }
        }
    }

    // MARK: Actions — lists (tabs)

    /// Selects the first available list if none is selected yet. The
    /// default list is created by `FamilyService` when the group is
    /// created (or arrives already created when syncing, if the group
    /// joined an existing one) — it's not created here, so it isn't
    /// duplicated if this view appears before sync has finished settling.
    private func ensureSelection() {
        if let selectedListID, lists.contains(where: { $0.id == selectedListID }) { return }
        selectedListID = lists.first?.id
    }

    private func createList(name: String, isPrivate: Bool) {
        guard !name.isEmpty else { return }
        let list = ShoppingList(
            name: name,
            position: (allLists.map(\.position).max() ?? -1) + 1,
            ownerMemberID: isPrivate ? currentMember?.id : nil
        )
        modelContext.insert(list)
        if let familyID = familySession.familyID { dataSync.pushShoppingList(list, familyID: familyID) }
        Track.event("shopping_list_created", ["lists_total": lists.count + 1, "private": list.isPrivate])
        selectedListID = list.id
    }

    private func saveListRename() {
        defer { renamingList = nil }
        guard let list = renamingList, !renameListText.trimmed.isEmpty else { return }
        list.name = renameListText.trimmed
        Track.event("shopping_list_renamed")
        if let familyID = familySession.familyID { dataSync.pushShoppingList(list, familyID: familyID) }
    }

    private func deleteList(_ list: ShoppingList) {
        let listID = list.id
        let entriesToDelete = allEntries.filter { $0.listID == listID }
        // Its products go with it (old ones without a list stay, they're
        // the first list's).
        let itemsToDelete = catalog.filter { $0.listID == listID }
        Track.event("shopping_list_deleted", ["entries": entriesToDelete.count, "lists_total": lists.count - 1, "private": list.isPrivate])
        withAnimation {
            for entry in entriesToDelete {
                let entryID = entry.id
                modelContext.delete(entry)
                dataSync.deleteShoppingListEntry(id: entryID)
            }
            for item in itemsToDelete {
                let itemID = item.id
                modelContext.delete(item)
                dataSync.deleteGroceryItem(id: itemID)
            }
            modelContext.delete(list)
        }
        dataSync.deleteShoppingList(id: listID)
        if selectedListID == listID {
            selectedListID = lists.first(where: { $0.id != listID })?.id
        }
    }
}

/// Row for an item within the active list: pastel checkbox + name, with
/// "×n" below (1 when it has no quantity). Tap marks it done. The menu
/// edits the quantity right in the row (− n + ✓) or removes it from the
/// list (only the entry, not the list's product).
private struct ShoppingListRow: View {
    let entry: ShoppingListEntry
    var dimmed: Bool = false
    var canEdit: Bool = true
    var canDelete: Bool = true
    let onToggle: () -> Void
    /// New quantity (nil = 1).
    let onSetQuantity: (String?) -> Void
    let onDelete: () -> Void

    @State private var editing = false
    @State private var draft = 1

    private var accent: Color { ALIColors.shoppingAccent }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(entry.isChecked ? ALIColors.success : ALIColors.surfaceVariant)
                            .frame(width: 26, height: 26)
                        if entry.isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ALIColors.onAccent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(dimmed ? ALIColors.mutedInk : ALIColors.ink)
                            .strikethrough(dimmed)
                        if !editing {
                            Text(verbatim: "×" + shoppingQuantityLabel(entry.quantity))
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.mutedInk)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(editing)

            if editing {
                QuantityCircleButton(systemImage: "minus", foreground: draft > 1 ? accent : ALIColors.mutedInk, background: ALIColors.surfaceVariant) {
                    draft -= 1
                }
                .disabled(draft <= 1)
                Text(verbatim: "\(draft)")
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .frame(minWidth: 20)
                QuantityCircleButton(systemImage: "plus", foreground: accent, background: ALIColors.surfaceVariant) {
                    draft += 1
                }
                QuantityCircleButton(systemImage: "checkmark", foreground: ALIColors.onAccent, background: accent) {
                    editing = false
                    onSetQuantity(draft > 1 ? "\(draft)" : nil)
                }
            } else if canEdit || canDelete {
                Menu {
                    if canEdit {
                        Button {
                            draft = Int(entry.quantity?.trimmed ?? "") ?? 1
                            editing = true
                        } label: {
                            Label("Edit quantity", systemImage: "number")
                        }
                    }
                    if canDelete {
                        Button(role: .destructive, action: onDelete) {
                            Label("Remove from list", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, 12)
    }
}

/// Round 32 pt button for the quantity controls (− + ✓).
struct QuantityCircleButton: View {
    let systemImage: String
    let foreground: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 32, height: 32)
                .background(background)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Quantity as shown: 1 when empty; free text (old "1 kg" values) as is.
func shoppingQuantityLabel(_ quantity: String?) -> String {
    let text = quantity?.trimmed ?? ""
    return text.isEmpty ? "1" : text
}

/// Create a list: name + whether it's private. Private is chosen here
/// only — it can't be changed later.
private struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, Bool) -> Void

    @State private var name = ""
    @State private var isPrivate = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ALITextField(placeholder: "E.g. Groceries, Pharmacy, Gifts…", text: $name, onSubmit: create)

                ALICard {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $isPrivate) {
                            Label("Private list", systemImage: "lock.fill")
                                .font(ALITypography.bodyLarge)
                                .foregroundStyle(ALIColors.ink)
                        }
                        .tint(ALIColors.shoppingAccent)
                        Text("Only you will see it and its products. This can't be changed later.")
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                }

                Spacer()

                ALIPrimaryButton(text: "Create list", enabled: !name.trimmed.isEmpty, accent: ALIColors.shoppingAccent) {
                    create()
                }
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationTitle("New list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .trackScreen("shopping_new_list")
    }

    private func create() {
        guard !name.trimmed.isEmpty else { return }
        onCreate(name.trimmed, isPrivate)
        dismiss()
    }
}
