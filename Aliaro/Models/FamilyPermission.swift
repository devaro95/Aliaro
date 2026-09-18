import SwiftUI

/// A specific thing a family member may or may not be allowed to do,
/// beyond just being in the group. The creator — and anyone promoted to
/// admin — always has every permission; for everyone else,
/// `FamilyMember.restrictedPermissions` lists which of these are turned
/// off. Grouped into `Section`s so `MemberPermissionsSheet` can render
/// them as labeled groups of toggles.
enum FamilyPermission: String, CaseIterable, Identifiable {
    case weeklyMenuEdit = "weekly_menu_edit"
    case calendarAdd = "calendar_add"
    case calendarEdit = "calendar_edit"
    case calendarDelete = "calendar_delete"
    case remindersCreate = "reminders_create"
    case remindersDelete = "reminders_delete"
    case tasksEdit = "tasks_edit"
    case tasksDelete = "tasks_delete"
    case financesAdd = "finances_add"
    case financesEdit = "finances_edit"
    case financesDelete = "finances_delete"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .weeklyMenuEdit: return "Edit the weekly menu"
        case .calendarAdd: return "Add calendar events"
        case .calendarEdit: return "Edit calendar events"
        case .calendarDelete: return "Delete calendar events"
        case .remindersCreate: return "Create reminders"
        case .remindersDelete: return "Delete reminders"
        case .tasksEdit: return "Edit house tasks"
        case .tasksDelete: return "Delete house tasks"
        case .financesAdd: return "Add transactions"
        case .financesEdit: return "Edit transactions"
        case .financesDelete: return "Delete transactions"
        }
    }

    var section: Section {
        switch self {
        case .weeklyMenuEdit: return .weeklyMenu
        case .calendarAdd, .calendarEdit, .calendarDelete: return .calendar
        case .remindersCreate, .remindersDelete: return .reminders
        case .tasksEdit, .tasksDelete: return .tasks
        case .financesAdd, .financesEdit, .financesDelete: return .finances
        }
    }

    /// Feature section a permission belongs to, for grouping in the UI.
    enum Section: String, CaseIterable, Identifiable {
        case weeklyMenu, calendar, reminders, tasks, finances

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .weeklyMenu: return "Weekly menu"
            case .calendar: return "Family calendar"
            case .reminders: return "Reminders"
            case .tasks: return "House tasks"
            case .finances: return "Finances"
            }
        }

        var accent: Color {
            switch self {
            case .weeklyMenu: return ALIColors.weeklyMenuAccent
            case .calendar: return ALIColors.familyAccent
            case .reminders: return ALIColors.remindersAccent
            case .tasks: return ALIColors.houseTasksAccent
            case .finances: return ALIColors.economiaAccent
            }
        }

        var permissions: [FamilyPermission] {
            FamilyPermission.allCases.filter { $0.section == self }
        }
    }
}
