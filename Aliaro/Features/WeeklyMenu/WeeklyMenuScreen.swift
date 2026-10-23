import SwiftUI
import SwiftData

/// "Menu" tab: lunch and dinner planned on real calendar days. Week view
/// (free) moves between past and future weeks; month view and copying a
/// week forward are `menuPlanning` premium. Meals that are a recipe get a
/// "Cook" button that opens the recipe straight away.
struct WeeklyMenuScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query private var entries: [MealPlanEntry]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @Query private var recipes: [Recipe]

    private enum ViewMode { case week, month }

    @State private var viewMode: ViewMode = .week
    @State private var weekStart: Date = MenuCalendar.startOfWeek(.now)
    @State private var monthStart: Date = MenuCalendar.startOfMonth(.now)
    @State private var dayBeingEdited: MenuDay?
    @State private var showClearConfirm = false
    @State private var showDishes = false
    @State private var showPaywall = false
    @State private var openedRecipe: Recipe?
    @State private var copyMessage: String?

    private var canEditMenu: Bool {
        members.first(where: \.isCurrentDevice)?.can(.weeklyMenuEdit) ?? true
    }

    private var isPlanningLocked: Bool { premium.isLocked(.menuPlanning) }

    private var weekDays: [Date] { MenuCalendar.days(ofWeek: weekStart) }

    private var weekEntries: [MealPlanEntry] {
        let end = MenuCalendar.adding(days: 7, to: weekStart)
        return entries.filter { $0.date >= weekStart && $0.date < end }
    }

    private func dish(for date: Date, mealType: MealType) -> DishSelection? {
        guard let entry = entries.first(where: { MenuCalendar.isSameDay($0.date, date) && $0.mealType == mealType.rawValue }) else {
            return nil
        }
        return DishSelection(id: entry.dishID, name: entry.dishName)
    }

    var body: some View {
        trackedBody.trackScreen("weekly_menu")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "Menu", accent: ALIColors.weeklyMenuAccent) {
                    HStack(spacing: 10) {
                        if canEditMenu { dishesButton }
                        viewModeToggleButton
                        if canEditMenu && viewMode == .week { weekActionsMenu }
                    }
                }

                switch viewMode {
                case .week:
                    periodHeader(
                        title: weekTitle,
                        subtitle: weekRangeLabel,
                        isCurrent: MenuCalendar.isSameDay(weekStart, MenuCalendar.startOfWeek(.now)),
                        onPrevious: { moveWeek(-1) },
                        onNext: { moveWeek(1) },
                        onToday: { goToToday() }
                    )
                    weekCard
                case .month:
                    periodHeader(
                        title: monthStart.formatted(.dateTime.month(.wide).year()).capitalized,
                        subtitle: nil,
                        isCurrent: MenuCalendar.isSameDay(monthStart, MenuCalendar.startOfMonth(.now)),
                        onPrevious: { moveMonth(-1) },
                        onNext: { moveMonth(1) },
                        onToday: { goToToday() }
                    )
                    monthCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .sheet(item: $dayBeingEdited) { day in
            EditDayMealsSheet(
                date: day.date,
                lunchDish: dish(for: day.date, mealType: .lunch),
                dinnerDish: dish(for: day.date, mealType: .dinner),
                canEdit: canEditMenu
            )
        }
        .sheet(item: $openedRecipe) { recipe in
            RecipeDetailSheet(recipe: recipe)
        }
        .sheet(isPresented: $showDishes) {
            SelectDishSheet(mealType: nil, onSelect: nil)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("Clear this week?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearWeek() }
        } message: {
            Text("All planned lunches and dinners for this week will be deleted. This action can't be undone.")
        }
        .alert(copyMessage ?? "", isPresented: Binding(get: { copyMessage != nil }, set: { if !$0 { copyMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Top bar

    private var dishesButton: some View {
        Button {
            Track.event("menu_dishes_open")
            showDishes = true
        } label: {
            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dishes")
    }

    private var viewModeToggleButton: some View {
        Button {
            if viewMode == .week && isPlanningLocked {
                showPaywall = Track.paywall("menu_month_view")
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                if viewMode == .week {
                    monthStart = MenuCalendar.startOfMonth(weekStart)
                    viewMode = .month
                } else {
                    weekStart = MenuCalendar.startOfWeek(
                        MenuCalendar.isSameDay(monthStart, MenuCalendar.startOfMonth(.now)) ? .now : monthStart
                    )
                    viewMode = .week
                }
            }
            Track.event("menu_view_mode", ["mode": viewMode == .week ? "week" : "month"])
        } label: {
            Image(systemName: viewMode == .week ? "calendar" : "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
                .aliPremiumLockOverlay(viewMode == .week && isPlanningLocked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewMode == .week ? "View month" : "View week")
    }

    private var weekActionsMenu: some View {
        Menu {
            Button {
                copyWeek(weeksAhead: [1])
            } label: {
                Label("Copy to next week", systemImage: "doc.on.doc")
            }
            .disabled(weekEntries.isEmpty)

            Button {
                copyWeek(weeksAhead: weeksUntilEndOfMonth)
            } label: {
                Label("Repeat until end of month", systemImage: "calendar.badge.plus")
            }
            .disabled(weekEntries.isEmpty || weeksUntilEndOfMonth.isEmpty)

            Divider()

            Button(role: .destructive) {
                Track.event("menu_clear_tap", ["planned_meals": weekEntries.count])
                showClearConfirm = true
            } label: {
                Label("Clear this week", systemImage: "trash")
            }
            .disabled(weekEntries.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
        }
        .accessibilityLabel("More options")
    }

    // MARK: Period header

    private var weekTitle: String {
        let current = MenuCalendar.startOfWeek(.now)
        let diff = (MenuCalendar.calendar.dateComponents([.day], from: current, to: weekStart).day ?? 0) / 7
        switch diff {
        case 0: return String(localized: "This week")
        case 1: return String(localized: "Next week")
        case -1: return String(localized: "Last week")
        default: return weekRangeLabel
        }
    }

    private var weekRangeLabel: String {
        let end = MenuCalendar.adding(days: 6, to: weekStart)
        return "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    @ViewBuilder
    private func periodHeader(
        title: String,
        subtitle: String?,
        isCurrent: Bool,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onToday: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            arrowButton("chevron.left", label: "Previous", action: onPrevious)

            VStack(spacing: 2) {
                Text(title)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                if let subtitle, subtitle != title {
                    Text(subtitle)
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if !isCurrent {
                    Button(action: onToday) {
                        Text("Today")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(ALIColors.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ALIColors.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            arrowButton("chevron.right", label: "Next", action: onNext)
        }
    }

    private func arrowButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 36, height: 36)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Horizontal swipe on the week/month card moves to the previous/next period.
    private func swipe(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) * 1.5, abs(dx) > 60 else { return }
                if dx < 0 { onNext() } else { onPrevious() }
            }
    }

    private func moveWeek(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            weekStart = MenuCalendar.adding(days: 7 * delta, to: weekStart)
        }
        Track.event("menu_week_change", ["direction": delta > 0 ? "next" : "previous"])
    }

    private func moveMonth(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            monthStart = MenuCalendar.adding(months: delta, to: monthStart)
        }
        Track.event("menu_month_change", ["direction": delta > 0 ? "next" : "previous"])
    }

    private func goToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            weekStart = MenuCalendar.startOfWeek(.now)
            monthStart = MenuCalendar.startOfMonth(.now)
        }
    }

    // MARK: Week view

    private var weekCard: some View {
        ALICard(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            VStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.element) { index, date in
                    Button {
                        Track.event("menu_day_open", [
                            "is_today": MenuCalendar.isSameDay(date, .now),
                            "is_past": date < MenuCalendar.today,
                            "can_edit": canEditMenu
                        ])
                        dayBeingEdited = MenuDay(date: date)
                    } label: {
                        dayRow(date)
                    }
                    .buttonStyle(.plain)

                    if index < weekDays.count - 1 {
                        Divider().overlay(ALIColors.outline).padding(.leading, 20)
                    }
                }
            }
        }
        .id(weekStart)
        .transition(.opacity)
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(onPrevious: { moveWeek(-1) }, onNext: { moveWeek(1) }))
    }

    @ViewBuilder
    private func dayRow(_ date: Date) -> some View {
        let lunch = dish(for: date, mealType: .lunch)
        let dinner = dish(for: date, mealType: .dinner)
        let past = date < MenuCalendar.today
        let isToday = MenuCalendar.isSameDay(date, .now)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(date.formatted(.dateTime.weekday(.wide)).capitalized)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)

                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)

                if isToday {
                    Text("Today")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(ALIColors.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ALIColors.primary)
                        .clipShape(Capsule())
                }

                if past && (lunch != nil || dinner != nil) {
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
        .background(isToday ? ALIColors.primary.opacity(0.14) : Color.clear)
        .overlay(alignment: .leading) {
            if isToday {
                Rectangle()
                    .fill(ALIColors.primary)
                    .frame(width: 4)
            }
        }
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

            if let dish, let recipe = recipes.first(where: { $0.id == dish.id }) {
                Button {
                    Track.event("menu_recipe_open", ["from": "menu_list"])
                    openedRecipe = recipe
                } label: {
                    Label("Cook", systemImage: "book.pages.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(ALIColors.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ALIColors.recipesAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("View recipe"))
            }
        }
    }

    // MARK: Month view

    /// Grid cells for the visible month: leading blanks up to Monday, then each day.
    private var monthCells: [Date?] {
        let firstWeekStart = MenuCalendar.startOfWeek(monthStart)
        let leading = MenuCalendar.calendar.dateComponents([.day], from: firstWeekStart, to: monthStart).day ?? 0
        let count = MenuCalendar.calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let days = (0..<count).map { Optional(MenuCalendar.adding(days: $0, to: monthStart)) }
        return Array(repeating: nil, count: leading) + days
    }

    private var monthCard: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return ALICard {
            VStack(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(MenuCalendar.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol.uppercased())
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                    ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                        if let date {
                            monthCell(date)
                        } else {
                            Color.clear.frame(height: 52)
                        }
                    }
                }

                HStack(spacing: 14) {
                    legendDot(color: ALIColors.mealLunchAccent, label: "Lunch")
                    legendDot(color: ALIColors.mealDinnerAccent, label: "Dinner")
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .id(monthStart)
        .transition(.opacity)
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(onPrevious: { moveMonth(-1) }, onNext: { moveMonth(1) }))
    }

    private func monthCell(_ date: Date) -> some View {
        let hasLunch = dish(for: date, mealType: .lunch) != nil
        let hasDinner = dish(for: date, mealType: .dinner) != nil
        let isToday = MenuCalendar.isSameDay(date, .now)
        let past = date < MenuCalendar.today

        return Button {
            Track.event("menu_day_open", ["from": "month", "is_today": isToday, "can_edit": canEditMenu])
            dayBeingEdited = MenuDay(date: date)
        } label: {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.day()))
                    .font(ALITypography.bodyLarge.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? ALIColors.onAccent : ALIColors.ink)
                    .frame(width: 30, height: 30)
                    .background(isToday ? ALIColors.primary : Color.clear)
                    .clipShape(Circle())
                HStack(spacing: 3) {
                    Circle()
                        .fill(hasLunch ? ALIColors.mealLunchAccent : ALIColors.outline.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(hasDinner ? ALIColors.mealDinnerAccent : ALIColors.outline.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
            .opacity(past ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    private func legendDot(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
        }
    }

    // MARK: Actions

    /// Offsets (in weeks) of the following weeks that start in the same
    /// month as the visible week ends.
    private var weeksUntilEndOfMonth: [Int] {
        let lastDay = MenuCalendar.adding(days: 6, to: weekStart)
        let monthEnd = MenuCalendar.adding(months: 1, to: MenuCalendar.startOfMonth(lastDay))
        var offsets: [Int] = []
        var offset = 1
        while MenuCalendar.adding(days: 7 * offset, to: weekStart) < monthEnd {
            offsets.append(offset)
            offset += 1
        }
        return offsets
    }

    private func copyWeek(weeksAhead: [Int]) {
        guard !weeksAhead.isEmpty else { return }
        if isPlanningLocked {
            showPaywall = Track.paywall("menu_copy_week")
            return
        }
        let source = weekEntries
        let familyID = familySession.familyID
        for weeks in weeksAhead {
            for entry in source {
                MenuWriter.set(
                    DishSelection(id: entry.dishID, name: entry.dishName),
                    date: MenuCalendar.adding(days: 7 * weeks, to: entry.date),
                    mealType: MealType(rawValue: entry.mealType) ?? .lunch,
                    entries: entries,
                    modelContext: modelContext,
                    dataSync: dataSync,
                    familyID: familyID
                )
            }
        }
        Track.event("menu_week_copied", ["weeks": weeksAhead.count, "planned_meals": source.count])
        copyMessage = weeksAhead.count == 1
            ? String(localized: "Menu copied to next week")
            : String(localized: "Menu repeated for \(weeksAhead.count) weeks")
    }

    private func clearWeek() {
        Track.event("menu_cleared", ["planned_meals": weekEntries.count])
        withAnimation {
            for entry in weekEntries {
                MenuWriter.remove(entry, modelContext: modelContext, dataSync: dataSync)
            }
        }
    }
}
