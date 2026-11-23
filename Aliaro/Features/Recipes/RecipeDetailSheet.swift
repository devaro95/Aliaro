import SwiftUI
import SwiftData

/// Reads a recipe: photo, category, time, servings, ingredients and steps.
/// From here it can be added to the weekly menu, edited or deleted.
struct RecipeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
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
                    // Header: the recipe name as the big title (up to two lines)
                    // with the "…" menu to its right. Closes by swiping down.
                    HStack(alignment: .center, spacing: 10) {
                        Text(recipe.name)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(ALIColors.ink)
                            .lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        if canEdit || canDelete {
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
                                ALISheetIconLabel(systemImage: "ellipsis")
                            }
                            .accessibilityLabel(Text("More options"))
                        }
                    }
                    .padding(.top, 12)

                    if let image = recipe.image {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .aspectRatio(RecipeFormatting.photoAspectRatio, contentMode: .fit)
                            .overlay {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
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

                    if !recipe.links.isEmpty {
                        section("Links") {
                            VStack(spacing: 8) {
                                ForEach(Array(recipe.links.enumerated()), id: \.offset) { index, link in
                                    linkRow(link, name: recipe.linkName(at: index))
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
            .toolbar(.hidden, for: .navigationBar)
            .presentationDragIndicator(.visible)
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

    /// A link: its name (if it has one) with the site below, or the site and
    /// the rest of the address; opens in the browser.
    private func linkRow(_ link: String, name: String?) -> some View {
        Button {
            Track.event("recipe_link_open", ["host": RecipeLink.host(link)])
            if let url = URL(string: link) { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ALIColors.onAccent)
                    .frame(width: 34, height: 34)
                    .background(ALIColors.recipesAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? RecipeLink.host(link))
                        .font(ALITypography.bodyLarge.weight(.semibold))
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(1)
                    let path = name == nil ? RecipeLink.path(link) : RecipeLink.host(link)
                    if !path.isEmpty {
                        Text(path)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ALIColors.mutedInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { UIPasteboard.general.string = link } label: { Label("Copy link", systemImage: "doc.on.doc") }
            ShareLink(item: link) { Label("Share", systemImage: "square.and.arrow.up") }
        }
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
/// Added next to whatever that meal already has (a meal can have several dishes).
struct AddRecipeToMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let recipe: Recipe

    @Query private var entries: [MealPlanEntry]

    @State private var day: Date = MenuCalendar.today

    /// Today and the next 13 days.
    private var upcomingDays: [Date] {
        (0..<14).map { MenuCalendar.adding(days: $0, to: MenuCalendar.today) }
    }

    private func chipTitle(for date: Date) -> String {
        if MenuCalendar.isSameDay(date, .now) { return String(localized: "Today") }
        if MenuCalendar.isSameDay(date, MenuCalendar.adding(days: 1, to: MenuCalendar.today)) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.abbreviated).day()).capitalized
    }
    @State private var mealType: MealType = .lunch

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
                    ForEach(upcomingDays, id: \.self) { date in
                        RecipeChip(title: LocalizedStringKey(chipTitle(for: date)), isSelected: MenuCalendar.isSameDay(day, date)) {
                            day = date
                        }
                    }
                }

                Spacer()

                ALIPrimaryButton(text: "Add to menu", accent: ALIColors.recipesAccent) {
                    save()
                }
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationTitle("Add to weekly menu")
            .navigationBarTitleDisplayMode(.large)
            .presentationDragIndicator(.visible)
        }
        .presentationDetents([.medium])
        .trackScreen("recipe_add_to_menu")
    }

    private func save() {
        let familyID = familySession.familyID
        RecipeDishLink.sync(recipe, modelContext: modelContext, dataSync: dataSync, familyID: familyID)

        // Added next to whatever the meal already has (several dishes per meal).
        MenuWriter.add(
            DishSelection(id: recipe.id, name: recipe.name),
            date: day,
            mealType: mealType,
            entries: entries,
            modelContext: modelContext,
            dataSync: dataSync,
            familyID: familyID
        )
        Track.event("recipe_added_to_menu", [
            "days_ahead": MenuCalendar.calendar.dateComponents([.day], from: MenuCalendar.today, to: day).day ?? 0,
            "meal": String(describing: mealType)
        ])
        dismiss()
    }
}
