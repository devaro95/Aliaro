import Foundation
import SwiftData

/// A planned meal in the weekly menu: a day of the week (0 = Monday
/// ... 6 = Sunday) and a type ("lunch" or "dinner") with the chosen dish. It's
/// a recurring template, not a specific calendar day — it gets reused
/// and edited week after week. `dishID` references the source `Dish` (not
/// a SwiftData relationship) — `dishName` is copied so the entry stays
/// readable even if the catalog dish changes or is deleted.
@Model
final class MealPlanEntry {
    var id: UUID
    var weekday: Int
    var mealType: String
    var dishID: UUID
    var dishName: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        weekday: Int,
        mealType: String,
        dishID: UUID,
        dishName: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.weekday = weekday
        self.mealType = mealType
        self.dishID = dishID
        self.dishName = dishName
        self.updatedAt = updatedAt
    }
}
