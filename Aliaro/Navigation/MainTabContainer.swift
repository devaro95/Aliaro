import SwiftUI

/// Container for the top-level screens with the floating bar on top.
struct MainTabContainer: View {
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var familySession: FamilySession
    @Environment(\.modelContext) private var modelContext

    @State private var selected: AppTab = MainTabContainer.initialTab()
    @StateObject private var bottomBarScrollTracker = BottomBarScrollTracker()

    /// Every tab, minus whatever the admin has turned off for the family
    /// group — the Group tab itself is never hidden.
    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { !$0.isConfigurable || !familySession.disabledTabs.contains($0.settingsKey) }
    }

    /// The tab the admin picked to open first for the group, if it's set
    /// and not itself hidden. Read directly from the singleton since this
    /// feeds a `@State` initial value, evaluated before environment
    /// objects are injected.
    private static func initialTab() -> AppTab {
        let session = FamilySession.shared
        if let key = session.startTab, let tab = AppTab.from(settingsKey: key),
           tab.isConfigurable, !session.disabledTabs.contains(key) {
            return tab
        }
        // No explicit (still valid) choice: Weekly Menu, or the next
        // visible tab in bottom-bar order if that one's hidden.
        return AppTab.firstAvailable(excluding: session.disabledTabs)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selected {
                case .weeklyMenu: WeeklyMenuScreen()
                case .shoppingList: ShoppingListScreen()
                case .houseTasks: HouseTasksScreen()
                case .familyCalendar: FamilyCalendarScreen()
                case .reminders: RemindersScreen()
                case .economia: EconomiaScreen()
                case .people: PeopleScreen()
                }
            }
            .environmentObject(bottomBarScrollTracker)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ALIBottomBar(selected: $selected, visibleTabs: visibleTabs, collapseFraction: bottomBarScrollTracker.collapseFraction)
        }
        .background(ALIColors.background)
        .ignoresSafeArea(.keyboard)
        .onChange(of: selected) { old, new in
            bottomBarScrollTracker.reset()
            Track.event("tab_selected", ["tab": new.settingsKey, "from": old.settingsKey])
        }
        .onChange(of: familySession.disabledTabs) { _, _ in
            // The tab we're on may have just been hidden by the admin
            // (possibly from another device) — fall back to the first
            // tab that's still visible.
            if !visibleTabs.contains(selected) {
                selected = visibleTabs.first ?? .people
            }
        }
        .onAppear {
            Track.event("app_home_shown", ["initial_tab": selected.settingsKey, "visible_tabs": visibleTabs.count])
        }
        .task {
            if let familyID = familySession.familyID, let memberID = familySession.memberID {
                await dataSync.startAll(familyID: familyID, currentMemberID: memberID, modelContext: modelContext)
                await familyService.refreshFamilySettings()
                await familyService.startSettingsSync(familyID: familyID)
            }
        }
    }
}
