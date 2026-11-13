import SwiftUI
import SwiftData

/// Full screen (sliding in from the right) to add products to the active
/// list. It's also where the list's own products live. Each product belongs
/// to its list; products of the other lists show below ("From other lists")
/// and adding one copies it into this list.
/// - Tapping a product adds one more (the first tap adds it); once in the
///   list, − n + adjusts it (− to 0 removes it).
/// - "Edit" (pencil, top right): select products to delete several at once,
///   or rename one with its pencil. Create and "From other lists" hide meanwhile.
/// Same as `AddToShoppingListScreen` on Android.
struct AddToShoppingListScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    /// Active list (tab) that the products chosen here get added to.
    let listID: UUID
    /// Back to the list.
    let onClose: () -> Void

    @Query(sort: \GroceryItem.name) private var catalog: [GroceryItem]
    @Query(sort: \ShoppingList.position) private var lists: [ShoppingList]
    @Query private var entries: [ShoppingListEntry]

    @State private var searchText = ""
    @State private var renamingItem: GroceryItem?
    @State private var renameText = ""
    @State private var showOtherLists = false
    @State private var editMode = false
    @State private var selected: Set<UUID> = []
    @State private var confirmBulkDelete = false
    /// Edge swipe to go back (like a pushed screen).
    @State private var swipeOffset: CGFloat = 0

    private var firstListID: UUID? { lists.first?.id }

    /// Products of this list.
    private var listCatalog: [GroceryItem] {
        catalog.filter { $0.belongs(to: listID, firstListID: firstListID) }
    }

    /// Pending (unchecked) entries of the active list by product — no point
    /// adding them again until they're done.
    private var pendingEntries: [UUID: ShoppingListEntry] {
        Dictionary(
            entries.filter { !$0.isChecked && $0.listID == listID }.map { ($0.itemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func matches(_ item: GroceryItem) -> Bool {
        searchText.trimmed.isEmpty || item.name.localizedCaseInsensitiveContains(searchText.trimmed)
    }

    private var filteredCatalog: [GroceryItem] { listCatalog.filter(matches) }

    /// Products of the other lists (one per name) that this list doesn't have yet.
    private var otherProducts: [OtherProduct] {
        let own = Set(listCatalog.map { $0.name.lowercased() })
        var seen = Set<String>()
        var result: [OtherProduct] = []
        for list in lists where list.id != listID {
            for item in catalog where item.belongs(to: list.id, firstListID: firstListID) && matches(item) {
                let key = item.name.lowercased()
                guard !own.contains(key), seen.insert(key).inserted else { continue }
                result.append(OtherProduct(item: item, listName: list.displayName))
            }
        }
        return result.sorted { $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending }
    }

    private var exactMatchExists: Bool {
        listCatalog.contains { $0.name.compare(searchText.trimmed, options: .caseInsensitive) == .orderedSame }
    }

    private var currentListName: String {
        lists.first(where: { $0.id == listID })?.displayName ?? String(localized: "Lists")
    }

    var body: some View {
        trackedBody.trackScreen("shopping_add_items")
    }

    @ViewBuilder
    private var trackedBody: some View {
        VStack(spacing: 14) {
            header

            VStack(spacing: 14) {
                ALITextField(placeholder: "Search or create item…", text: $searchText, onSubmit: {
                    if !editMode { createFromSearchIfNeeded() }
                })

                if !editMode && !searchText.trimmed.isEmpty && !exactMatchExists {
                    Button(action: createFromSearchIfNeeded) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Create \"\(searchText.trimmed)\" and add")
                            Spacer()
                        }
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.onAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .background(ALIColors.shoppingAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 20)

            let others = editMode ? [] : otherProducts
            if filteredCatalog.isEmpty && others.isEmpty {
                ALIEmptyState(
                    icon: ALIIcon.list,
                    title: listCatalog.isEmpty ? "No items yet" : "No results",
                    subtitle: listCatalog.isEmpty ? "Type above to create the first one." : "Try another search or create it."
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        if !filteredCatalog.isEmpty {
                            // The list's products in one card.
                            VStack(spacing: 0) {
                                ForEach(Array(filteredCatalog.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        Rectangle().fill(ALIColors.outline).frame(height: 1).padding(.leading, 30)
                                    }
                                    if editMode {
                                        EditableCatalogRow(
                                            item: item,
                                            isSelected: selected.contains(item.id),
                                            onToggle: {
                                                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                                            },
                                            onRename: {
                                                Track.event("grocery_item_edit_tap")
                                                renamingItem = item
                                                renameText = item.name
                                            }
                                        )
                                    } else {
                                        CatalogItemRow(
                                            item: item,
                                            pendingEntry: pendingEntries[item.id],
                                            onAdd: { addToList(item) },
                                            onQuantityCommit: { entry in pushEntry(entry) },
                                            onRemove: { entry in removeEntry(entry) }
                                        )
                                    }
                                }
                            }
                            .background(ALIColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(ALIColors.outline, lineWidth: 1)
                            )
                        }

                        if !others.isEmpty {
                            otherListsSection(others)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            // Edit mode: delete the selected products in one go.
            if editMode {
                ALIPrimaryButton(
                    text: selected.isEmpty ? "Delete" : "Delete (\(selected.count))",
                    enabled: !selected.isEmpty,
                    accent: ALIColors.error
                ) { confirmBulkDelete = true }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ALIColors.background.ignoresSafeArea())
        .offset(x: swipeOffset)
        .simultaneousGesture(edgeSwipeBack)
        .alert("Rename item", isPresented: Binding(get: { renamingItem != nil }, set: { if !$0 { renamingItem = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingItem = nil }
            Button("Save") {
                if let item = renamingItem, !renameText.trimmed.isEmpty {
                    Track.event("grocery_item_renamed", ["item_name": renameText.trimmed])
                    item.name = renameText.trimmed
                    if let familyID = familySession.familyID { dataSync.pushGroceryItem(item, familyID: familyID) }
                }
                renamingItem = nil
            }
        }
        .aliDeleteConfirmDialog(
            isPresented: $confirmBulkDelete,
            itemName: bulkDeleteName
        ) {
            deleteSelected()
        }
    }

    /// Back, title, Edit / Done (same round buttons as the other screens).
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ALIColors.ink)
                    .frame(width: 36, height: 36)
                    .background(ALIColors.surface)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Add to \(currentListName)")
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
            Spacer(minLength: 0)

            if !listCatalog.isEmpty || editMode {
                Button {
                    if !editMode { Track.event("grocery_edit_mode") }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editMode.toggle()
                        selected = []
                    }
                } label: {
                    Image(systemName: editMode ? "checkmark" : "pencil")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(editMode ? ALIColors.onAccent : ALIColors.shoppingAccent)
                        .frame(width: 36, height: 36)
                        .background(editMode ? ALIColors.shoppingAccent : ALIColors.surface)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(editMode ? Text("Done") : Text("Edit"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(minHeight: 56)
    }

    /// Swipe from the left edge to go back.
    private var edgeSwipeBack: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard value.startLocation.x < 30, value.translation.width > 0 else { return }
                swipeOffset = value.translation.width
            }
            .onEnded { value in
                guard value.startLocation.x < 30 else { return }
                if value.translation.width > 120 || value.predictedEndTranslation.width > 240 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { swipeOffset = 0 }
                }
            }
    }

    private var bulkDeleteName: String {
        let items = catalog.filter { selected.contains($0.id) }
        if items.count == 1 { return items[0].name }
        return String(localized: "\(items.count) items")
    }

    @ViewBuilder
    private func otherListsSection(_ others: [OtherProduct]) -> some View {
        let expanded = showOtherLists || !searchText.trimmed.isEmpty
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showOtherLists.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text("From other lists (\(others.count))")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                Spacer()
                if searchText.trimmed.isEmpty {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!searchText.trimmed.isEmpty)

        if expanded {
            ForEach(others) { other in
                OtherListItemRow(name: other.item.name, listName: other.listName) {
                    copyFromOtherList(other.item)
                }
            }
        }
    }

    // MARK: Actions

    private func addToList(_ item: GroceryItem, source: String = "catalog") {
        Track.event("shopping_item_added", [
            "item_name": item.name,
            "source": source,
            "searching": !searchText.trimmed.isEmpty,
            "catalog_size": listCatalog.count
        ])
        // Old products without a list get pinned to the one they're used in.
        if item.listID == nil {
            item.listID = listID
            if let familyID = familySession.familyID { dataSync.pushGroceryItem(item, familyID: familyID) }
        }
        let entry = ShoppingListEntry(itemID: item.id, listID: listID, name: item.name)
        modelContext.insert(entry)
        pushEntry(entry)
    }

    private func removeEntry(_ entry: ShoppingListEntry) {
        let entryID = entry.id
        Track.event("shopping_item_removed", ["item_name": entry.name, "was_checked": false, "where": "add_screen"])
        modelContext.delete(entry)
        dataSync.deleteShoppingListEntry(id: entryID)
    }

    private func deleteSelected() {
        let items = catalog.filter { selected.contains($0.id) }
        Track.event("grocery_items_deleted", ["count": items.count])
        for item in items {
            let itemID = item.id
            modelContext.delete(item)
            dataSync.deleteGroceryItem(id: itemID)
        }
        selected = []
        withAnimation(.easeInOut(duration: 0.2)) { editMode = false }
    }

    private func pushEntry(_ entry: ShoppingListEntry) {
        if let familyID = familySession.familyID { dataSync.pushShoppingListEntry(entry, familyID: familyID) }
    }

    /// Copies a product of another list into this one and adds it.
    private func copyFromOtherList(_ source: GroceryItem) {
        let item = GroceryItem(name: source.name, listID: listID)
        modelContext.insert(item)
        if let familyID = familySession.familyID { dataSync.pushGroceryItem(item, familyID: familyID) }
        addToList(item, source: "other_list")
    }

    private func createFromSearchIfNeeded() {
        let name = searchText.trimmed
        guard !name.isEmpty, !exactMatchExists else { return }
        let item = GroceryItem(name: name, listID: listID)
        modelContext.insert(item)
        if let familyID = familySession.familyID { dataSync.pushGroceryItem(item, familyID: familyID) }
        Track.event("grocery_item_created", ["item_name": name, "catalog_size": listCatalog.count + 1])
        addToList(item, source: "new_item")
        searchText = ""
    }
}

/// A product of another list, with the name of the list it comes from.
private struct OtherProduct: Identifiable {
    let item: GroceryItem
    let listName: String
    var id: UUID { item.id }
}

/// A product of this list. Tap adds one more (the first tap adds it); once
/// added, − n + adjusts it (− to 0 removes it). Taps update a local count
/// right away and are saved after a short pause, so fast taps don't race
/// the sync.
private struct CatalogItemRow: View {
    let item: GroceryItem
    let pendingEntry: ShoppingListEntry?
    let onAdd: () -> Void
    let onQuantityCommit: (ShoppingListEntry) -> Void
    let onRemove: (ShoppingListEntry) -> Void

    /// Count not saved yet (nil = show what's saved). 0 = being removed.
    @State private var local: Int?

    private var accent: Color { ALIColors.shoppingAccent }
    private var savedCount: Int { Int(pendingEntry?.quantity?.trimmed ?? "") ?? 1 }
    private var inList: Bool { local.map { $0 > 0 } ?? (pendingEntry != nil) }
    private var shown: Int { local ?? savedCount }

    var body: some View {
        HStack(spacing: 10) {
            // Accent bar marks the products already in the list.
            RoundedRectangle(cornerRadius: 2)
                .fill(inList ? accent : Color.clear)
                .frame(width: 4, height: 24)
            Text(item.name)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if inList {
                QuantityCircleButton(systemImage: "minus", foreground: accent, background: ALIColors.surfaceVariant) {
                    change(shown - 1, where: "add_screen_stepper")
                }
                Text(verbatim: local == nil ? shoppingQuantityLabel(pendingEntry?.quantity) : "\(shown)")
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                    .frame(minWidth: 20)
                QuantityCircleButton(systemImage: "plus", foreground: ALIColors.onAccent, background: accent) {
                    change(shown + 1, where: "add_screen_stepper")
                }
            } else {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(accent)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .onTapGesture { change(inList ? shown + 1 : 1, where: "add_screen_tap") }
        // Save after a pause (and once the entry exists).
        .task(id: TaskKey(local: local, entryID: pendingEntry?.id)) {
            guard let value = local else { return }
            guard let entry = pendingEntry else {
                if value == 0 { local = nil }
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if value < 1 {
                onRemove(entry)
            } else if value != savedCount {
                entry.quantity = value > 1 ? "\(value)" : nil
                onQuantityCommit(entry)
            }
        }
        // The saved value caught up: drop the local one.
        .onChange(of: savedCount) { _, saved in
            if pendingEntry != nil, local == saved { local = nil }
        }
        .onChange(of: pendingEntry?.quantity) { _, _ in
            if pendingEntry != nil, local == savedCount { local = nil }
        }
    }

    private struct TaskKey: Equatable {
        let local: Int?
        let entryID: UUID?
    }

    private func change(_ value: Int, where source: String) {
        if pendingEntry == nil && local == nil {
            onAdd()
            local = 1
            return
        }
        Track.event("shopping_item_quantity", ["has_quantity": value > 1, "where": source])
        local = max(0, value)
    }
}

/// Edit mode row: tap selects it (for bulk delete); the pencil renames it.
private struct EditableCatalogRow: View {
    let item: GroceryItem
    let isSelected: Bool
    let onToggle: () -> Void
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isSelected ? ALIColors.error : ALIColors.surface)
                    .frame(width: 24, height: 24)
                Circle()
                    .stroke(isSelected ? ALIColors.error : ALIColors.outline, lineWidth: 1.5)
                    .frame(width: 24, height: 24)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ALIColors.onAccent)
                }
            }
            Text(item.name)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onRename) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename item")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
        .background(isSelected ? ALIColors.error.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

/// Product from another list: adding it copies it into the active list.
private struct OtherListItemRow: View {
    let name: String
    let listName: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Text(listName)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ALIColors.shoppingAccent)
                .frame(width: 34, height: 34)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ALIColors.outline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        // The whole row adds it.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onAdd)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
