import SwiftUI

/// A capability that can be toggled between free and premium from the
/// `premium_features` table in Supabase (`key` column matches `rawValue`
/// here) — Varo flips these remotely via SQL, no app update needed, and
/// every device picks up the change live through `PremiumConfig`.
enum PremiumFeature: String, CaseIterable, Identifiable {
    // Case order = paywall order: the Board goes first (headline feature).
    case board
    case historial
    case extraShoppingLists = "extra_shopping_lists"
    case unlimitedReminders = "unlimited_reminders"
    case houseTasksCalendar = "house_tasks_calendar"
    case houseTasksStats = "house_tasks_stats"
    case unlimitedHouseTasks = "unlimited_house_tasks"
    case economiaStats = "economia_stats"
    case extraMembers = "extra_members"
    case extraCategories = "extra_categories"
    case financeArchive = "finance_archive"

    var id: String { rawValue }

    /// Shown in the paywall's feature list.
    var title: LocalizedStringKey {
        switch self {
        case .historial: return "Group history"
        case .extraShoppingLists: return "Multiple shopping lists"
        case .unlimitedReminders: return "Unlimited reminders"
        case .houseTasksCalendar: return "Tasks calendar view"
        case .houseTasksStats: return "Task statistics"
        case .unlimitedHouseTasks: return "Unlimited house tasks"
        case .economiaStats: return "Finance statistics"
        case .extraMembers: return "Bigger family group"
        case .extraCategories: return "Custom finance categories"
        case .financeArchive: return "Archive finances and export to PDF"
        case .board: return "Family board"
        }
    }

    /// One-line benefit shown under the title in the paywall.
    var subtitle: LocalizedStringKey {
        switch self {
        case .historial: return "See who did what and when in your group."
        case .extraShoppingLists: return "Separate lists for the supermarket, the pharmacy and more."
        case .unlimitedReminders: return "Never forget anything important again."
        case .houseTasksCalendar: return "Plan the week's chores at a glance."
        case .houseTasksStats: return "Find out who pulls their weight at home."
        case .unlimitedHouseTasks: return "Add all the chores your home needs."
        case .economiaStats: return "Understand where your money goes each month."
        case .extraMembers: return "Add more people to your family group."
        case .extraCategories: return "Organise your expenses your way."
        case .financeArchive: return "Close periods and keep your accounts as a PDF."
        case .board: return "Pin messages on your family's Home screen."
        }
    }

    /// Same accent as the section of the app the feature belongs to.
    var accent: Color {
        switch self {
        case .historial: return ALIColors.familyAccent
        case .extraShoppingLists: return ALIColors.shoppingAccent
        case .unlimitedReminders: return ALIColors.remindersAccent
        case .houseTasksCalendar, .houseTasksStats, .unlimitedHouseTasks: return ALIColors.houseTasksAccent
        case .economiaStats, .extraCategories, .financeArchive: return ALIColors.economiaAccent
        case .extraMembers: return ALIColors.peopleAccent
        case .board: return ALIColors.boardAccent
        }
    }

    var systemImage: String {
        switch self {
        case .historial: return "clock.arrow.circlepath"
        case .extraShoppingLists: return "cart.fill"
        case .unlimitedReminders: return "bell.fill"
        case .houseTasksCalendar: return "calendar"
        case .houseTasksStats: return "chart.bar.fill"
        case .unlimitedHouseTasks: return "checklist"
        case .economiaStats: return "chart.pie.fill"
        case .extraMembers: return "person.2.fill"
        case .extraCategories: return "tag.fill"
        case .financeArchive: return "archivebox.fill"
        case .board: return "pin.fill"
        }
    }
}
