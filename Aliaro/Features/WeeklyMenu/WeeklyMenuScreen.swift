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

    /// Permission `weeklyMenuClear` (on top of editing): "Clear this week".
    private var canClearWeek: Bool {
        members.first(where: \.isCurrentDevice)?.can(.weeklyMenuClear) ?? true
    }

    private var canEditMenu: Bool {
        members.first(where: \.isCurrentDevice)?.can(.weeklyMenuEdit) ?? true
    }

    private var isPlanningLocked: Bool { premium.isLocked(.menuPlanning) }
    /// Month view open as a premium preview (sample data + blur + floating banner).
    private var isMonthPreview: Bool { viewMode == .month && isPlanningLocked }

    private var weekDays: [Date] { MenuCalendar.days(ofWeek: weekStart) }

    private var weekEntries: [MealPlanEntry] {
        let end = MenuCalendar.adding(days: 7, to: weekStart)
        return entries.filter { $0.date >= weekStart && $0.date < end }
    }

    private func dishes(for date: Date, mealType: MealType) -> [DishSelection] {
        MenuWriter.dishes(on: date, mealType: mealType, in: entries)
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
                    // In the premium preview the month header is part of the
                    // blurred, inert sample too (no moving between months).
                    VStack(spacing: 16) {
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
                    .aliPremiumPreview(isMonthPreview)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        // The premium preview is a fixed screen: no scrolling under the banner.
        .scrollDisabled(isMonthPreview)
        .overlay(alignment: .bottom) {
            if isMonthPreview {
                // Floats just above the bottom bar (same placement as Tasks).
                ALIPremiumPreviewBanner(
                    message: .menuMonth,
                    buttonTitle: "Unlock monthly menu"
                ) { showPaywall = Track.paywall("menu_month_banner") }
                .padding(.horizontal, 16)
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(ALIColors.background)
        .sheet(item: $dayBeingEdited) { day in
            EditDayMealsSheet(
                date: day.date,
                lunchDishes: dishes(for: day.date, mealType: .lunch),
                dinnerDishes: dishes(for: day.date, mealType: .dinner),
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
        .accessibilityLabel("menu_dishes_title")
    }

    private var viewModeToggleButton: some View {
        Button {
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
            Track.event("menu_view_mode", ["mode": viewMode == .week ? "week" : "month", "locked": isPlanningLocked])
        } label: {
            Image(systemName: viewMode == .week ? "calendar" : "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
                .aliPremiumPreviewOverlay(viewMode == .week && isPlanningLocked)
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

            if canClearWeek {
                Divider()

                Button(role: .destructive) {
                    Track.event("menu_clear_tap", ["planned_meals": weekEntries.count])
                    showClearConfirm = true
                } label: {
                    Label("Clear this week", systemImage: "trash")
                }
                .disabled(weekEntries.isEmpty)
            }
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

            // Like the family calendar: tapping the title goes back to the current
            // period; "Go to today" shows under it when you're elsewhere.
            Button { if !isCurrent { onToday() } } label: {
                VStack(spacing: 2) {
                    Text(title)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let subtitle, subtitle != title {
                        Text(subtitle)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .lineLimit(1)
                    }
                    if !isCurrent {
                        Text("Go to today")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            arrowButton("chevron.right", label: "Next", action: onNext)
        }
    }

    private func arrowButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
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
        // One card per day: the gaps between cards separate the days, no lines needed.
        VStack(spacing: 10) {
            ForEach(weekDays, id: \.self) { date in
                Button {
                    Track.event("menu_day_open", [
                        "is_today": MenuCalendar.isSameDay(date, .now),
                        "is_past": date < MenuCalendar.today,
                        "can_edit": canEditMenu
                    ])
                    dayBeingEdited = MenuDay(date: date)
                } label: {
                    dayCard(date)
                }
                .buttonStyle(.plain)
            }
        }
        .id(weekStart)
        .transition(.opacity)
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(onPrevious: { moveWeek(-1) }, onNext: { moveWeek(1) }))
    }

    /// A day of the week as its own card (split in small pieces so the
    /// compiler type-checks it quickly).
    private func dayCard(_ date: Date) -> some View {
        let lunch = dishes(for: date, mealType: .lunch)
        let dinner = dishes(for: date, mealType: .dinner)
        let past: Bool = date < MenuCalendar.today
        let isToday: Bool = MenuCalendar.isSameDay(date, .now)
        let planned: Bool = !lunch.isEmpty || !dinner.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            dayCardHeader(date, isToday: isToday, showsDone: past && planned)
            VStack(alignment: .leading, spacing: 14) {
                mealLines(label: "Lunch", icon: "sun.max.fill", dishes: lunch, accent: ALIColors.mealLunchAccent)
                mealLines(label: "Dinner", icon: "moon.fill", dishes: dinner, accent: ALIColors.mealDinnerAccent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dayCardBackground(isToday: isToday))
        .overlay(dayCardBorder(isToday: isToday))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(past ? 0.55 : 1)
    }

    private func dayCardHeader(_ date: Date, isToday: Bool, showsDone: Bool) -> some View {
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

            if showsDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ALIColors.success)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
        }
    }

    /// Card fill: surface, with a coral tint on today.
    private func dayCardBackground(isToday: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let tint: Color = isToday ? ALIColors.primary.opacity(0.14) : Color.clear
        return ZStack {
            shape.fill(ALIColors.surface)
            shape.fill(tint)
        }
    }

    /// Card border: outline, coral and a bit thicker on today.
    private func dayCardBorder(isToday: Bool) -> some View {
        let color: Color = isToday ? ALIColors.primary : ALIColors.outline
        let width: CGFloat = isToday ? 1.5 : 1
        return RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(color, lineWidth: width)
    }

    private static let mealIconSize: CGFloat = 28
    private static let mealIconGap: CGFloat = 12

    /// A meal's dishes, one per line, next to the meal's icon (sun = lunch, moon = dinner).
    private func mealLines(label: LocalizedStringKey, icon: String, dishes: [DishSelection], accent: Color) -> some View {
        let planned: Bool = !dishes.isEmpty
        let iconColor: Color = ALIColors.onAccent.opacity(planned ? 1 : 0.5)
        let circleColor: Color = accent.opacity(planned ? 0.7 : 0.3)
        return HStack(alignment: .top, spacing: Self.mealIconGap) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: Self.mealIconSize, height: Self.mealIconSize)
                .background(Circle().fill(circleColor))
                .accessibilityLabel(Text(label))

            VStack(alignment: .leading, spacing: 6) {
                if dishes.isEmpty {
                    mealLine(dish: nil)
                } else {
                    ForEach(Array(dishes.enumerated()), id: \.offset) { _, dish in
                        mealLine(dish: dish)
                    }
                }
            }
            .frame(minHeight: Self.mealIconSize)
        }
    }

    private func mealLine(dish: DishSelection?) -> some View {
        let name: String = dish?.name ?? String(localized: "Not planned")
        let font: Font = dish == nil ? ALITypography.bodyMedium : ALITypography.bodyLarge
        let color: Color = dish == nil ? ALIColors.mutedInk.opacity(0.7) : ALIColors.ink
        return HStack(spacing: 8) {
            Text(name)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if let dish, let recipe = recipes.first(where: { $0.id == dish.id }) {
                Button {
                    Track.event("menu_recipe_open", ["from": "menu_list"])
                    openedRecipe = recipe
                } label: {
                    // Compact "cook" button: just the recipe icon in a small circle.
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ALIColors.onAccent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(ALIColors.recipesAccent))
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
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let symbols: [String] = MenuCalendar.weekdaySymbols
        let cells: [Date?] = monthCells
        return ALICard {
            VStack(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(symbols.indices, id: \.self) { index in
                        weekdayHeader(symbols[index])
                    }
                    ForEach(cells.indices, id: \.self) { index in
                        monthGridItem(cells[index])
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

    private func weekdayHeader(_ symbol: String) -> some View {
        Text(symbol.uppercased())
            .font(ALITypography.labelLarge)
            .foregroundStyle(ALIColors.mutedInk)
    }

    /// A grid slot of the month: the day, or a blank before the 1st.
    @ViewBuilder
    private func monthGridItem(_ date: Date?) -> some View {
        if let date {
            monthCell(date)
        } else {
            Color.clear.frame(height: 52)
        }
    }

    private func monthCell(_ date: Date) -> some View {
        // Sample month in the premium preview; real dishes otherwise.
        let hasLunch: Bool
        let hasDinner: Bool
        if isMonthPreview {
            let sample = MenuDemoData.planned(on: date)
            hasLunch = sample.lunch
            hasDinner = sample.dinner
        } else {
            hasLunch = !dishes(for: date, mealType: .lunch).isEmpty
            hasDinner = !dishes(for: date, mealType: .dinner).isEmpty
        }
        let isToday: Bool = MenuCalendar.isSameDay(date, .now)
        let past: Bool = date < MenuCalendar.today
        let empty: Color = ALIColors.outline.opacity(0.5)
        let lunchColor: Color = hasLunch ? ALIColors.mealLunchAccent : empty
        let dinnerColor: Color = hasDinner ? ALIColors.mealDinnerAccent : empty
        let numberFont: Font = ALITypography.bodyLarge.weight(isToday ? .bold : .regular)
        let numberColor: Color = isToday ? ALIColors.onAccent : ALIColors.ink
        let numberBackground: Color = isToday ? ALIColors.primary : Color.clear
        let cellOpacity: Double = past ? 0.5 : 1

        return Button {
            Track.event("menu_day_open", ["from": "month", "is_today": isToday, "can_edit": canEditMenu])
            dayBeingEdited = MenuDay(date: date)
        } label: {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.day()))
                    .font(numberFont)
                    .foregroundStyle(numberColor)
                    .frame(width: 30, height: 30)
                    .background(numberBackground)
                    .clipShape(Circle())
                HStack(spacing: 3) {
                    Circle().fill(lunchColor).frame(width: 6, height: 6)
                    Circle().fill(dinnerColor).frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
            .opacity(cellOpacity)
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
        // Each planned meal of the week (all its dishes, in order) replaces
        // the same meal in the target week.
        let slots = Set(source.map { SlotKey(date: MenuCalendar.day($0.date), mealType: $0.mealType) })
        for weeks in weeksAhead {
            for slot in slots {
                guard let mealType = MealType(rawValue: slot.mealType) else { continue }
                MenuWriter.set(
                    MenuWriter.dishes(on: slot.date, mealType: mealType, in: source),
                    date: MenuCalendar.adding(days: 7 * weeks, to: slot.date),
                    mealType: mealType,
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

/// A day + meal of the menu (one or more dishes).
private struct SlotKey: Hashable {
    let date: Date
    let mealType: String
}

/// Sample month for the `menuPlanning` premium preview: a believable,
/// mostly-planned month (stable per day so it doesn't flicker).
enum MenuDemoData {
    static func planned(on date: Date) -> (lunch: Bool, dinner: Bool) {
        let day = MenuCalendar.calendar.component(.day, from: date)
        return (lunch: day % 7 != 3, dinner: day % 5 != 2 && day % 11 != 0)
    }
}
