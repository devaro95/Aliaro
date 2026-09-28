import SwiftUI
import SwiftData

/// "Home" tab — the hub of the app:
///
/// - Top bar with the current member's avatar, which opens People.
/// - A horizontally paged carousel of summary cards with what matters
///   today (tasks due, next event, today's menu, shopping, next reminder,
///   who owes whom). Only features with something to say get a card.
/// - The family Board: notes pinned by anyone, always shown here until
///   someone deletes them.
/// - A 2-column grid with a shortcut to **every** visible feature, so new
///   ones never need a bottom-bar slot.
///
/// The feature cards can be reordered (button next to "All features",
/// then drag by the grip like the Board's notes). The order is personal
/// (`FamilySession.homeFeatureOrder`, stored on this device), not a family
/// setting; the "Today" carousel follows it too.
///
/// Respects `FamilySession.disabledTabs` (hidden features appear nowhere)
/// and whole-feature premium locks (`AppTab.premiumFeature`): locked
/// cards show the crown and open the paywall instead of the screen.
struct HomeScreen: View {
    /// The bottom bar's favorites (tapping one switches tab instead of pushing).
    let favorites: [AppTab]
    /// Opens a feature (or `.people`), decided by `MainTabContainer`.
    let onOpen: (AppTab) -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @Query private var houseTasks: [HouseTask]
    @Query private var houseTaskLogs: [HouseTaskLog]
    @Query(sort: \FamilyEvent.startDate) private var events: [FamilyEvent]
    @Query private var mealPlan: [MealPlanEntry]
    @Query(sort: \ShoppingListEntry.addedAt) private var shoppingEntries: [ShoppingListEntry]
    @Query(sort: \Reminder.fireDate) private var reminders: [Reminder]
    @Query private var recipes: [Recipe]
    /// Same order as the Board (manual `position`, then newest first).
    @Query(sort: [SortDescriptor(\BoardNote.position), SortDescriptor(\BoardNote.createdAt, order: .reverse)])
    private var boardNotes: [BoardNote]
    /// Only a re-render trigger — see `expenses`.
    @Query private var allExpenses: [Expense]

    @State private var showPaywall = false
    /// Placeholder notes for the locked Board preview.
    @State private var sampleBoardNotes = BoardNote.samples()
    /// Virtual slot currently shown by the infinite carousel.
    @State private var carouselPosition: Int?

    // Reordering the feature cards (custom drag, same feel as the Board).
    /// Whether the grid is in reorder mode (grips shown, taps disabled).
    @State private var isReordering = false
    /// Card being dragged, if any.
    @State private var draggingTab: AppTab?
    /// Working order while dragging; saved on release.
    @State private var dragOrder: [AppTab] = []
    /// Grid slot frames captured when the drag starts (slots don't move,
    /// only which card sits in each).
    @State private var dragSlots: [CGRect] = []
    /// Slot the dragged card started in.
    @State private var dragStartIndex = 0
    /// Finger translation since the drag started.
    @State private var dragTranslation: CGSize = .zero
    /// Measured frame of each card in the grid's coordinate space.
    @State private var tileFrames: [AppTab: CGRect] = [:]

    /// Seconds each "Today" card stays before auto-advancing.
    private let carouselInterval: Duration = .seconds(5)
    /// Copies of the card list laid out so the carousel feels endless.
    private let carouselLoops = 100

