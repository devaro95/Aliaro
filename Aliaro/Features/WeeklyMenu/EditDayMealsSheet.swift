import SwiftUI
import SwiftData

/// Sheet to edit lunch and dinner for a calendar day of the menu, choosing
/// a dish from the catalog for each slot. If saved without a dish, that
/// day/type's entry is deleted instead of being left empty.
struct EditDayMealsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let date: Date
    var canEdit: Bool = true

    @State private var lunchDish: DishSelection?
    @State private var dinnerDish: DishSelection?
    @State private var mealTypeBeingPicked: MealType?
    @State private var openedRecipe: Recipe?

    @Query private var recipes: [Recipe]
    @Query private var entries: [MealPlanEntry]

    private func recipe(for selection: DishSelection?) -> Recipe? {
        guard let selection else { return nil }
        return recipes.first { $0.id == selection.id }
    }

    init(date: Date, lunchDish: DishSelection?, dinnerDish: DishSelection?, canEdit: Bool = true) {
        self.date = MenuCalendar.day(date)
        self.canEdit = canEdit
        _lunchDish = State(initialValue: lunchDish)
        _dinnerDish = State(initialValue: dinnerDish)
    }

    var body: some View {
        trackedBody.trackScreen("menu_day_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !canEdit {
                    ALICard(containerColor: ALIColors.surfaceVariant) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(ALIColors.mutedInk)
                            Text("You don't have permission to edit the weekly menu")
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.mutedInk)
                        }
                    }
                }

                mealPicker(label: "Lunch", selection: $lunchDish) {
                    Track.event("menu_meal_pick_tap", ["meal": "lunch"])
                    mealTypeBeingPicked = .lunch
                }
                mealPicker(label: "Dinner", selection: $dinnerDish) {
                    Track.event("menu_meal_pick_tap", ["meal": "dinner"])
                    mealTypeBeingPicked = .dinner
                }

                Spacer()

                if canEdit {
                    ALIPrimaryButton(text: "Save", accent: ALIColors.weeklyMenuAccent) {
                        save()
                    }
                }
            }
            .padding(20)
            .background(ALIColors.background)
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Track.event("menu_day_cancel")
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .sheet(item: $openedRecipe) { recipe in
            RecipeDetailSheet(recipe: recipe)
        }
        .sheet(item: $mealTypeBeingPicked) { mealType in
            SelectDishSheet(mealType: mealType) { picked in
                switch mealType {
                case .lunch: lunchDish = picked
                case .dinner: dinnerDish = picked
                }
            }
        }
    }

    @ViewBuilder
    private func mealPicker(label: LocalizedStringKey, selection: Binding<DishSelection?>, onTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)

            HStack(spacing: 8) {
                Button(action: onTap) {
                    HStack {
                        Text(selection.wrappedValue?.name ?? String(localized: "Choose dish"))
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(selection.wrappedValue == nil ? ALIColors.mutedInk.opacity(0.7) : ALIColors.ink)
                            .lineLimit(1)
                        Spacer()
                        if canEdit {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(ALIColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ALIColors.outline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)

                if let recipe = recipe(for: selection.wrappedValue) {
                    Button {
                        Track.event("menu_recipe_open")
                        openedRecipe = recipe
                    } label: {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ALIColors.onAccent)
                            .frame(width: 36, height: 36)
                            .background(ALIColors.recipesAccent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("View recipe"))
                }

                if selection.wrappedValue != nil && canEdit {
                    Button {
                        Track.event("menu_meal_clear_tap")
                        selection.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func save() {
        upsert(mealType: .lunch, dish: lunchDish)
        upsert(mealType: .dinner, dish: dinnerDish)
        dismiss()
    }

    private func upsert(mealType: MealType, dish: DishSelection?) {
        let existing = entries.first { MenuCalendar.isSameDay($0.date, date) && $0.mealType == mealType.rawValue }
        // Analytics: only real changes (saving an untouched meal logs nothing).
        let changed = (dish?.id != existing?.dishID) || (dish == nil) != (existing == nil)
        if changed {
            let eventName = dish == nil ? "menu_meal_removed" : (existing == nil ? "menu_meal_planned" : "menu_meal_changed")
            Track.event(eventName, [
                "days_ahead": MenuCalendar.calendar.dateComponents([.day], from: MenuCalendar.today, to: date).day ?? 0,
                "meal": String(describing: mealType),
                "dish_name": dish?.name
            ])
        }
        MenuWriter.set(
            dish,
            date: date,
            mealType: mealType,
            entries: entries,
            modelContext: modelContext,
            dataSync: dataSync,
            familyID: familySession.familyID
        )
    }
}
