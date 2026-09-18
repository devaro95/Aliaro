import Foundation
import SwiftUI

/// Days of the week for the menu, in fixed Monday-to-Sunday order.
enum Weekday: Int, CaseIterable, Identifiable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var shortLabel: LocalizedStringKey {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }
}

/// Meal type within a menu day.
/// Note: raw values ("comida"/"cena") are stored and synced with Supabase — kept as-is for data compatibility.
enum MealType: String, CaseIterable, Identifiable {
    case lunch = "comida"
    case dinner = "cena"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }
}

/// Dish chosen for a lunch/dinner slot — a lightweight copy of a
/// catalog `Dish`, so the UI doesn't have to carry the full model around.
struct DishSelection: Equatable {
    let id: UUID
    let name: String
}
