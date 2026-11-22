import Foundation
import SwiftData
import SwiftUI

/// Date helpers for the menu. Weeks always run Monday to Sunday,
/// whatever the device locale says, to match the backend bridge.
enum MenuCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        calendar.locale = .current
        return calendar
    }

    static func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static var today: Date { day(.now) }

    static func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? day(date)
    }

    static func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? day(date)
    }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func adding(months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// The 7 days of the week that starts on `start` (a Monday).
    static func days(ofWeek start: Date) -> [Date] {
        (0..<7).map { adding(days: $0, to: start) }
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    /// Monday-first single-letter weekday symbols for the month grid.
    static var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols // Sunday first
        return Array(symbols[1...]) + [symbols[0]]
    }

    // MARK: Supabase `date` column ("yyyy-MM-dd", local day)

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(_ date: Date) -> String {
        keyFormatter.timeZone = .current
        return keyFormatter.string(from: date)
    }

    static func date(fromKey key: String) -> Date? {
        keyFormatter.timeZone = .current
        return keyFormatter.date(from: String(key.prefix(10))).map(day)
    }
}

/// A day of the menu, usable as a sheet item.
struct MenuDay: Identifiable, Hashable {
    let date: Date
    var id: Date { date }
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

/// Shared write path for menu slots (one dish per day + meal type):
/// used by the day editor, "Add to menu" from a recipe and week copies.
enum MenuWriter {
    @MainActor
    static func set(
        _ dish: DishSelection?,
        date: Date,
        mealType: MealType,
        entries: [MealPlanEntry],
        modelContext: ModelContext,
        dataSync: AppDataSyncCoordinator,
        familyID: UUID?
    ) {
        let day = MenuCalendar.day(date)
        let existing = entries.filter { MenuCalendar.isSameDay($0.date, day) && $0.mealType == mealType.rawValue }

        if let dish {
            let entry: MealPlanEntry
            if let first = existing.first {
                guard first.dishID != dish.id || first.dishName != dish.name else { return }
                first.dishID = dish.id
                first.dishName = dish.name
                first.updatedAt = .now
                entry = first
            } else {
                entry = MealPlanEntry(date: day, mealType: mealType.rawValue, dishID: dish.id, dishName: dish.name)
                modelContext.insert(entry)
            }
            if let familyID { dataSync.pushMealPlanEntry(entry, familyID: familyID) }
            // Leftover duplicates from older versions of the slot.
            for extra in existing.dropFirst() { remove(extra, modelContext: modelContext, dataSync: dataSync) }
        } else {
            for entry in existing { remove(entry, modelContext: modelContext, dataSync: dataSync) }
        }
    }

    @MainActor
    static func remove(_ entry: MealPlanEntry, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) {
        let entryID = entry.id
        modelContext.delete(entry)
        dataSync.deleteMealPlanEntry(id: entryID)
    }
}
