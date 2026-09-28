import SwiftUI
import SwiftData

/// Sheet to choose the dish for a slot (lunch or dinner) of the weekly
/// menu: the family's **recipes** first (with photo), then the plain
/// dish catalog. It's also where that catalog lives: search, create, edit
/// and delete — just like the shopping list catalog. Recipes are edited
/// from Recipes, not here.
struct SelectDishSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let mealType: MealType
    let onSelect: (DishSelection) -> Void

    @Query(sort: \Dish.name) private var catalog: [Dish]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    /// Dishes that are a recipe's twin (same id) — listed as recipes instead.
    private var recipeIDs: Set<UUID> { Set(recipes.map(\.id)) }

    private var filteredRecipes: [Recipe] {
        guard !searchText.trimmed.isEmpty else { return recipes }
        return recipes.filter { $0.name.localizedCaseInsensitiveContains(searchText.trimmed) }
    }

    @State private var searchText = ""
    @State private var renamingDish: Dish?
    @State private var renameText = ""
    @State private var dishPendingDelete: Dish?

    /// Plain dishes only (recipe twins show up in the recipes section).
    private var filteredCatalog: [Dish] {
        let dishes = catalog.filter { !recipeIDs.contains($0.id) }
        guard !searchText.trimmed.isEmpty else { return dishes }
        return dishes.filter { $0.name.localizedCaseInsensitiveContains(searchText.trimmed) }
    }

    private var exactMatchExists: Bool {
        let name = searchText.trimmed
        return catalog.contains { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
            || recipes.contains { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    var body: some View {
        trackedBody.trackScreen("dish_picker")
    }

    @ViewBuilder
    private var trackedBody: some View {
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

                if filteredCatalog.isEmpty && filteredRecipes.isEmpty {
                    ALIEmptyState(
                        icon: ALIIcon.dining,
                        title: catalog.isEmpty && recipes.isEmpty ? "No dishes yet" : "No results",
                        subtitle: catalog.isEmpty && recipes.isEmpty ? "Type above to create the first one." : "Try another search or create it."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !filteredRecipes.isEmpty {
                                sectionHeader("Recipes")
                                ForEach(filteredRecipes) { recipe in
                                    RecipePickRow(recipe: recipe) { select(recipe) }
                                }
                            }
                            if !filteredCatalog.isEmpty {
                                if !filteredRecipes.isEmpty {
                                    sectionHeader("Dishes").padding(.top, 8)
                                }
                            }
                            ForEach(filteredCatalog) { dish in
                                DishCatalogRow(
                                    dish: dish,
                                    isRecipe: false,
                                    onSelect: { select(dish) },
                                    onEdit: {
                                        Track.event("dish_edit_tap")
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
                        Track.event("dish_renamed", ["dish_name": renameText.trimmed])
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
                    Track.event("dish_deleted", ["dish_name": dish.name])
                    modelContext.delete(dish)
                    dataSync.deleteDish(id: dishID)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(ALITypography.labelLarge)
            .foregroundStyle(ALIColors.mutedInk)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    /// Picks a recipe: makes sure its twin dish exists in the catalog
    /// (recipes created before the link had none) and selects it.
    private func select(_ recipe: Recipe) {
        RecipeDishLink.sync(recipe, modelContext: modelContext, dataSync: dataSync, familyID: familySession.familyID)
        Track.event("dish_selected", [
            "dish_name": recipe.name,
            "meal": String(describing: mealType),
            "is_new": false,
            "is_recipe": true,
            "searching": !searchText.trimmed.isEmpty,
            "catalog_size": catalog.count
        ])
        onSelect(DishSelection(id: recipe.id, name: recipe.name))
        dismiss()
    }

    private func select(_ dish: Dish, isNew: Bool = false) {
        Track.event("dish_selected", [
            "dish_name": dish.name,
            "meal": String(describing: mealType),
            "is_new": isNew,
            "searching": !searchText.trimmed.isEmpty,
            "catalog_size": catalog.count
        ])
        onSelect(DishSelection(id: dish.id, name: dish.name))
        dismiss()
    }

    private func createFromSearchIfNeeded() {
        let name = searchText.trimmed
        guard !name.isEmpty, !exactMatchExists else { return }
        let dish = Dish(name: name)
        modelContext.insert(dish)
        if let familyID = familySession.familyID { dataSync.pushDish(dish, familyID: familyID) }
        Track.event("dish_created", ["dish_name": name, "catalog_size": catalog.count + 1])
        select(dish, isNew: true)
    }
}

/// Row for a recipe within the selection sheet: photo, name and time.
private struct RecipePickRow: View {
    let recipe: Recipe
    let onSelect: () -> Void

    private var totalMinutes: Int { (recipe.prepMinutes ?? 0) + (recipe.cookMinutes ?? 0) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RecipeThumbnail(recipe: recipe, size: 44, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                        .font(ALITypography.bodyLarge.weight(.semibold))
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(1)
                    if totalMinutes > 0 {
                        Label(String(localized: "\(totalMinutes) min"), systemImage: "clock")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ALIColors.onAccent)
                    .frame(width: 24, height: 24)
                    .background(ALIColors.recipesAccent)
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ALIColors.outline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Row for a catalog dish within the selection sheet.
private struct DishCatalogRow: View {
    let dish: Dish
    var isRecipe: Bool = false
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    if isRecipe {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ALIColors.onAccent)
                            .frame(width: 24, height: 24)
                            .background(ALIColors.recipesAccent)
                            .clipShape(Circle())
                    }
                    Text(dish.name)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isRecipe {
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
        }
        .frame(minHeight: 30)
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
