import SwiftUI

/// Every top-level destination of the app. Two concepts live here:
///
/// - **Features** (`AppTab.features`): Menu, Shopping, Tasks, Calendar,
///   Reminders, Finances… — all of them reachable from the Home grid.
///   New ones (Recipes, Documents…) are added here without touching the
///   bottom bar.
/// - **Bottom-bar tabs**: always `home` + up to 5 favorite features chosen
///   by the group admin (`FamilySession.favoriteTabs`), see `barTabs`.
///
/// `people` is neither: it opens from the avatar on the Home top bar.
enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case home
    case weeklyMenu
    case recipes
    case shoppingList
    case houseTasks
    case familyCalendar
    case reminders
    case board
    case economia
    case people

    /// Maximum number of favorite features shown in the bottom bar next to Home.
    static let maxFavorites = 5

    /// How many favorites are pre-picked when the admin hasn't chosen any yet.
    static let defaultFavoritesCount = 3

    var id: Int { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .home: return "Home"
        case .weeklyMenu: return "Menu"
        case .recipes: return "Recipes"
        case .shoppingList: return "Shopping"
        case .houseTasks: return "Tasks"
        case .familyCalendar: return "Family"
        case .reminders: return "Reminders"
        case .board: return "Board"
        case .economia: return "Finances"
        case .people: return "People"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .weeklyMenu: return "fork.knife"
        case .recipes: return "book.pages.fill"
        case .shoppingList: return "cart.fill"
        case .houseTasks: return "checklist"
        case .familyCalendar: return "calendar"
        case .reminders: return "bell.fill"
        case .board: return "pin.fill"
        case .economia: return "eurosign.circle.fill"
        case .people: return "person.2.fill"
        }
    }

    var accent: Color {
        switch self {
        case .home: return ALIColors.primary
        case .weeklyMenu: return ALIColors.weeklyMenuAccent
        case .recipes: return ALIColors.recipesAccent
        case .shoppingList: return ALIColors.shoppingAccent
        case .houseTasks: return ALIColors.houseTasksAccent
        case .familyCalendar: return ALIColors.familyAccent
        case .reminders: return ALIColors.remindersAccent
        case .board: return ALIColors.boardAccent
        case .economia: return ALIColors.economiaAccent
        case .people: return ALIColors.peopleAccent
        }
    }

    /// Stable identifier for this tab as stored in `families.disabled_tabs`,
    /// `.start_tab` and `.favorite_tabs` (Supabase) — independent of
    /// `rawValue`/case order so it never drifts if tabs are reordered later.
    var settingsKey: String {
        switch self {
        case .home: return "home"
        case .weeklyMenu: return "weekly_menu"
        case .recipes: return "recipes"
        case .shoppingList: return "shopping_list"
        case .houseTasks: return "house_tasks"
        case .familyCalendar: return "family_calendar"
        case .reminders: return "reminders"
        case .board: return "board"
        case .economia: return "economia"
        case .people: return "people"
        }
    }

    /// Whether this is a feature: shows up in the Home grid, can be hidden
    /// by the admin and picked as a bottom-bar favorite. Home is always on
    /// (it's the hub) and People lives behind the avatar — hiding it would
    /// lock everyone out of turning features back on.
    var isFeature: Bool { self != .home && self != .people }

    /// Kept for readability at call sites that talk about the admin setting.
    var isConfigurable: Bool { isFeature }

    /// Premium capability that gates the *whole* feature, if any. Feature
    /// cards for a locked one show the crown and open the paywall instead
    /// of the screen. No current feature is gated as a whole (premium is
    /// per capability inside each screen), but future ones can opt in here.
    var premiumFeature: PremiumFeature? { nil }

    /// Every feature, in canonical (grid) order.
    static var features: [AppTab] { allCases.filter(\.isFeature) }

    /// Features the admin hasn't hidden, in canonical order.
    static func visibleFeatures(excluding disabledTabs: Set<String>) -> [AppTab] {
        features.filter { !disabledTabs.contains($0.settingsKey) }
    }

    /// `tabs` sorted by this member's personal Home order (`stored`
    /// `settingsKey`s). Tabs not in `stored` (e.g. a feature added after
    /// the user reordered) keep their canonical order, after the rest.
    static func ordered(_ tabs: [AppTab], by stored: [String]) -> [AppTab] {
        guard !stored.isEmpty else { return tabs }
        let rank = Dictionary(stored.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return tabs.enumerated()
            .sorted { lhs, rhs in
                let l = rank[lhs.element.settingsKey] ?? Int.max
                let r = rank[rhs.element.settingsKey] ?? Int.max
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Looks up the tab for a stored `settingsKey` (e.g. from
    /// `families.start_tab`, `.disabled_tabs` or `.favorite_tabs`), if one matches.
    static func from(settingsKey: String) -> AppTab? {
        allCases.first { $0.settingsKey == settingsKey }
    }

    /// The favorite features shown in the bottom bar after Home: the admin's
    /// stored choice (order kept, hidden/unknown/duplicate keys dropped,
    /// max `maxFavorites`) or — when nothing valid is stored — the first
    /// `defaultFavoritesCount` visible features.
    static func favorites(stored: [String], excluding disabledTabs: Set<String>) -> [AppTab] {
        var result: [AppTab] = []
        for key in stored {
            guard let tab = from(settingsKey: key), tab.isFeature,
                  !disabledTabs.contains(key), !result.contains(tab) else { continue }
            result.append(tab)
        }
        if result.isEmpty {
            // Nothing stored yet (or everything stored got hidden).
            result = Array(visibleFeatures(excluding: disabledTabs).prefix(defaultFavoritesCount))
        }
        return Array(result.prefix(maxFavorites))
    }

    /// Where the app opens: the admin's start tab if it's Home or a visible
    /// feature, otherwise Home.
    static func start(stored: String?, excluding disabledTabs: Set<String>) -> AppTab {
        guard let key = stored, let tab = from(settingsKey: key) else { return .home }
        if tab == .home { return .home }
        return tab.isFeature && !disabledTabs.contains(key) ? tab : .home
    }
}
