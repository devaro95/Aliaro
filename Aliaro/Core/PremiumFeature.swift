import SwiftUI

/// A capability that can be toggled between free and premium from the
/// `premium_features` table in Supabase (`key` column matches `rawValue`
/// here) — Varo flips these remotely via SQL, no app update needed, and
/// every device picks up the change live through `PremiumConfig`.
enum PremiumFeature: String, CaseIterable, Identifiable {
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
    case cloudBackup = "cloud_backup"

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
        case .cloudBackup: return "Cloud backup"
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
        case .cloudBackup: return "icloud.and.arrow.up"
        }
    }
}
