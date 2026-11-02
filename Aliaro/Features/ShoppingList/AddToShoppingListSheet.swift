import SwiftUI
import SwiftData

/// Sheet to add products to the active list. It's also where the list's
/// own products live: search, create, edit and delete them. Each product
/// belongs to its list; products of the other lists show below ("From
/// other lists") and adding one copies it into this list. Once added, a
/// product can get an optional quantity right there.
struct AddToShoppingListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    /// Active list (tab) that the products chosen here get added to.
    let listID: UUID

    @Query(sort: \GroceryItem.name) private var catalog: [GroceryItem]
    @Query(sort: \ShoppingList.position) private var lists: [ShoppingList]
    @Query private var entries: [ShoppingListEntry]

    @State private var searchText = ""
    @State private var renamingItem: GroceryItem?
    @State private var renameText = ""
    @State private var itemPendingDelete: GroceryItem?
    @State private var showOtherLists = false

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
        NavigationStack {
            VStack(spacing: 14) {
                ALITextField(placeholder: "Search or create item…", text: $searchText, onSubmit: createFromSearchIfNeeded)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if !searchText.trimmed.isEmpty && !exactMatchExists {
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
                    .padding(.horizontal, 20)
                }

                let others = otherProducts
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
                            ForEach(filteredCatalog) { item in
                                CatalogItemRow(
                                    item: item,
                                    pendingEntry: pendingEntries[item.id],
                                    onAdd: { addToList(item) },
                                    onQuantityCommit: { entry in pushEntry(entry) },
                                    onEdit: {
                                        Track.event("grocery_item_edit_tap")
                                        renamingItem = item
                                        renameText = item.name
                                    },
                                    onDelete: { itemPendingDelete = item }
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
            }
            .background(ALIColors.background)
            .navigationTitle(Text("Add to \(currentListName)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
                isPresented: Binding(get: { itemPendingDelete != nil }, set: { if !$0 { itemPendingDelete = nil } }),
                itemName: itemPendingDelete?.name ?? ""
            ) {
                if let item = itemPendingDelete {
                    let itemID = item.id
                    Track.event("grocery_item_deleted", ["item_name": item.name])
                    modelContext.delete(item)
                    dataSync.deleteGroceryItem(id: itemID)
                }
            }
        }
        .presentationDetents([.medium, .large])
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

/// Row for a catalog item within the add sheet. Once it's in the list, an
/// optional quantity can be typed right below the name.
private struct CatalogItemRow: View {
    let item: GroceryItem
    let pendingEntry: ShoppingListEntry?
    let onAdd: () -> Void
    let onQuantityCommit: (ShoppingListEntry) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var quantity = ""
    @FocusState private var quantityFocused: Bool

    private var isPending: Bool { pendingEntry != nil }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                if pendingEntry != nil {
                    TextField("Quantity (optional)", text: $quantity)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.ink)
                        .focused($quantityFocused)
                        .submitLabel(.done)
                        .onSubmit(commitQuantity)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Button(action: onAdd) {
                Image(systemName: isPending ? "checkmark" : "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ALIColors.onAccent)
                    .frame(width: 34, height: 34)
                    .background(isPending ? ALIColors.success : ALIColors.shoppingAccent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isPending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
        .onAppear { quantity = pendingEntry?.quantity ?? "" }
        .onChange(of: pendingEntry?.id) { _, _ in quantity = pendingEntry?.quantity ?? "" }
        .onChange(of: quantityFocused) { _, focused in if !focused { commitQuantity() } }
        .onDisappear(perform: commitQuantity)
    }

    private func commitQuantity() {
        guard let entry = pendingEntry else { return }
        let value = quantity.trimmed.isEmpty ? nil : quantity.trimmed
        guard value != entry.quantity else { return }
        entry.quantity = value
        Track.event("shopping_item_quantity", ["has_quantity": value != nil, "where": "add_sheet"])
        onQuantityCommit(entry)
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
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ALIColors.shoppingAccent)
                    .frame(width: 34, height: 34)
                    .background(ALIColors.surfaceVariant)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ALIColors.outline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
