import SwiftUI
import SwiftData

/// "Shopping" tab: at the top, the group's lists as tabs (there's
/// always at least one); below, the active list. The items themselves
/// (the catalog) are managed from the add sheet (`AddToShoppingListSheet`).
struct ShoppingListScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query(sort: \ShoppingList.position) private var lists: [ShoppingList]
    @Query(sort: \ShoppingListEntry.addedAt, order: .reverse)
    private var allEntries: [ShoppingListEntry]

    @State private var selectedListID: UUID?
    @State private var showAddSheet = false
    @State private var entryPendingDelete: ShoppingListEntry?

    @State private var showNewListAlert = false
    @State private var newListName = ""
    @State private var renamingList: ShoppingList?
    @State private var renameListText = ""
    @State private var listPendingDelete: ShoppingList?
    @State private var showPaywall = false

    private var entries: [ShoppingListEntry] {
        guard let selectedListID else { return [] }
        return allEntries.filter { $0.listID == selectedListID }
    }
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
                ALITopBar(title: "Shopping list", accent: ALIColors.shoppingAccent) {
                    ALIFloatingButton(accent: ALIColors.shoppingAccent) {
                        Track.event("shopping_add_tap", ["pending": pending.count, "lists": lists.count])
                        showAddSheet = true
                    }
                        .scaleEffect(0.72)
                }

                listTabs

                if entries.isEmpty {
                    ALIEmptyState(
                        emoji: "🛒",
                        title: "The list is empty",
                        subtitle: "Tap the + to add what you're missing at home."
                    )
                } else {
                    if !pending.isEmpty {
                        sectionCard(title: "To buy (\(pending.count))", rows: pending)
                    }
                    if !checked.isEmpty {
                        sectionCard(title: "Bought (\(checked.count))", rows: checked, dimmed: true)
                        ALITextButton(text: "Clear bought") {
                            Track.event("shopping_clear_bought", ["count": checked.count])
                            clearChecked()
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
        .sheet(isPresented: $showAddSheet) {
            if let selectedListID {
                AddToShoppingListSheet(listID: selectedListID)
            }
        }
        .aliDeleteConfirmDialog(
            isPresented: Binding(get: { entryPendingDelete != nil }, set: { if !$0 { entryPendingDelete = nil } }),
            itemName: entryPendingDelete?.name ?? ""
        ) {
            if let entry = entryPendingDelete { delete(entry) }
        }
        .alert("New list", isPresented: $showNewListAlert) {
            TextField("E.g. Groceries, Furniture…", text: $newListName)
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Create") { createList() }
        } message: {
            Text("It will be added as a new tab.")
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
            itemName: listPendingDelete?.name ?? ""
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
                Button {
                    if isNewListLocked {
                        showPaywall = Track.paywall("new_shopping_list")
                    } else {
                        newListName = ""
                        showNewListAlert = true
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
            Text(list.name)
                .font(ALITypography.labelLarge)
                .foregroundStyle(isSelected ? ALIColors.onAccent : ALIColors.ink)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(isSelected ? ALIColors.shoppingAccent : ALIColors.surfaceVariant)
                .clipShape(Capsule())
                .aliPremiumLockOverlay(locked)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Track.event("shopping_list_menu", ["action": "rename"])
                renameListText = list.name
                renamingList = list
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if lists.count > 1 {
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
                        ShoppingListRow(entry: entry, dimmed: dimmed) {
                            toggle(entry)
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

    private func createList() {
        let name = newListName.trimmed
        newListName = ""
        guard !name.isEmpty else { return }
        let list = ShoppingList(name: name, position: (lists.map(\.position).max() ?? -1) + 1)
        modelContext.insert(list)
        if let familyID = familySession.familyID { dataSync.pushShoppingList(list, familyID: familyID) }
        Track.event("shopping_list_created", ["lists_total": lists.count + 1])
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
        Track.event("shopping_list_deleted", ["entries": entriesToDelete.count, "lists_total": lists.count - 1])
        withAnimation {
            for entry in entriesToDelete {
                let entryID = entry.id
                modelContext.delete(entry)
                dataSync.deleteShoppingListEntry(id: entryID)
            }
            modelContext.delete(list)
        }
        dataSync.deleteShoppingList(id: listID)
        if selectedListID == listID {
            selectedListID = lists.first(where: { $0.id != listID })?.id
        }
    }
}

/// Row for an item within the active list: pastel checkbox + name,
/// swipeable to delete (only removes the entry from the list, not the
/// catalog item).
private struct ShoppingListRow: View {
    let entry: ShoppingListEntry
    var dimmed: Bool = false
    let onToggle: () -> Void
    let onDelete: () -> Void

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
                    Text(entry.name)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(dimmed ? ALIColors.mutedInk : ALIColors.ink)
                        .strikethrough(dimmed)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }
}
