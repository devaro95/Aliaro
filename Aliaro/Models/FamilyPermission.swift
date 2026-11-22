import SwiftUI

/// A specific thing a family member may or may not be allowed to do,
/// beyond just being in the group. The creator — and anyone promoted to
/// admin — always has every permission; for everyone else,
/// `FamilyMember.restrictedPermissions` lists which of these are turned
/// off. Grouped into `Section`s so `MemberPermissionsSheet` can render
/// them as labeled groups of toggles.
/// Keep in sync with the `update-member-permissions` edge function whitelist.
enum FamilyPermission: String, CaseIterable, Identifiable {
    case weeklyMenuEdit = "weekly_menu_edit"
    case weeklyMenuClear = "weekly_menu_clear"
    case recipesAdd = "recipes_add"
    case recipesEdit = "recipes_edit"
    case recipesDelete = "recipes_delete"
    case calendarAdd = "calendar_add"
    case calendarEdit = "calendar_edit"
    case calendarDelete = "calendar_delete"
    case remindersCreate = "reminders_create"
    case remindersEdit = "reminders_edit"
    case remindersDelete = "reminders_delete"
    case tasksCreate = "tasks_create"
    case tasksEdit = "tasks_edit"
    case tasksDelete = "tasks_delete"
    case financesAdd = "finances_add"
    case financesEdit = "finances_edit"
    case financesDelete = "finances_delete"
    case financesArchive = "finances_archive"
    case financesCategories = "finances_categories"
    case shoppingAdd = "shopping_add"
    case shoppingEdit = "shopping_edit"
    case shoppingDelete = "shopping_delete"
    case boardAdd = "board_add"
    case boardEdit = "board_edit"
    case boardDelete = "board_delete"
    case wifiEdit = "wifi_edit"
    case wifiDelete = "wifi_delete"
    case placesAdd = "places_add"
    case placesEdit = "places_edit"
    case placesDelete = "places_delete"
    case placesCategories = "places_categories"
    case worldMapEdit = "world_map_edit"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .weeklyMenuEdit: return "Edit the weekly menu"
        case .weeklyMenuClear: return "Clear the week"
        case .recipesAdd: return "Add recipes"
        case .recipesEdit: return "Edit recipes"
        case .recipesDelete: return "Delete recipes"
        case .calendarAdd: return "Add calendar events"
        case .calendarEdit: return "Edit calendar events"
        case .calendarDelete: return "Delete calendar events"
        case .remindersCreate: return "Create reminders"
        case .remindersEdit: return "Edit reminders"
        case .remindersDelete: return "Delete reminders"
        case .tasksCreate: return "Create house tasks"
        case .tasksEdit: return "Edit house tasks"
        case .tasksDelete: return "Delete house tasks"
        case .financesAdd: return "Add transactions"
        case .financesEdit: return "Edit transactions"
        case .financesDelete: return "Delete transactions"
        case .financesArchive: return "Archive finances"
        case .financesCategories: return "Create expense categories"
        case .shoppingAdd: return "Add items and lists"
        case .shoppingEdit: return "Edit items and rename lists"
        case .shoppingDelete: return "Delete items and lists"
        case .boardAdd: return "Pin notes"
        case .boardEdit: return "Edit notes"
        case .boardDelete: return "Delete notes"
        case .wifiEdit: return "Add and edit networks"
        case .wifiDelete: return "Delete networks"
        case .placesAdd: return "Add places"
        case .placesEdit: return "Edit places"
        case .placesDelete: return "Delete places"
        case .placesCategories: return "Manage place categories"
        case .worldMapEdit: return "Mark visited countries"
        }
    }

    var section: Section {
        switch self {
        case .weeklyMenuEdit, .weeklyMenuClear: return .weeklyMenu
        case .recipesAdd, .recipesEdit, .recipesDelete: return .recipes
        case .calendarAdd, .calendarEdit, .calendarDelete: return .calendar
        case .remindersCreate, .remindersEdit, .remindersDelete: return .reminders
        case .tasksCreate, .tasksEdit, .tasksDelete: return .tasks
        case .financesAdd, .financesEdit, .financesDelete, .financesArchive, .financesCategories: return .finances
        case .shoppingAdd, .shoppingEdit, .shoppingDelete: return .shopping
        case .boardAdd, .boardEdit, .boardDelete: return .board
        case .wifiEdit, .wifiDelete: return .wifi
        case .placesAdd, .placesEdit, .placesDelete, .placesCategories: return .places
        case .worldMapEdit: return .worldMap
        }
    }

    /// Feature section a permission belongs to, for grouping in the UI.
    enum Section: String, CaseIterable, Identifiable {
        case weeklyMenu, recipes, shopping, calendar, reminders, tasks, board, finances, wifi, places, worldMap

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .weeklyMenu: return "Weekly menu"
            case .recipes: return "Recipes"
            case .shopping: return "Lists"
            case .board: return "Board"
            case .calendar: return "Family calendar"
            case .reminders: return "Reminders"
            case .tasks: return "House tasks"
            case .finances: return "Finances"
            case .wifi: return "Wi-Fi"
            case .places: return "Places"
            case .worldMap: return "World map"
            }
        }

        var accent: Color {
            switch self {
            case .weeklyMenu: return ALIColors.weeklyMenuAccent
            case .recipes: return ALIColors.recipesAccent
            case .shopping: return ALIColors.shoppingAccent
            case .board: return ALIColors.boardAccent
            case .calendar: return ALIColors.familyAccent
            case .reminders: return ALIColors.remindersAccent
            case .tasks: return ALIColors.houseTasksAccent
            case .finances: return ALIColors.economiaAccent
            case .wifi: return ALIColors.wifiAccent
            case .places: return ALIColors.placesAccent
            case .worldMap: return ALIColors.worldMapAccent
            }
        }

        var permissions: [FamilyPermission] {
            FamilyPermission.allCases.filter { $0.section == self }
        }
    }
}
