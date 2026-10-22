import SwiftUI
import SwiftData
import PhotosUI

/// Creates or edits a recipe: photo, name, categories, servings, prep time,
/// ingredients (typed, or picked from the shopping list catalog) and
/// numbered steps (one field per step; Return starts the next one).
struct AddRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let recipeToEdit: Recipe?

    @State private var name = ""
    @State private var categories: Set<RecipeCategory> = []
    @State private var servings = 2
    @State private var prepMinutes = 0
    @State private var cookMinutes = 0
    @State private var editingTime: TimeField?

    private enum TimeField: String, Identifiable {
        case prep, cook
        var id: String { rawValue }
    }
    @State private var ingredients: [IngredientDraft] = [IngredientDraft()]
    @State private var steps: [TextDraft] = [TextDraft()]
    @State private var showGroceryPicker = false
    /// The vertical TextField reports a Return twice in the same update;
    /// remembers the last split ("<id>|<text>") so it only happens once.
    @State private var lastStepSplit: String?

    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoSource = false
    @State private var showLibrary = false
    @State private var showCamera = false
    /// Compressed JPEG picked in this session (nil = unchanged).
    @State private var newPhotoData: Data?
    @State private var removePhoto = false
    @State private var existingPhoto: UIImage?

    /// Focused ingredient or step row (both share one focus space).
    @FocusState private var focusedRow: UUID?

    private struct TextDraft: Identifiable {
        let id = UUID()
        var text = ""
    }

    private struct IngredientDraft: Identifiable {
        let id = UUID()
        var name = ""
        var quantityText = ""
        var unit: IngredientUnit = .grams

        init(name: String = "", quantityText: String = "", unit: IngredientUnit = .grams) {
            self.name = name
            self.quantityText = quantityText
            self.unit = unit
        }

        init(_ ingredient: RecipeIngredient) {
            self.init(
                name: ingredient.name,
                quantityText: RecipeFormatting.quantityText(ingredient.quantity),
                unit: ingredient.ingredientUnit ?? .grams
            )
        }

        var ingredient: RecipeIngredient {
            RecipeIngredient(
                name: name.trimmed,
                quantity: unit.needsQuantity ? RecipeFormatting.quantity(from: quantityText) : nil,
                unit: unit
            )
        }
    }

    /// Amount field of an ingredient row (kept apart from `focusedRow` ids).
    @FocusState private var focusedQuantity: UUID?

    private var isEditing: Bool { recipeToEdit != nil }

    /// Selected categories as stored raw values, in canonical order.
    private var categoryValues: [String] {
        RecipeCategory.allCases.filter(categories.contains).map(\.rawValue)
    }

    private var previewImage: UIImage? {
        if let newPhotoData { return UIImage(data: newPhotoData) }
        return removePhoto ? nil : existingPhoto
    }

    var body: some View {
        trackedBody.trackScreen("recipe_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoPicker
                    ALITextField(placeholder: "Recipe name", text: $name)
                    categoryCard
                    detailsCard
                    ingredientsCard
                    stepsCard

                    ALIPrimaryButton(
                        text: isEditing ? "Save" : "Create recipe",
                        enabled: !name.trimmed.isEmpty,
                        accent: ALIColors.recipesAccent
                    ) {
                        save()
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ALIColors.background)
            .navigationTitle(isEditing ? "Edit recipe" : "New recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: loadIfEditing)
            .sheet(item: $editingTime) { field in
                DurationPickerSheet(
                    title: field == .prep ? "Prep time" : "Cooking time",
                    minutes: field == .prep ? $prepMinutes : $cookMinutes
                )
            }
            .sheet(isPresented: $showGroceryPicker) {
                GroceryIngredientPicker(alreadyAdded: Set(ingredients.map { $0.name.trimmed.lowercased() })) { names in
                    addIngredients(names)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        setPhoto(data)
                    }
                    photoItem = nil
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    /// Tapping the photo asks where it comes from: camera or library.
    private var photoPicker: some View {
        Button {
            if CameraPicker.isAvailable {
                showPhotoSource = true
            } else {
                showLibrary = true
            }
        } label: {
            ZStack {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ALIColors.recipesAccent.opacity(0.25)
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 26, weight: .semibold))
                        Text("Add photo")
                            .font(ALITypography.titleLarge)
                    }
                    .foregroundStyle(ALIColors.ink.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if previewImage != nil {
                Button {
                    newPhotoData = nil
                    removePhoto = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .confirmationDialog("Add photo", isPresented: $showPhotoSource, titleVisibility: .hidden) {
            Button("Take photo") {
                Track.event("recipe_photo_source", ["source": "camera"])
                showCamera = true
            }
            Button("Choose from library") {
                Track.event("recipe_photo_source", ["source": "library"])
                showLibrary = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                setPhoto(data)
            }
            .ignoresSafeArea()
        }
    }

    private func setPhoto(_ data: Data) {
        guard let jpeg = RecipeFormatting.compressedJPEG(from: data) else { return }
        newPhotoData = jpeg
        removePhoto = false
        Track.event("recipe_photo_picked")
    }

    private var categoryCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Categories")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(RecipeCategory.allCases) { option in
                        RecipeChip(title: option.label, systemImage: option.systemImage, isSelected: categories.contains(option)) {
                            if categories.contains(option) {
                                categories.remove(option)
                            } else {
                                categories.insert(option)
                            }
                        }
                    }
                }
            }
        }
    }

    private var detailsCard: some View {
        ALICard {
            VStack(spacing: 14) {
                Stepper(value: $servings, in: 1...20) {
                    HStack {
                        Label("Servings", systemImage: "person.2.fill")
                        Spacer()
                        Text("\(servings)").foregroundStyle(ALIColors.mutedInk)
                    }
                }
                Divider().overlay(ALIColors.outline)
                timeRow("Prep time", systemImage: "timer", minutes: prepMinutes) { editingTime = .prep }
                Divider().overlay(ALIColors.outline)
                timeRow("Cooking time", systemImage: "flame.fill", minutes: cookMinutes) { editingTime = .cook }
            }
            .font(ALITypography.bodyLarge)
            .foregroundStyle(ALIColors.ink)
        }
    }

    private func timeRow(_ title: LocalizedStringKey, systemImage: String, minutes: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(minutes == 0 ? String(localized: "Not set") : RecipeFormatting.duration(minutes))
                    .foregroundStyle(minutes == 0 ? ALIColors.mutedInk : ALIColors.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ALIColors.surfaceVariant)
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ingredientsCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ingredients")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                ForEach($ingredients) { $ingredient in
                    ingredientRow($ingredient)
                }

                HStack(spacing: 8) {
                    addRowButton("Add ingredient", systemImage: "plus") {
                        addIngredient(after: ingredients.last?.id)
                    }
                    addRowButton("From shopping list", systemImage: "cart.fill") {
                        Track.event("recipe_ingredients_from_shopping_tap")
                        showGroceryPicker = true
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    /// Name, amount and unit of one ingredient, plus its delete button.
    private func ingredientRow(_ ingredient: Binding<IngredientDraft>) -> some View {
        let id = ingredient.wrappedValue.id
        let unit = ingredient.wrappedValue.unit
        return HStack(spacing: 8) {
            TextField("Ingredient", text: ingredient.name)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.ink)
                .focused($focusedRow, equals: id)
                .submitLabel(.next)
                .onSubmit { focusedQuantity = unit.needsQuantity ? id : nil }
                .frame(maxWidth: .infinity, alignment: .leading)

            if unit.needsQuantity {
                TextField("0", text: ingredient.quantityText)
                    .font(ALITypography.bodyLarge.weight(.semibold))
                    .foregroundStyle(ALIColors.ink)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.center)
                    .focused($focusedQuantity, equals: id)
                    .frame(width: 64, height: 36)
                    .background(ALIColors.surfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Menu {
                Picker("Unit", selection: ingredient.unit) {
                    ForEach(IngredientUnit.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(unit.symbol)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.ink)
                .padding(.horizontal, 10)
                .frame(minWidth: 52, minHeight: 36)
                .background(ALIColors.recipesAccent.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                ingredients.removeAll { $0.id == id }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 40)
    }

    private func addRowButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ALIColors.surfaceVariant)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var stepsCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text("How to make it")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(index: index, id: step.id)
                }

                addRowButton("Add step", systemImage: "plus") {
                    addStep(after: steps.last?.id)
                }
                .padding(.top, 4)
            }
        }
    }

    /// One numbered step: a growing field where Return starts the next step
    /// (pasted multi-line text is split into several steps). The "…" menu
    /// menu reorders or deletes it.
    private func stepRow(index: Int, id: UUID) -> some View {
        let text = Binding<String>(
            get: { steps.first { $0.id == id }?.text ?? "" },
            set: { newValue in updateStep(id: id, with: newValue) }
        )
        return HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 26, height: 26)
                .background(ALIColors.recipesAccent)
                .clipShape(Circle())
                .padding(.top, 2)

            TextField("Describe this step", text: text, axis: .vertical)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1...8)
                .focused($focusedRow, equals: id)
                .padding(.top, 4)

            if steps.count > 1 {
                Menu {
                    if index > 0 {
                        Button { moveStep(from: index, to: index - 1) } label: {
                            Label("Move up", systemImage: "arrow.up")
                        }
                    }
                    if index < steps.count - 1 {
                        Button { moveStep(from: index, to: index + 1) } label: {
                            Label("Move down", systemImage: "arrow.down")
                        }
                    }
                    Button(role: .destructive) {
                        steps.removeAll { $0.id == id }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: Actions

    private func addIngredient(after id: UUID?) {
        let draft = IngredientDraft()
        if let id, let index = ingredients.firstIndex(where: { $0.id == id }) {
            ingredients.insert(draft, at: index + 1)
        } else {
            ingredients.append(draft)
        }
        focusedRow = draft.id
    }

    private func addStep(after id: UUID?, text: String = "") {
        let draft = TextDraft(text: text)
        if let id, let index = steps.firstIndex(where: { $0.id == id }) {
            steps.insert(draft, at: index + 1)
        } else {
            steps.append(draft)
        }
        focusedRow = draft.id
    }

    /// Typing Return (or pasting several lines) splits the text: the first
    /// line stays in this step, each following line becomes a new step.
    private func updateStep(id: UUID, with newValue: String) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        guard newValue.contains(where: \.isNewline) else {
            steps[index].text = newValue
            return
        }
        let splitKey = "\(id)|\(newValue)"
        guard lastStepSplit != splitKey else { return }
        lastStepSplit = splitKey
        DispatchQueue.main.async { lastStepSplit = nil }
        let lines = newValue.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        steps[index].text = lines[0]
        var lastID = id
        for line in lines.dropFirst() {
            let draft = TextDraft(text: line.trimmed)
            let insertAt = (steps.firstIndex { $0.id == lastID } ?? index) + 1
            steps.insert(draft, at: insertAt)
            lastID = draft.id
        }
        focusedRow = lastID
    }

    private func moveStep(from source: Int, to destination: Int) {
        withAnimation {
            let step = steps.remove(at: source)
            steps.insert(step, at: destination)
        }
    }

    /// Adds the picked catalog items as ingredients, filling the empty row first.
    private func addIngredients(_ names: [String]) {
        let existing = Set(ingredients.map { $0.name.trimmed.lowercased() })
        let fresh = names.filter { !existing.contains($0.lowercased()) }
        guard !fresh.isEmpty else { return }
        ingredients.removeAll { $0.name.trimmed.isEmpty }
        ingredients.append(contentsOf: fresh.map { IngredientDraft(name: $0) })
    }

    private func loadIfEditing() {
        guard let recipe = recipeToEdit else { return }
        name = recipe.name
        categories = Set(recipe.recipeCategories)
        servings = recipe.servings
        prepMinutes = recipe.prepMinutes ?? 0
        cookMinutes = recipe.cookMinutes ?? 0
        ingredients = recipe.ingredients.map { IngredientDraft($0) }
        let savedSteps = recipe.steps
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
        steps = savedSteps.isEmpty ? [TextDraft()] : savedSteps.map { TextDraft(text: $0) }
        existingPhoto = recipe.image
    }

    private func save() {
        let cleanIngredients = ingredients.map(\.ingredient).filter { !$0.name.isEmpty }
        let cleanSteps = steps.map(\.text.trimmed).filter { !$0.isEmpty }.joined(separator: "\n")
        let familyID = familySession.familyID
        let recipe: Recipe

        if let existing = recipeToEdit {
            existing.name = name.trimmed
            existing.categories = categoryValues
            existing.servings = servings
            existing.prepMinutes = prepMinutes == 0 ? nil : prepMinutes
            existing.cookMinutes = cookMinutes == 0 ? nil : cookMinutes
            existing.ingredients = cleanIngredients
            existing.steps = cleanSteps
            existing.updatedAt = .now
            recipe = existing
        } else {
            let memberID = familySession.memberID
            recipe = Recipe(
                name: name.trimmed,
                categories: categoryValues,
                ingredients: cleanIngredients,
                steps: cleanSteps,
                servings: servings,
                prepMinutes: prepMinutes == 0 ? nil : prepMinutes,
                cookMinutes: cookMinutes == 0 ? nil : cookMinutes,
                createdByID: memberID,
                createdByName: memberID.flatMap { modelContext.familyMemberName(id: $0) }
            )
            modelContext.insert(recipe)
        }

        if let familyID {
            dataSync.pushRecipe(recipe, familyID: familyID, newPhoto: newPhotoData, removePhoto: removePhoto && newPhotoData == nil)
            dataSync.logActivity(
                entityType: "recipe", entityName: recipe.name, action: isEditing ? "updated" : "created",
                actorID: familySession.memberID,
                actorName: familySession.memberID.flatMap { modelContext.familyMemberName(id: $0) },
                familyID: familyID, modelContext: modelContext
            )
        } else {
            if let newPhotoData { recipe.photoData = newPhotoData }
            if removePhoto && newPhotoData == nil { recipe.photoData = nil }
        }
        RecipeDishLink.sync(recipe, modelContext: modelContext, dataSync: dataSync, familyID: familyID)
        Track.event("recipe_saved", [
            "is_new": !isEditing,
            "categories": categoryValues.joined(separator: ","),
            "ingredients": cleanIngredients.count,
            "has_photo": previewImage != nil
        ])
        dismiss()
    }
}
