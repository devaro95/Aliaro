import SwiftUI
import MapKit
import UIKit
import Combine

/// Container for the top-level screens with the floating bar on top.
///
/// The bar holds Home + the group's (up to 5) favorite features. Every
/// other feature — and People, from the avatar — is pushed onto Home's
/// `NavigationStack`, so new features never need a bar slot.
struct MainTabContainer: View {
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @ObservedObject private var whatsNew = WhatsNew.shared
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var familySession: FamilySession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selected: AppTab
    /// Screens pushed on top of Home (features that aren't favorites, and People).
    @State private var homePath: [AppTab]
    @StateObject private var bottomBarScrollTracker = BottomBarScrollTracker()
    /// Screens shown over everything (Lists → add products) hide the bar too.
    @StateObject private var screenChrome = ScreenChrome()
    @Environment(\.colorScheme) private var colorScheme

    init() {
        let initial = MainTabContainer.initialNavigation()
        _selected = State(initialValue: initial.selected)
        _homePath = State(initialValue: initial.homePath)
    }

    /// The (up to 5) favorite features next to Home in the bar.
    private var favorites: [AppTab] {
        AppTab.favorites(stored: familySession.favoriteTabs, excluding: familySession.disabledTabs)
    }

    /// The screen on top right now (a favorite, or what's pushed on Home).
    private var currentScreen: AppTab { selected == .home ? (homePath.last ?? .home) : selected }

    /// Full-screen screens (the Places map) hide the floating bar and show
    /// their own back button instead.
    private var hidesBottomBar: Bool { currentScreen == .places || screenChrome.coversBottomBar }

    /// Back from a full-screen screen: pop it from Home, or go to Home if it's a favorite.
    private func leaveFullScreen() {
        if !homePath.isEmpty { homePath.removeLast() } else { selected = .home }
    }

    /// What the bottom bar shows, in order.
    private var barTabs: [AppTab] { [.home] + favorites }

    /// Where the app opens, from the admin's start tab (except right after
    /// the group was loaded on this device, which always opens on Home): a favorite is
    /// selected in the bar; any other visible feature is pushed on top of
    /// Home; hidden/unset falls back to Home. Read directly from the
    /// singleton since it feeds `@State` initial values, evaluated before
    /// environment objects are injected.
    private static func initialNavigation() -> (selected: AppTab, homePath: [AppTab]) {
        let session = FamilySession.shared
        // First time in after creating/joining/restoring the group: Home.
        if session.opensOnHomeNext {
            session.opensOnHomeNext = false
            return (.home, [])
        }
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
                                    // Full-screen screens bring their own back button.
                                    .toolbar(tab == .places ? .hidden : .automatic, for: .navigationBar)
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
            .environmentObject(screenChrome)
            .environment(\.leaveFullScreen, LeaveFullScreenAction(run: leaveFullScreen))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !hidesBottomBar {
                ALIBottomBar(
                    // Places asks for location before opening (not on top of the map).
                    selected: Binding(
                        get: { selected },
                        set: { tab in
                            if tab == .places {
                                LocationPermission.shared.requestIfNeeded { selected = tab }
                            } else {
                                selected = tab
                            }
                        }
                    ),
                    visibleTabs: barTabs,
                    collapseFraction: bottomBarScrollTracker.collapseFraction,
                    onReselect: { tab in
                        // Tapping Home again goes back to the Home root.
                        if tab == .home, !homePath.isEmpty { homePath.removeAll() }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hidesBottomBar)
        .background(ALIColors.background)
        .ignoresSafeArea(.keyboard)
        .onReceive(PushNotificationManager.shared.$pendingTab.compactMap { $0 }) { tab in
            PushNotificationManager.shared.pendingTab = nil
            openFromPush(tab)
        }
        .onChange(of: selected) { old, new in
            bottomBarScrollTracker.reset()
            // Leaving Home for another tab drops whatever was pushed on it,
            // so tapping Home in the bar always lands on the Home root.
            if old == .home, new != .home, !homePath.isEmpty { homePath.removeAll() }
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
        .sheet(isPresented: $whatsNew.isPresented) {
            WhatsNewSheet()
        }
        .onAppear { whatsNew.showIfNeeded() }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Back from the background: catch up on changes missed while suspended.
            guard oldPhase == .background, newPhase != .background,
                  let familyID = familySession.familyID, let memberID = familySession.memberID else { return }
            Task {
                await dataSync.resyncAfterBackground(familyID: familyID, currentMemberID: memberID, modelContext: modelContext)
                await familyService.refreshFamilySettings()
            }
        }
        .task {
            // Places: warm up MapKit (the first map is slow to set up) and make the
            // locked preview's map image, a few seconds after launch.
            Task {
                try? await Task.sleep(for: .seconds(2))
                MapKitWarmUp.run()
                SampleMapSnapshotStore.preload(colorScheme: colorScheme)
            }
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
        case .wifi: WifiScreen()
        case .places: PlacesScreen()
        case .worldMap: WorldMapScreen()
        case .people: PeopleScreen()
        }
    }

    /// Opens a feature (or People) from Home: favorites switch the bar's
    /// selection so there's only ever one copy of a screen; the rest are
    /// pushed on Home's stack.
    private func openFeature(_ tab: AppTab) {
        // Places asks for location before opening (not on top of the map).
        if tab == .places {
            LocationPermission.shared.requestIfNeeded { openFeatureNow(tab) }
        } else {
            openFeatureNow(tab)
        }
    }

    private func openFeatureNow(_ tab: AppTab) {
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

/// "Back" for full-screen screens without the floating bar (Places).
struct LeaveFullScreenAction {
    let run: () -> Void
    func callAsFunction() { run() }
}

private struct LeaveFullScreenKey: EnvironmentKey {
    static let defaultValue = LeaveFullScreenAction(run: {})
}

extension EnvironmentValues {
    var leaveFullScreen: LeaveFullScreenAction {
        get { self[LeaveFullScreenKey.self] }
        set { self[LeaveFullScreenKey.self] = newValue }
    }
}

/// Keeps the swipe-from-the-edge "back" working on pushed screens that hide
/// the navigation bar (Places draws its own back button): SwiftUI turns the
/// gesture off when the bar is hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

/// Lets a screen hide the floating bar while it shows something full screen over itself.
@MainActor
final class ScreenChrome: ObservableObject {
    @Published var coversBottomBar = false
}

/// Creates (and drops) one map view off screen so MapKit's first-time setup
/// (rendering engine, styles) happens before the user opens Places.
@MainActor
enum MapKitWarmUp {
    private static var done = false

    static func run() {
        guard !done else { return }
        done = true
        let view = MKMapView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        view.pointOfInterestFilter = .excludingAll
        // Keep it alive briefly so it loads its resources, then release it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { _ = view }
    }
}
