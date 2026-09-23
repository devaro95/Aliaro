import SwiftUI
import SwiftData

/// "Menu" tab: the weekly meal menu — a recurring Monday-to-Sunday
/// template with lunch and dinner, chosen from a dish catalog, so you
/// don't have to think each day about what to cook.
struct WeeklyMenuScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator

    @Query private var entries: [MealPlanEntry]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var dayBeingEdited: Weekday?
    @State private var showClearConfirm = false

    private var canEditMenu: Bool {
        members.first(where: \.isCurrentDevice)?.can(.weeklyMenuEdit) ?? true
    }

    private func dish(for weekday: Weekday, mealType: MealType) -> DishSelection? {
        guard let entry = entries.first(where: { $0.weekday == weekday.rawValue && $0.mealType == mealType.rawValue }) else {
            return nil
        }
        return DishSelection(id: entry.dishID, name: entry.dishName)
    }

    /// Current day of the week (Monday = 0 ... Sunday = 6), to mark
    /// already-past days of the current week as completed.
    private var todayWeekday: Weekday {
        let systemWeekday = Calendar.current.component(.weekday, from: Date()) // Sunday=1 ... Saturday=7
        let mondayBased = (systemWeekday + 5) % 7
        return Weekday(rawValue: mondayBased) ?? .monday
    }

    private func isPast(_ day: Weekday) -> Bool {
        day.rawValue < todayWeekday.rawValue
    }

    var body: some View {
        trackedBody.trackScreen("weekly_menu")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Weekly menu", accent: ALIColors.weeklyMenuAccent) {
                    if !entries.isEmpty && canEditMenu {
                        Button {
                            Track.event("menu_clear_tap", ["planned_meals": entries.count])
                            showClearConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ALIColors.mutedInk)
                                .frame(width: 34, height: 34)
                                .background(ALIColors.surfaceVariant)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                ALICard(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
                    VStack(spacing: 0) {
                        ForEach(Array(Weekday.allCases.enumerated()), id: \.element.id) { index, day in
                            Button {
                                Track.event("menu_day_open", [
                                    "weekday": String(describing: day),
                                    "is_today": day == todayWeekday,
                                    "is_past": isPast(day),
                                    "can_edit": canEditMenu
                                ])
                                dayBeingEdited = day
                            } label: {
                                dayRow(day)
                            }
                            .buttonStyle(.plain)

                            if index < Weekday.allCases.count - 1 {
                                Divider().overlay(ALIColors.outline).padding(.leading, 20)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .sheet(item: $dayBeingEdited) { day in
            EditDayMealsSheet(
                day: day,
                lunchDish: dish(for: day, mealType: .lunch),
                dinnerDish: dish(for: day, mealType: .dinner),
                canEdit: canEditMenu
            )
        }
        .alert("Clear the weekly menu?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearAll() }
        } message: {
            Text("All planned lunches and dinners for every day will be deleted. This action can't be undone.")
        }
    }

    private func clearAll() {
        Track.event("menu_cleared", ["planned_meals": entries.count])
        withAnimation {
            for entry in entries {
                let entryID = entry.id
                modelContext.delete(entry)
                dataSync.deleteMealPlanEntry(id: entryID)
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ day: Weekday) -> some View {
        let lunch = dish(for: day, mealType: .lunch)
        let dinner = dish(for: day, mealType: .dinner)
        let past = isPast(day)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(day.shortLabel)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)

                if past {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ALIColors.success)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 6) {
                mealLine(label: "Lunch", dish: lunch, accent: ALIColors.mealLunchAccent)
                mealLine(label: "Dinner", dish: dinner, accent: ALIColors.mealDinnerAccent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .opacity(past ? 0.55 : 1)
    }

    @ViewBuilder
    private func mealLine(label: LocalizedStringKey, dish: DishSelection?, accent: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 50)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(accent.opacity(dish == nil ? 0.22 : 0.55))
                .clipShape(Capsule())

            Text(dish?.name ?? String(localized: "Not planned"))
                .font(dish == nil ? ALITypography.bodyMedium : ALITypography.bodyLarge.weight(.semibold))
                .foregroundStyle(dish == nil ? ALIColors.mutedInk.opacity(0.7) : ALIColors.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
}
