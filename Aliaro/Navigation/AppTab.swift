import SwiftUI

/// The tabs on the floating bottom bar. They're all top-level
/// (there's no navigation stack between them).
enum AppTab: Int, CaseIterable, Identifiable {
    case weeklyMenu
    case shoppingList
    case houseTasks
    case familyCalendar
    case reminders
    case economia
    case people

    var id: Int { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .weeklyMenu: return "Menu"
        case .shoppingList: return "Shopping"
        case .houseTasks: return "Tasks"
        case .familyCalendar: return "Family"
        case .reminders: return "Reminders"
        case .economia: return "Finances"
        case .people: return "People"
        }
    }

    var systemImage: String {
        switch self {
        case .weeklyMenu: return "fork.knife"
        case .shoppingList: return "cart.fill"
        case .houseTasks: return "checklist"
        case .familyCalendar: return "calendar"
        case .reminders: return "bell.fill"
        case .economia: return "eurosign.circle.fill"
        case .people: return "person.2.fill"
        }
    }

    var accent: Color {
        switch self {
        case .weeklyMenu: return ALIColors.weeklyMenuAccent
        case .shoppingList: return ALIColors.shoppingAccent
        case .houseTasks: return ALIColors.houseTasksAccent
        case .familyCalendar: return ALIColors.familyAccent
        case .reminders: return ALIColors.remindersAccent
        case .economia: return ALIColors.economiaAccent
        case .people: return ALIColors.peopleAccent
        }
    }

    /// Stable identifier for this tab as stored in `families.disabled_tabs`
    /// (Supabase) — independent of `rawValue`/case order so it never
    /// drifts if tabs are reordered later.
    var settingsKey: String {
        switch self {
        case .weeklyMenu: return "weekly_menu"
        case .shoppingList: return "shopping_list"
        case .houseTasks: return "house_tasks"
        case .familyCalendar: return "family_calendar"
        case .reminders: return "reminders"
        case .economia: return "economia"
        case .people: return "people"
        }
    }

    /// Whether the admin can turn this tab off. The Group tab itself is
    /// always on — it's where this setting lives, so hiding it would lock
    /// everyone out of turning features back on.
    var isConfigurable: Bool { self != .people }

    /// Looks up the tab for a stored `settingsKey` (e.g. from
    /// `families.start_tab` or `.disabled_tabs`), if one matches.
    static func from(settingsKey: String) -> AppTab? {
        allCases.first { $0.settingsKey == settingsKey }
    }

    /// The tab that opens first when no valid start tab is chosen: Weekly
    /// Menu, or — if the admin has hidden it — the next one still visible,
    /// in bottom-bar order. "People" is only ever the last resort.
    static func firstAvailable(excluding disabledTabs: Set<String>) -> AppTab {
        allCases.first { $0.isConfigurable && !disabledTabs.contains($0.settingsKey) } ?? .people
    }
}
