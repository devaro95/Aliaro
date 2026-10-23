import Foundation
import SwiftData

/// A planned meal on a specific calendar day: a date (local start of day)
/// and a type ("comida"/"cena") with the chosen dish. Synced with the
/// `meal_plan_days` table. `dishID` references the source `Dish` (not a
/// SwiftData relationship) — `dishName` is copied so the entry stays
/// readable even if the catalog dish changes or is deleted.
///
/// Note: older app versions used a recurring Monday-to-Sunday template
/// (`weekday`, table `meal_plan_entries`). Supabase bridges that table
/// with the current week of `meal_plan_days`, so both versions coexist.
@Model
final class MealPlanEntry {
    var id: UUID
    /// Local start of day. Default only exists for SwiftData's lightweight
    /// migration from the old `weekday` model; the next sync overwrites it.
    var date: Date = Date.distantPast
    var mealType: String
    var dishID: UUID
    var dishName: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        mealType: String,
        dishID: UUID,
        dishName: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = MenuCalendar.day(date)
        self.mealType = mealType
        self.dishID = dishID
        self.dishName = dishName
        self.updatedAt = updatedAt
    }
}
