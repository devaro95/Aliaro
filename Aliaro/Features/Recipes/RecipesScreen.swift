import SwiftUI
import SwiftData

/// "Recipes" feature: the family's recipe book. Search, filter by
/// category, open a recipe to read it, add it to the weekly menu or edit it.
struct RecipesScreen: View {
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker

    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var searchText = ""
    @State private var selectedCategory: RecipeCategory?
    @State private var showAddSheet = false
    @State private var openedRecipe: Recipe?

    private var canEdit: Bool {
        members.first(where: \.isCurrentDevice)?.can(.recipesEdit) ?? true
    }

    private var filteredRecipes: [Recipe] {
        let query = searchText.trimmed
        return recipes.filter { recipe in
            (selectedCategory.map { recipe.categories.contains($0.rawValue) } ?? true)
                && (query.isEmpty
                    || recipe.name.localizedCaseInsensitiveContains(query)
                    || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        trackedBody.trackScreen("recipes")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Recipes", accent: ALIColors.recipesAccent) {
                    if canEdit {
                        ALIFloatingButton(accent: ALIColors.recipesAccent) {
                            Track.event("recipe_add_tap", ["recipes": recipes.count])
                            showAddSheet = true
                        }
                        .scaleEffect(0.72)
                    }
                }

                if recipes.isEmpty {
                    ALIEmptyState(
                        icon: ALIIcon.book,
                        title: "No recipes yet",
                        subtitle: "Save your family's recipes here and plan them in the weekly menu."
                    )
                } else {
                    ALITextField(placeholder: "Search recipe or ingredient…", text: $searchText)

                    categoryTabs

                    if filteredRecipes.isEmpty {
                        ALIEmptyState(icon: ALIIcon.search, title: "No results", subtitle: "Try another search or category.")
                    } else {
                        VStack(spacing: 10) {
                            ForEach(filteredRecipes) { recipe in
                                Button {
                                    Track.event("recipe_open", ["categories": recipe.categories.joined(separator: ",")])
                                    openedRecipe = recipe
                                } label: {
                                    RecipeRow(recipe: recipe)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .sheet(isPresented: $showAddSheet) {
            AddRecipeSheet(recipeToEdit: nil)
        }
        .sheet(item: $openedRecipe) { recipe in
            RecipeDetailSheet(recipe: recipe)
        }
    }

    /// One tab per category (plus "All") to filter the list.
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                RecipeChip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(RecipeCategory.allCases) { category in
                    RecipeChip(title: category.label, systemImage: category.systemImage, isSelected: selectedCategory == category) {
                        Track.event("recipe_filter_category", ["category": category.rawValue])
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
}

/// Card for a recipe in the list: photo, name, favorite mark and time/servings.
private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            RecipeThumbnail(recipe: recipe, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if recipe.categories.contains(RecipeCategory.favorites.rawValue) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(ALIColors.error)
                    }
                    Text(recipe.metaLabel)
                }
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
        }
        .padding(12)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
