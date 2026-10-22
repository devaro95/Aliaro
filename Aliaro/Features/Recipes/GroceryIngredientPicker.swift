import SwiftUI
import SwiftData

/// Multi-select list of the shopping list catalog (`GroceryItem`) to add
/// them as recipe ingredients in one go. Items already in the recipe are
/// shown as added and can't be picked again.
struct GroceryIngredientPicker: View {
    @Environment(\.dismiss) private var dismiss

    /// Lowercased names already in the recipe.
    let alreadyAdded: Set<String>
    let onAdd: ([String]) -> Void

    @Query(sort: \GroceryItem.name) private var catalog: [GroceryItem]

    @State private var searchText = ""
    @State private var selected: [String] = []

    private var filtered: [GroceryItem] {
        let query = searchText.trimmed
        guard !query.isEmpty else { return catalog }
        return catalog.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ALITextField(placeholder: "Search product…", text: $searchText)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if filtered.isEmpty {
                    ALIEmptyState(
                        icon: ALIIcon.cart,
                        title: catalog.isEmpty ? "Your shopping list is empty" : "No results",
                        subtitle: catalog.isEmpty ? "Products you add to the shopping list will show up here." : "Try another search."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(filtered) { item in
                                row(for: item)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }

                ALIPrimaryButton(
                    text: selected.isEmpty ? "Add ingredients" : "Add \(selected.count) ingredients",
                    enabled: !selected.isEmpty,
                    accent: ALIColors.recipesAccent
                ) {
                    Track.event("recipe_ingredients_from_shopping_added", ["count": selected.count])
                    onAdd(selected)
                    dismiss()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(ALIColors.background)
            .navigationTitle("From shopping list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .trackScreen("recipe_grocery_picker")
    }

    private func row(for item: GroceryItem) -> some View {
        let added = alreadyAdded.contains(item.name.lowercased())
        let isSelected = selected.contains(item.name)
        return Button {
            if isSelected {
                selected.removeAll { $0 == item.name }
            } else {
                selected.append(item.name)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: added || isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(added ? ALIColors.mutedInk.opacity(0.5) : (isSelected ? ALIColors.recipesAccent : ALIColors.mutedInk.opacity(0.6)))
                Text(item.name)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(added ? ALIColors.mutedInk : ALIColors.ink)
                    .lineLimit(1)
                Spacer()
                if added {
                    Text("Added")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? ALIColors.recipesAccent : ALIColors.outline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(added)
    }
}
