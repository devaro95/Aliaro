import SwiftUI
import SwiftData

/// Reads a recipe: photo, category, time, servings, ingredients and steps.
/// From here it can be added to the weekly menu, edited or deleted.
struct RecipeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let recipe: Recipe

    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var showEdit = false
    @State private var showAddToMenu = false
    @State private var showDeleteConfirm = false

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }
    private var canEdit: Bool { currentMember?.can(.recipesEdit) ?? true }
    private var canDelete: Bool { currentMember?.can(.recipesDelete) ?? true }
    private var canEditMenu: Bool { currentMember?.can(.weeklyMenuEdit) ?? true }

    private var steps: [String] {
        recipe.steps
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        trackedBody.trackScreen("recipe_detail")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image = recipe.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(recipe.name)
                            .font(ALITypography.headlineLarge)
                            .foregroundStyle(ALIColors.ink)
                        FlowChips {
                            ForEach(recipe.recipeCategories) { category in
                                metaPill(systemImage: category.systemImage, text: Text(category.label))
                            }
                            if let minutes = recipe.prepMinutes, minutes > 0 {
                                metaPill(systemImage: "timer", text: Text("Prep \(RecipeFormatting.duration(minutes))"))
                            }
                            if let minutes = recipe.cookMinutes, minutes > 0 {
                                metaPill(systemImage: "flame.fill", text: Text("Cook \(RecipeFormatting.duration(minutes))"))
                            }
                            metaPill(
                                systemImage: "person.2.fill",
                                text: Text(recipe.servings == 1 ? String(localized: "1 serving") : String(localized: "\(recipe.servings) servings"))
                            )
                        }
                    }

                    if canEditMenu {
                        ALIPrimaryButton(text: "Add to weekly menu", accent: ALIColors.recipesAccent) {
                            Track.event("recipe_add_to_menu_tap")
                            showAddToMenu = true
                        }
                    }

                    if !recipe.ingredients.isEmpty {
                        section("Ingredients") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, ingredient in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Circle()
                                            .fill(ALIColors.recipesAccent)
                                            .frame(width: 7, height: 7)
                                        Text(ingredient.name)
                                            .font(ALITypography.bodyLarge)
                                            .foregroundStyle(ALIColors.ink)
                                        Spacer(minLength: 8)
                                        if let amount = RecipeFormatting.amount(of: ingredient) {
                                            Text(amount)
                                                .font(ALITypography.bodyLarge.weight(.semibold))
                                                .foregroundStyle(ALIColors.ink)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !steps.isEmpty {
                        section("How to make it") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(ALIColors.onAccent)
                                            .frame(width: 26, height: 26)
                                            .background(ALIColors.recipesAccent)
                                            .clipShape(Circle())
                                        Text(step)
                                            .font(ALITypography.bodyLarge)
                                            .foregroundStyle(ALIColors.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }

                    if let name = recipe.createdByName, !name.isEmpty {
                        Text("Added by \(name)")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .background(ALIColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if canEdit || canDelete {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if canEdit {
                                Button {
                                    Track.event("recipe_edit_tap")
                                    showEdit = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }
                            if canDelete {
                                Button(role: .destructive) {
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddRecipeSheet(recipeToEdit: recipe)
            }
            .sheet(isPresented: $showAddToMenu) {
                AddRecipeToMenuSheet(recipe: recipe)
            }
            .aliDeleteConfirmDialog(isPresented: $showDeleteConfirm, itemName: recipe.name) {
                delete()
            }
        }
        .presentationDetents([.large])
    }

    private func metaPill(systemImage: String, text: Text) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
            text.font(ALITypography.labelLarge)
        }
        .foregroundStyle(ALIColors.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ALIColors.recipesAccent.opacity(0.3))
        .clipShape(Capsule())
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                content()
            }
        }
    }

    private func delete() {
        let recipeID = recipe.id
        let recipeName = recipe.name
        let photoPath = recipe.photoPath
        modelContext.delete(recipe)
        dataSync.deleteRecipe(id: recipeID, photoPath: photoPath)
        RecipeDishLink.remove(recipeID: recipeID, modelContext: modelContext, dataSync: dataSync)
        if let familyID = familySession.familyID {
            dataSync.logActivity(
                entityType: "recipe", entityName: recipeName, action: "deleted",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID, modelContext: modelContext
            )
        }
        dismiss()
    }
}

/// Picks a day and lunch/dinner to plan a recipe in the weekly menu.
/// Replaces whatever was planned in that slot.
struct AddRecipeToMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let recipe: Recipe

    @Query private var entries: [MealPlanEntry]

    @State private var day: Weekday = {
        let systemWeekday = Calendar.current.component(.weekday, from: Date())
        return Weekday(rawValue: (systemWeekday + 5) % 7) ?? .monday
    }()
    @State private var mealType: MealType = .lunch

    private var currentDishName: String? {
        entries.first { $0.weekday == day.rawValue && $0.mealType == mealType.rawValue }?.dishName
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(Weekday.allCases) { weekday in
                        RecipeChip(title: weekday.shortLabel, isSelected: day == weekday) {
                            day = weekday
                        }
                    }
                }

                if let currentDishName, currentDishName != recipe.name {
                    Text("Replaces \"\(currentDishName)\"")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                }

                Spacer()

                ALIPrimaryButton(text: "Add to menu", accent: ALIColors.recipesAccent) {
                    save()
                }
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationTitle("Add to weekly menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .trackScreen("recipe_add_to_menu")
    }

    private func save() {
        let familyID = familySession.familyID
        RecipeDishLink.sync(recipe, modelContext: modelContext, dataSync: dataSync, familyID: familyID)

        let entry: MealPlanEntry
        if let existing = entries.first(where: { $0.weekday == day.rawValue && $0.mealType == mealType.rawValue }) {
            existing.dishID = recipe.id
            existing.dishName = recipe.name
            existing.updatedAt = .now
            entry = existing
        } else {
            entry = MealPlanEntry(weekday: day.rawValue, mealType: mealType.rawValue, dishID: recipe.id, dishName: recipe.name)
            modelContext.insert(entry)
        }
        if let familyID { dataSync.pushMealPlanEntry(entry, familyID: familyID) }
        Track.event("recipe_added_to_menu", ["weekday": String(describing: day), "meal": String(describing: mealType)])
        dismiss()
    }
}
