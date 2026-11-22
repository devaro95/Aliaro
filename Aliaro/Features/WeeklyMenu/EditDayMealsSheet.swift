import SwiftUI
import SwiftData

/// Sheet to edit lunch and dinner for a calendar day of the menu. Each meal
/// can have several dishes from the catalog ("Add another dish"); a meal
/// saved with none is left unplanned.
struct EditDayMealsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession

    let date: Date
    var canEdit: Bool = true

    @State private var lunchDishes: [DishSelection]
    @State private var dinnerDishes: [DishSelection]
    @State private var mealTypeBeingPicked: MealType?
    @State private var openedRecipe: Recipe?

    @Query private var recipes: [Recipe]
    @Query private var entries: [MealPlanEntry]

    private func recipe(for selection: DishSelection) -> Recipe? {
        recipes.first { $0.id == selection.id }
    }

    init(date: Date, lunchDishes: [DishSelection], dinnerDishes: [DishSelection], canEdit: Bool = true) {
        self.date = MenuCalendar.day(date)
        self.canEdit = canEdit
        _lunchDishes = State(initialValue: lunchDishes)
        _dinnerDishes = State(initialValue: dinnerDishes)
    }

    var body: some View {
        trackedBody.trackScreen("menu_day_editor")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        dayHeader
                            .padding(.top, 12)

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

                        mealSection(label: "Lunch", icon: "sun.max.fill", accent: ALIColors.mealLunchAccent, mealType: .lunch, dishes: $lunchDishes)
                        mealSection(label: "Dinner", icon: "moon.fill", accent: ALIColors.mealDinnerAccent, mealType: .dinner, dishes: $dinnerDishes)
                    }
                    .padding(20)
                }

                if canEdit {
                    ALIPrimaryButton(text: "Save", accent: ALIColors.weeklyMenuAccent) {
                        save()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(ALIColors.background)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDragIndicator(.visible)
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $openedRecipe) { recipe in
            RecipeDetailSheet(recipe: recipe)
        }
        .sheet(item: $mealTypeBeingPicked) { mealType in
            SelectDishSheet(mealType: mealType) { picked in
                switch mealType {
                case .lunch: if !lunchDishes.contains(picked) { lunchDishes.append(picked) }
                case .dinner: if !dinnerDishes.contains(picked) { dinnerDishes.append(picked) }
                }
            }
        }
    }

    /// Header: a calendar leaf (month + day number) next to the weekday and
    /// where it falls (today / this week / next week…), so the date always fits.
    private var dayHeader: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.month(.abbreviated)).replacingOccurrences(of: ".", with: "").uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(ALIColors.onAccent)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(ALIColors.weeklyMenuAccent)
                Text("\(MenuCalendar.calendar.component(.day, from: date))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(ALIColors.ink)
                    .padding(.vertical, 3)
            }
            .frame(width: 48)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ALIColors.outline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(date.formatted(.dateTime.weekday(.wide)).capitalized)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Text(relativeWhen)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "Today", "This week", "Next week", "Last week" or, further away, month and year.
    private var relativeWhen: String {
        if MenuCalendar.isSameDay(date, .now) { return String(localized: "Today") }
        let current = MenuCalendar.startOfWeek(.now)
        let weeks = (MenuCalendar.calendar.dateComponents([.day], from: current, to: MenuCalendar.startOfWeek(date)).day ?? 0) / 7
        switch weeks {
        case 0: return String(localized: "This week")
        case 1: return String(localized: "Next week")
        case -1: return String(localized: "Last week")
        default: return date.formatted(.dateTime.month(.wide).year()).capitalized
        }
    }

    /// A meal: its title (sun/moon + name), its dishes (each with "view recipe"
    /// and remove) and a row to add one more ("Choose dish" while empty, "Add another dish" after).
    @ViewBuilder
    private func mealSection(label: LocalizedStringKey, icon: String, accent: Color, mealType: MealType, dishes: Binding<[DishSelection]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ALIColors.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(accent.opacity(0.7)))
                    .accessibilityHidden(true)
                Text(label)
                    .font(ALITypography.titleLarge.weight(.bold))
                    .foregroundStyle(ALIColors.ink)
            }
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(dishes.wrappedValue.enumerated()), id: \.offset) { index, dish in
                HStack(spacing: 8) {
                    Text(dish.name)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(ALIColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ALIColors.outline, lineWidth: 1)
                        )

                    if let recipe = recipe(for: dish) {
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

                    if canEdit {
                        Button {
                            Track.event("menu_meal_clear_tap")
                            dishes.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if canEdit {
                Button {
                    Track.event("menu_meal_pick_tap", ["meal": mealType == .lunch ? "lunch" : "dinner", "dishes": dishes.wrappedValue.count])
                    mealTypeBeingPicked = mealType
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(dishes.wrappedValue.isEmpty ? "Choose dish" : "Add another dish")
                            .font(ALITypography.bodyLarge)
                        Spacer()
                    }
                    .foregroundStyle(ALIColors.mutedInk)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(ALIColors.outline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if dishes.wrappedValue.isEmpty {
                Text("Not planned")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk.opacity(0.7))
            }
        }
    }

    private func save() {
        upsert(mealType: .lunch, dishes: lunchDishes)
        upsert(mealType: .dinner, dishes: dinnerDishes)
        dismiss()
    }

    private func upsert(mealType: MealType, dishes: [DishSelection]) {
        let existing = MenuWriter.dishes(on: date, mealType: mealType, in: entries)
        // Analytics: only real changes (saving an untouched meal logs nothing).
        if dishes != existing {
            let eventName = dishes.isEmpty ? "menu_meal_removed" : (existing.isEmpty ? "menu_meal_planned" : "menu_meal_changed")
            Track.event(eventName, [
                "days_ahead": MenuCalendar.calendar.dateComponents([.day], from: MenuCalendar.today, to: date).day ?? 0,
                "meal": String(describing: mealType),
                "dish_name": dishes.first?.name,
                "dishes": dishes.count
            ])
        }
        MenuWriter.set(
            dishes,
            date: date,
            mealType: mealType,
            entries: entries,
            modelContext: modelContext,
            dataSync: dataSync,
            familyID: familySession.familyID
        )
    }
}
