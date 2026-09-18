import SwiftUI
import SwiftData

/// Sheet to choose the dish for a slot (lunch or dinner) of the weekly
/// menu. It's also where the household's own dish catalog lives: search,
/// create, edit and delete — just like the shopping list catalog.
struct SelectDishSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let mealType: MealType
    let onSelect: (DishSelection) -> Void

    @Query(sort: \Dish.name) private var catalog: [Dish]

    @State private var searchText = ""
    @State private var renamingDish: Dish?
    @State private var renameText = ""
    @State private var dishPendingDelete: Dish?

    private var filteredCatalog: [Dish] {
        guard !searchText.trimmed.isEmpty else { return catalog }
        return catalog.filter { $0.name.localizedCaseInsensitiveContains(searchText.trimmed) }
    }

    private var exactMatchExists: Bool {
        catalog.contains { $0.name.compare(searchText.trimmed, options: .caseInsensitive) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ALITextField(placeholder: "Search or create dish…", text: $searchText, onSubmit: createFromSearchIfNeeded)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if !searchText.trimmed.isEmpty && !exactMatchExists {
                    Button(action: createFromSearchIfNeeded) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Create \"\(searchText.trimmed)\" and choose")
                            Spacer()
                        }
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.onAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .background(ALIColors.weeklyMenuAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                }

                if filteredCatalog.isEmpty {
                    ALIEmptyState(
                        emoji: "🍽️",
                        title: catalog.isEmpty ? "No dishes yet" : "No results",
                        subtitle: catalog.isEmpty ? "Type above to create the first one." : "Try another search or create it."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(filteredCatalog) { dish in
                                DishCatalogRow(
                                    dish: dish,
                                    onSelect: { select(dish) },
                                    onEdit: {
                                        renamingDish = dish
                                        renameText = dish.name
                                    },
                                    onDelete: { dishPendingDelete = dish }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(ALIColors.background)
            .navigationTitle(mealType == .lunch ? "Choose lunch" : "Choose dinner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Rename dish", isPresented: Binding(get: { renamingDish != nil }, set: { if !$0 { renamingDish = nil } })) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renamingDish = nil }
                Button("Save") {
                    if let dish = renamingDish, !renameText.trimmed.isEmpty {
                        dish.name = renameText.trimmed
                        if let familyID = familySession.familyID { dataSync.pushDish(dish, familyID: familyID) }
                    }
                    renamingDish = nil
                }
            }
            .aliDeleteConfirmDialog(
                isPresented: Binding(get: { dishPendingDelete != nil }, set: { if !$0 { dishPendingDelete = nil } }),
                itemName: dishPendingDelete?.name ?? ""
            ) {
                if let dish = dishPendingDelete {
                    let dishID = dish.id
                    modelContext.delete(dish)
                    dataSync.deleteDish(id: dishID)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func select(_ dish: Dish) {
        onSelect(DishSelection(id: dish.id, name: dish.name))
        dismiss()
    }

    private func createFromSearchIfNeeded() {
        let name = searchText.trimmed
        guard !name.isEmpty, !exactMatchExists else { return }
        let dish = Dish(name: name)
        modelContext.insert(dish)
        if let familyID = familySession.familyID { dataSync.pushDish(dish, familyID: familyID) }
        select(dish)
    }
}

/// Row for a catalog dish within the selection sheet.
private struct DishCatalogRow: View {
    let dish: Dish
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Text(dish.name)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

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