    /// Same approach as `EconomiaScreen`: a fresh fetch so a burst of
    /// deletes (archiving) never hands us detached objects.
    private var expenses: [Expense] {
        _ = allExpenses.count
        return (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
    }

    private var currentMember: FamilyMember? { members.first(where: \.isCurrentDevice) }

    /// Visible features in this member's personal order.
    private var visibleFeatures: [AppTab] {
        AppTab.ordered(
            AppTab.visibleFeatures(excluding: familySession.disabledTabs),
            by: familySession.homeFeatureOrder
        )
    }

    /// Cards in the order shown: the working order while dragging.
    private var displayedFeatures: [AppTab] {
        draggingTab != nil ? dragOrder : visibleFeatures
    }

    private func isLocked(_ tab: AppTab) -> Bool {
        guard let feature = tab.premiumFeature else { return false }
        return premium.isLocked(feature)
    }

    var body: some View {
        trackedBody.trackScreen("home")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(alignment: .leading, spacing: 16) {
                ALITopBar(title: "Home", accent: AppTab.home.accent) {
                    ALIAvatarButton(name: currentMember?.name) {
                        onOpen(.people)
                    }
                    .accessibilityLabel(Text("People"))
                    // The "+" on other screens is a 58pt button scaled to 0.72, so its
                    // circle sits ~7pt in from the edge: match its center.
                    .padding(.trailing, 7)
                }
                .padding(.horizontal, 20)
                // Pull "Today" closer to the title (only on Home).
                .padding(.bottom, -12)

                let cards = summaryCards
                if !cards.isEmpty {
                    sectionTitle("Today")
                    VStack(spacing: 10) {
                        carousel(cards)
                        carouselDots(cards)
                    }
                }

                if visibleFeatures.contains(.board) {
                    if premium.isLocked(.board) {
                        sectionTitle("Board")
                        boardLockedPreview
                    } else if !myBoardNotes.isEmpty {
                        sectionTitle("Board")
                        boardSection
                    }
                }

                featuresHeader
                if isReordering {
                    Label {
                        Text("Drag a card by its handle to reorder it. Only you see this order.")
                    } icon: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                }
                featureGrid
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 100)
        }
        .scrollDisabled(draggingTab != nil)
        .background(ALIColors.background)
        .sensoryFeedback(.impact(weight: .medium), trigger: draggingTab) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: dragOrder)
        .onDisappear { isReordering = false }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(ALITypography.labelLarge)
            .foregroundStyle(ALIColors.mutedInk)
            .textCase(.uppercase)
            .padding(.horizontal, 24)
            .padding(.top, 4)
    }

    // MARK: Carousel

    private func carousel(_ cards: [HomeSummary]) -> some View {
        let count = cards.count
        let looping = count > 1
        let slots = looping ? count * carouselLoops : count
        let middle = looping ? count * (carouselLoops / 2) : 0

        // The current card sits centred; neighbours peek in from both sides.
        // Content margins of (width - cardWidth) / 2 make `.viewAligned`
        // snapping and the `.center`-anchored auto-advance land centred.
        return GeometryReader { proxy in
            let width = proxy.size.width
            let cardWidth = count == 1 ? width - 40 : width * 0.8
            let inset = (width - cardWidth) / 2
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(0..<slots, id: \.self) { slot in
                        let card = cards[slot % count]
                        Button {
                            Track.event("home_summary_tap", ["tab": card.tab.settingsKey])
                            onOpen(card.tab)
                        } label: {
                            ALIHomeSummaryCard(
                                title: card.tab.label,
                                systemImage: card.tab.systemImage,
                                accent: card.tab.accent,
                                headline: card.headline,
                                detail: card.detail
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: cardWidth)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                .opacity(phase.isIdentity ? 1 : 0.7)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $carouselPosition, anchor: .center)
        }
        .frame(height: 160)
        .onAppear {
            // Start in the middle so it can loop both ways.
            if carouselPosition == nil || carouselPosition! >= slots {
                carouselPosition = middle
            }
        }
        .onChange(of: count) { _, _ in
            carouselPosition = middle
        }
        // Restarts whenever the slot changes (auto or by swipe), so a manual
        // swipe gets its full interval before the next auto-advance.
        .task(id: "\(carouselPosition ?? -1)-\(count)") {
            guard looping, let current = carouselPosition else { return }
            // Near either end: once the scroll settles, silently jump to the
            // same card in the middle (identical content, so it's invisible).
            if current >= slots - count || current < count {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                carouselPosition = middle + current % count
                return
            }
            try? await Task.sleep(for: carouselInterval)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                carouselPosition = current + 1
            }
        }
    }

    /// Page indicator under the "Today" carousel: one dot per card, the
    /// current one wider and darker.
    @ViewBuilder
    private func carouselDots(_ cards: [HomeSummary]) -> some View {
        if cards.count > 1 {
            let active = (carouselPosition ?? 0) % cards.count
            HStack(spacing: 6) {
                ForEach(cards.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == active ? ALIColors.ink : ALIColors.mutedInk.opacity(0.35))
                        .frame(width: index == active ? 16 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: active)
            .accessibilityHidden(true)
        }
    }

    // MARK: Board

    /// Board notes addressed to this member (everyone's, or theirs).
    private var myBoardNotes: [BoardNote] {
        boardNotes.filter { $0.isFor(familySession.memberID) }
    }

    /// Locked Board: the same strip as the real one, with blurred sample
    /// notes where the real ones would go, plus a pill explaining it and
    /// leading to the paywall.
    private var boardLockedPreview: some View {
        Button {
            showPaywall = Track.paywall("home_board_preview")
        } label: {
            ZStack {
                boardStrip(sampleBoardNotes, onTap: { _ in })
                    .scrollDisabled(true)
                    .aliPremiumPreview(true)
                    .allowsHitTesting(false)

                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ALIColors.onAccent)
                        .frame(width: 24, height: 24)
                        .background(ALIColors.sun)
                        .clipShape(Circle())
                    Text("Pin messages here for the whole family")
                        .font(ALITypography.labelLarge.weight(.semibold))
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.leading, 8)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .background(ALIColors.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(ALIColors.outline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.horizontal, 32)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Every Board note for me, in the Board's order.
    private var boardSection: some View {
        boardStrip(myBoardNotes) { _ in
            Track.event("home_board_tap", ["notes": myBoardNotes.count])
            onOpen(.board)
        }
    }

    /// Horizontal strip of sticky notes, left-aligned with the Home gutter
    /// and a peek of the next note on the right (`.viewAligned` snaps each
    /// card to the leading content margin).
    private func boardStrip(
        _ notes: [BoardNote],
        position: Binding<UUID?> = .constant(nil),
        onTap: @escaping (BoardNote) -> Void
    ) -> some View {
        GeometryReader { proxy in
            let cardWidth = notes.count == 1 ? proxy.size.width - 40 : proxy.size.width * 0.62
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(notes) { note in
                        BoardNoteCard(note: note, compact: true, onTap: { onTap(note) })
                            .frame(width: cardWidth)
                    }
                }
                .scrollTargetLayout()
            }
            // Left-aligned with the rest of Home (20pt gutter); snaps each
            // card to that same leading edge, with a peek of the next one.
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: position, anchor: .leading)
        }
        .frame(height: 120)
    }

    // MARK: Grid

    /// "All features" title with the Reorder / Done button.
    private var featuresHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            sectionTitle("All features")
            Spacer()
            if visibleFeatures.count > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isReordering.toggle() }
                    if isReordering { Track.event("home_features_reorder_tap") }
                } label: {
                    Text(isReordering ? "Done" : "Reorder")
                        .font(ALITypography.labelLarge.weight(.semibold))
                        .foregroundStyle(ALIColors.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isReordering ? AppTab.home.accent : ALIColors.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(ALIColors.outline, lineWidth: isReordering ? 0 : 1))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.top, 4)
            }
        }
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(displayedFeatures) { tab in
                featureTile(tab)
            }
        }
        .coordinateSpace(.named(Self.gridSpace))
    }

    private static let gridSpace = "homeFeatureGrid"

    @ViewBuilder
    private func featureTile(_ tab: AppTab) -> some View {
        let locked = isLocked(tab)
        let isDragging = draggingTab == tab
        Button {
            guard !isReordering else { return }
            if locked {
                showPaywall = Track.paywall("home_feature_\(tab.settingsKey)")
            } else {
                onOpen(tab)
            }
        } label: {
            ALIFeatureTile(
                title: tab.label,
                systemImage: tab.systemImage,
                accent: tab.accent,
                detail: showsCrown(tab) ? nil : tileDetail(for: tab)
            )
        }
        .buttonStyle(.plain)
        // The Board opens as a blurred preview when locked, but still
        // gets the crown so it reads as premium from the grid.
        .aliPremiumLockOverlay(showsCrown(tab) && !isReordering)
        .overlay(alignment: .topTrailing) {
            if isReordering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isDragging ? ALIColors.ink : ALIColors.mutedInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .highPriorityGesture(reorderGesture(for: tab))
                    .accessibilityLabel(Text("Reorder"))
                    .padding(4)
                    .transition(.opacity)
            }
        }
        .background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(Self.gridSpace))
                Color.clear
                    .onAppear { tileFrames[tab] = frame }
                    .onChange(of: frame) { _, new in tileFrames[tab] = new }
            }
        )
        .scaleEffect(isDragging ? 1.05 : 1)
        .shadow(color: Color.black.opacity(isDragging ? 0.18 : 0), radius: isDragging ? 16 : 0, y: isDragging ? 8 : 0)
        .offset(isDragging ? dragOffset(for: tab) : .zero)
        .zIndex(isDragging ? 1 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
    }

    /// Keeps the lifted card under the finger even after it changed slot.
    private func dragOffset(for tab: AppTab) -> CGSize {
        guard let index = dragOrder.firstIndex(of: tab),
              dragSlots.indices.contains(index), dragSlots.indices.contains(dragStartIndex) else { return dragTranslation }
        let start = dragSlots[dragStartIndex].origin
        let current = dragSlots[index].origin
        return CGSize(
            width: start.x + dragTranslation.width - current.x,
            height: start.y + dragTranslation.height - current.y
        )
    }

    /// Press the grip to lift the card; move it over another slot to place
    /// it there (the rest shift along); release to save the order.
    private func reorderGesture(for tab: AppTab) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                if draggingTab == nil {
                    let order = visibleFeatures
                    guard let start = order.firstIndex(of: tab) else { return }
                    dragOrder = order
                    dragSlots = order.map { tileFrames[$0] ?? .zero }
                    dragStartIndex = start
                    draggingTab = tab
                }
                guard draggingTab == tab else { return }
                dragTranslation = value.translation
                moveIfNeeded(tab, to: value.location)
            }
            .onEnded { _ in
                guard draggingTab == tab else { return }
                // Save first, so when the working order is dropped the grid
                // already reads the same order (otherwise it would flash the
                // old order and animate every card back and forth).
                persistOrder(dragOrder)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    draggingTab = nil
                    dragTranslation = .zero
                }
            }
    }

    /// Moves the dragged card into the slot under the finger.
    private func moveIfNeeded(_ tab: AppTab, to location: CGPoint) {
        guard let current = dragOrder.firstIndex(of: tab),
              let target = dragSlots.firstIndex(where: { $0.contains(location) }),
              target != current else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            dragOrder.remove(at: current)
            dragOrder.insert(tab, at: target)
        }
    }

    /// Saves the personal order. Hidden features keep their stored place
    /// after the visible ones, so un-hiding one doesn't lose it.
    private func persistOrder(_ order: [AppTab]) {
        let keys = order.map(\.settingsKey)
        guard keys != visibleFeatures.map(\.settingsKey) else { return }
        let hidden = familySession.homeFeatureOrder.filter { !keys.contains($0) }
        familySession.setHomeFeatureOrder(keys + hidden)
        Track.event("home_features_reorder", ["features": keys.count])
    }

    /// Whole-feature locks, plus the Board, which opens as a blurred
    /// preview when locked but still reads as premium from the grid.
    private func showsCrown(_ tab: AppTab) -> Bool {
        isLocked(tab) || (tab == .board && premium.isLocked(.board))
    }

    /// Stable stat line for each feature tile — different from the "Today"
    /// cards (which are about what's due now): how much there is overall.
    private func tileDetail(for tab: AppTab) -> String? {
        switch tab {
        case .weeklyMenu:
            let count = mealPlan.count
            if count == 0 { return String(localized: "Nothing planned") }
            return count == 1 ? String(localized: "1 meal planned") : String(localized: "\(count) meals planned")
        case .recipes:
            let count = recipes.count
            if count == 0 { return String(localized: "No recipes yet") }
            return count == 1 ? String(localized: "1 recipe") : String(localized: "\(count) recipes")
        case .shoppingList:
            let count = shoppingEntries.filter { !$0.isChecked }.count
            if count == 0 { return String(localized: "Nothing to buy") }
            return count == 1 ? String(localized: "1 to buy") : String(localized: "\(count) to buy")
        case .houseTasks:
            let count = houseTasks.count
            if count == 0 { return String(localized: "No tasks yet") }
            return count == 1 ? String(localized: "1 task") : String(localized: "\(count) tasks")
        case .familyCalendar:
            guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return nil }
            let count = events.filter { $0.startDate < week.end && $0.endDate >= week.start }.count
            if count == 0 { return String(localized: "No events this week") }
            return count == 1 ? String(localized: "1 event this week") : String(localized: "\(count) events this week")
        case .reminders:
            let count = reminders.filter { $0.fireDate >= .now }.count
            if count == 0 { return String(localized: "No upcoming reminders") }
            return count == 1 ? String(localized: "1 upcoming") : String(localized: "\(count) upcoming")
        case .economia:
            guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return nil }
            let spent = expenses
                .filter { !$0.isIncome && month.contains($0.occurredAt) }
                .reduce(0) { $0 + $1.amount }
            if spent == 0 { return String(localized: "No expenses this month") }
            return String(localized: "\(spent.formattedEuros) this month")
        case .board:
            let count = myBoardNotes.count
            if count == 0 { return String(localized: "No notes") }
            return count == 1 ? String(localized: "1 note") : String(localized: "\(count) notes")
        case .home, .people:
            return nil
        }
    }

    // MARK: Summaries

    /// One card per visible, unlocked feature that has something relevant
    /// today — in the same order as the grid.
    private var summaryCards: [HomeSummary] {
        visibleFeatures
            .filter { !isLocked($0) }
            .compactMap(summary(for:))
    }

    private func summary(for tab: AppTab) -> HomeSummary? {
        switch tab {
        case .houseTasks: return tasksSummary
        case .familyCalendar: return calendarSummary
        case .weeklyMenu: return menuSummary
        case .shoppingList: return shoppingSummary
        case .reminders: return remindersSummary
        case .economia: return financesSummary
        case .recipes, .board, .home, .people: return nil
        }
    }

    /// Tasks with a cadence that are due today or overdue (or never done).
    private var tasksSummary: HomeSummary? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? .now
        let due = houseTasks.filter { task in
            // Only tasks for me (everyone's, or assigned to me).
            guard task.isFor(familySession.memberID) else { return false }
            let lastLog = houseTaskLogs.filter { $0.taskID == task.id }.max { $0.completedAt < $1.completedAt }
            if task.isDone(lastLog: lastLog) { return false }
            // Scheduled: pending once its day arrives, until it's done.
            if let scheduled = task.pendingSchedule(lastLog: lastLog) { return scheduled < endOfToday }
            guard let interval = task.intervalDays else { return false }
            guard let last = lastLog?.completedAt else { return true }
            let since = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: today).day ?? 0
            return since >= interval
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !due.isEmpty else { return nil }
        let headline = due.count == 1
            ? String(localized: "1 task pending")
            : String(localized: "\(due.count) tasks pending")
        return HomeSummary(tab: .houseTasks, headline: headline, detail: namesPreview(due.map(\.name)))
    }

    private var calendarSummary: HomeSummary? {
        let now = Date.now
        guard let next = events.first(where: { $0.endDate >= now }) else { return nil }
        let when: String
        if next.isAllDay {
            when = next.startDate <= now ? String(localized: "Today") : dayLabel(for: next.startDate)
        } else {
            when = next.startDate <= now ? String(localized: "Now") : dayLabel(for: next.startDate)
        }
        let detail = "\(when) · \(next.attendeesLabel(members: members))"
        return HomeSummary(tab: .familyCalendar, headline: next.title, detail: detail)
    }

    private var menuSummary: HomeSummary? {
        // MealPlanEntry.weekday: 0 = Monday ... 6 = Sunday (see WidgetSnapshotWriter).
        let todayWeekday = (Calendar.current.component(.weekday, from: .now) + 5) % 7
        let today = mealPlan.filter { $0.weekday == todayWeekday }
        let lunch = today.first { $0.mealType == MealType.lunch.rawValue }?.dishName
        let dinner = today.first { $0.mealType == MealType.dinner.rawValue }?.dishName
        switch (lunch, dinner) {
        case let (lunch?, dinner?):
            return HomeSummary(tab: .weeklyMenu, headline: lunch, detail: String(localized: "Dinner: \(dinner)"))
        case let (lunch?, nil):
            return HomeSummary(tab: .weeklyMenu, headline: lunch, detail: String(localized: "Lunch"))
        case let (nil, dinner?):
            return HomeSummary(tab: .weeklyMenu, headline: dinner, detail: String(localized: "Dinner"))
        case (nil, nil):
            return nil
        }
    }

    private var shoppingSummary: HomeSummary? {
        let pending = shoppingEntries.filter { !$0.isChecked }
        guard !pending.isEmpty else { return nil }
        let headline = pending.count == 1
            ? String(localized: "1 item to buy")
            : String(localized: "\(pending.count) items to buy")
        return HomeSummary(tab: .shoppingList, headline: headline, detail: namesPreview(pending.map(\.name)))
    }

    private var remindersSummary: HomeSummary? {
        guard let next = reminders.first(where: { $0.fireDate >= .now }) else { return nil }
        let detail = "\(dayLabel(for: next.fireDate)) · \(next.fireDate.formatted(date: .omitted, time: .shortened))"
        return HomeSummary(tab: .reminders, headline: next.title, detail: detail)
    }

    private var financesSummary: HomeSummary? {
        let settlements = FinanceBalances.settlements(expenses: expenses, members: members)
        guard let first = settlements.first else { return nil }
        var detail = first.amount.formattedEuros
        if settlements.count > 1 {
            detail += " · " + String(localized: "+\(settlements.count - 1) more")
        }
        return HomeSummary(tab: .economia, headline: String(localized: "\(first.from.name) owes \(first.to.name)"), detail: detail)
    }

    // MARK: Helpers

    /// "Milk, Eggs, Bread +2 more"
    private func namesPreview(_ names: [String], limit: Int = 3) -> String {
        var text = names.prefix(limit).joined(separator: ", ")
        if names.count > limit {
            text += " " + String(localized: "+\(names.count - limit) more")
        }
        return text
    }

    /// "Today", "Tomorrow" or e.g. "Friday, 3 Oct".
    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// One card of the Home carousel.
private struct HomeSummary: Identifiable {
    let tab: AppTab
    let headline: String
    let detail: String?

    var id: AppTab { tab }
}
