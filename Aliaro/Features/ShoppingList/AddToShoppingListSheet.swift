import SwiftUI
import SwiftData

/// Sheet to add items to the active shopping list. It's also where the
/// household's own catalog lives: search, create, edit and delete items —
/// "the many items we create" that are later drawn on for the shopping list.
struct AddToShoppingListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    /// Active list (tab) that the items chosen here get added to.
    let listID: UUID

    @Query(sort: \GroceryItem.name) private var catalog: [GroceryItem]
    @Query private var entries: [ShoppingListEntry]

    @State private var searchText = ""
    @State private var renamingItem: GroceryItem?
    @State private var renameText = ""
    @State private var itemPendingDelete: GroceryItem?

    /// IDs of items that are already pending (unchecked) in the active
    /// list — no point adding them again until they're bought.
    private var pendingItemIDs: Set<UUID> {
        Set(entries.filter { !$0.isChecked && $0.listID == listID }.map(\.itemID))
    }

    private var filteredCatalog: [GroceryItem] {
        guard !searchText.trimmed.isEmpty else { return catalog }
        return catalog.filter { $0.name.localizedCaseInsensitiveContains(searchText.trimmed) }
    }

    private var exactMatchExists: Bool {
        catalog.contains { $0.name.compare(searchText.trimmed, options: .caseInsensitive) == .orderedSame }
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

                if filteredCatalog.isEmpty {
                    ALIEmptyState(
                        emoji: "✨",
                        title: catalog.isEmpty ? "No items yet" : "No results",
                        subtitle: catalog.isEmpty ? "Type above to create the first one." : "Try another search or create it."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(filteredCatalog) { item in
                                CatalogItemRow(
                                    item: item,
                                    isPending: pendingItemIDs.contains(item.id),
                                    onAdd: { addToShoppingList(item) },
                                    onEdit: {
                                        Track.event("grocery_item_edit_tap")
                                        renamingItem = item
                                        renameText = item.name
                                    },
                                    onDelete: { itemPendingDelete = item }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(ALIColors.background)
            .navigationTitle("Add to shopping list")
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

    private func addToShoppingList(_ item: GroceryItem, source: String = "catalog") {
        Track.event("shopping_item_added", [
            "item_name": item.name,
            "source": source,
            "searching": !searchText.trimmed.isEmpty,
            "catalog_size": catalog.count
        ])
        let entry = ShoppingListEntry(itemID: item.id, listID: listID, name: item.name)
        modelContext.insert(entry)
        if let familyID = familySession.familyID { dataSync.pushShoppingListEntry(entry, familyID: familyID) }
    }

    private func createFromSearchIfNeeded() {
        let name = searchText.trimmed
        guard !name.isEmpty, !exactMatchExists else { return }
        let item = GroceryItem(name: name)
        modelContext.insert(item)
        if let familyID = familySession.familyID { dataSync.pushGroceryItem(item, familyID: familyID) }
        Track.event("grocery_item_created", ["item_name": name, "catalog_size": catalog.count + 1])
        addToShoppingList(item, source: "new_item")
        searchText = ""
    }
}

/// Row for a catalog item within the add sheet.
private struct CatalogItemRow: View {
    let item: GroceryItem
    let isPending: Bool
    let onAdd: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(item.name)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)

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
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
