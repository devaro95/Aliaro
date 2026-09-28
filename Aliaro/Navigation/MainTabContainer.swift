import SwiftUI
import Combine

/// Container for the top-level screens with the floating bar on top.
///
/// The bar holds Home + the group's (up to 5) favorite features. Every
/// other feature — and People, from the avatar — is pushed onto Home's
/// `NavigationStack`, so new features never need a bar slot.
struct MainTabContainer: View {
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var familySession: FamilySession
    @Environment(\.modelContext) private var modelContext

    @State private var selected: AppTab
    /// Screens pushed on top of Home (features that aren't favorites, and People).
    @State private var homePath: [AppTab]
    @StateObject private var bottomBarScrollTracker = BottomBarScrollTracker()

    init() {
        let initial = MainTabContainer.initialNavigation()
        _selected = State(initialValue: initial.selected)
        _homePath = State(initialValue: initial.homePath)
    }

    /// The (up to 5) favorite features next to Home in the bar.
    private var favorites: [AppTab] {
        AppTab.favorites(stored: familySession.favoriteTabs, excluding: familySession.disabledTabs)
    }

    /// What the bottom bar shows, in order.
    private var barTabs: [AppTab] { [.home] + favorites }

    /// Where the app opens, from the admin's start tab: a favorite is
    /// selected in the bar; any other visible feature is pushed on top of
    /// Home; hidden/unset falls back to Home. Read directly from the
    /// singleton since it feeds `@State` initial values, evaluated before
    /// environment objects are injected.
    private static func initialNavigation() -> (selected: AppTab, homePath: [AppTab]) {
        let session = FamilySession.shared
        let start = AppTab.start(stored: session.startTab, excluding: session.disabledTabs)
        guard start != .home else { return (.home, []) }
        let favorites = AppTab.favorites(stored: session.favoriteTabs, excluding: session.disabledTabs)
        return favorites.contains(start) ? (start, []) : (.home, [start])
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if selected == .home {
                    NavigationStack(path: $homePath) {
                        HomeScreen(favorites: favorites, onOpen: openFeature)
                            .navigationDestination(for: AppTab.self) { tab in
                                screen(for: tab)
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbarBackground(.hidden, for: .navigationBar)
                                    .background(ALIColors.background)
                            }
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .tint(ALIColors.ink)
                } else {
                    screen(for: selected)
                }
            }
            .environmentObject(bottomBarScrollTracker)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ALIBottomBar(
                selected: $selected,
                visibleTabs: barTabs,
                collapseFraction: bottomBarScrollTracker.collapseFraction,
                onReselect: { tab in
                    // Tapping Home again goes back to the Home root.
                    if tab == .home, !homePath.isEmpty { homePath.removeAll() }
                }
            )
        }
        .background(ALIColors.background)
        .ignoresSafeArea(.keyboard)
        .onReceive(PushNotificationManager.shared.$pendingTab.compactMap { $0 }) { tab in
            PushNotificationManager.shared.pendingTab = nil
            openFromPush(tab)
        }
        .onChange(of: selected) { old, new in
            bottomBarScrollTracker.reset()
            Track.event("tab_selected", ["tab": new.settingsKey, "from": old.settingsKey])
        }
        .onChange(of: homePath) { _, _ in
            bottomBarScrollTracker.reset()
        }
        .onChange(of: familySession.disabledTabs) { _, _ in
            fixNavigationAfterSettingsChange()
        }
        .onChange(of: familySession.favoriteTabs) { _, _ in
            fixNavigationAfterSettingsChange()
        }
        .onAppear {
            Track.event("app_home_shown", [
                "initial_tab": (homePath.last ?? selected).settingsKey,
                "visible_tabs": AppTab.visibleFeatures(excluding: familySession.disabledTabs).count,
            ])
        }
        .task {
            if let familyID = familySession.familyID, let memberID = familySession.memberID {
                await dataSync.startAll(familyID: familyID, currentMemberID: memberID, modelContext: modelContext)
                await familyService.refreshFamilySettings()
                await familyService.startSettingsSync(familyID: familyID)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeScreen(favorites: favorites, onOpen: openFeature)
        case .weeklyMenu: WeeklyMenuScreen()
        case .recipes: RecipesScreen()
        case .shoppingList: ShoppingListScreen()
        case .houseTasks: HouseTasksScreen()
        case .familyCalendar: FamilyCalendarScreen()
        case .reminders: RemindersScreen()
        case .board: BoardScreen()
        case .economia: EconomiaScreen()
        case .people: PeopleScreen()
        }
    }

    /// Opens a feature (or People) from Home: favorites switch the bar's
    /// selection so there's only ever one copy of a screen; the rest are
    /// pushed on Home's stack.
    private func openFeature(_ tab: AppTab) {
        Track.event("home_feature_open", ["tab": tab.settingsKey, "is_favorite": favorites.contains(tab)])
        if favorites.contains(tab) {
            homePath.removeAll()
            selected = tab
        } else {
            homePath = [tab]
        }
    }

    /// Opens the screen a tapped push points to (skipped if the admin hid it).
    private func openFromPush(_ tab: AppTab) {
        guard !familySession.disabledTabs.contains(tab.settingsKey) else { return }
        Track.event("push_open_tab", ["tab": tab.settingsKey])
        if favorites.contains(tab) {
            homePath.removeAll()
            selected = tab
        } else {
            selected = .home
            homePath = [tab]
        }
    }

    /// The admin may have just hidden the feature we're on, or changed the
    /// favorites (possibly from another device): fall back to Home and drop
    /// any pushed screen that's no longer available.
    private func fixNavigationAfterSettingsChange() {
        if !barTabs.contains(selected) {
            selected = .home
        }
        homePath.removeAll { $0.isFeature && familySession.disabledTabs.contains($0.settingsKey) }
    }
}
