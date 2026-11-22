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

/// Shared write path for menu slots (day + meal type, each with one or
/// more dishes): used by the day editor, "Add to menu" from a recipe and
/// week copies.
enum MenuWriter {
    /// The dishes of a slot, in order (`position`, then oldest first).
    static func entries(on date: Date, mealType: MealType, in entries: [MealPlanEntry]) -> [MealPlanEntry] {
        entries
            .filter { MenuCalendar.isSameDay($0.date, date) && $0.mealType == mealType.rawValue }
            .sorted { ($0.position, $0.updatedAt) < ($1.position, $1.updatedAt) }
    }

    static func dishes(on date: Date, mealType: MealType, in entries: [MealPlanEntry]) -> [DishSelection] {
        self.entries(on: date, mealType: mealType, in: entries).map { DishSelection(id: $0.dishID, name: $0.dishName) }
    }

    /// Makes the slot contain exactly `dishes`, in that order. Existing rows
    /// are reused by position (so the main dish keeps its row and its link
    /// with older app versions), extra ones are added and leftovers removed.
    @MainActor
    static func set(
        _ dishes: [DishSelection],
        date: Date,
        mealType: MealType,
        entries: [MealPlanEntry],
        modelContext: ModelContext,
        dataSync: AppDataSyncCoordinator,
        familyID: UUID?
    ) {
        let day = MenuCalendar.day(date)
        let existing = self.entries(on: day, mealType: mealType, in: entries)

        for (index, dish) in dishes.enumerated() {
            let entry: MealPlanEntry
            if index < existing.count {
                entry = existing[index]
                guard entry.dishID != dish.id || entry.dishName != dish.name || entry.position != index else { continue }
                entry.dishID = dish.id
                entry.dishName = dish.name
                entry.position = index
                entry.updatedAt = .now
            } else {
                entry = MealPlanEntry(date: day, mealType: mealType.rawValue, dishID: dish.id, dishName: dish.name, position: index)
                modelContext.insert(entry)
            }
            if let familyID { dataSync.pushMealPlanEntry(entry, familyID: familyID) }
        }
        for extra in existing.dropFirst(dishes.count) { remove(extra, modelContext: modelContext, dataSync: dataSync) }
    }

    /// Adds `dish` at the end of the slot (no-op if it's already there).
    @MainActor
    static func add(
        _ dish: DishSelection,
        date: Date,
        mealType: MealType,
        entries: [MealPlanEntry],
        modelContext: ModelContext,
        dataSync: AppDataSyncCoordinator,
        familyID: UUID?
    ) {
        var current = dishes(on: date, mealType: mealType, in: entries)
        guard !current.contains(where: { $0.id == dish.id }) else { return }
        current.append(dish)
        set(current, date: date, mealType: mealType, entries: entries, modelContext: modelContext, dataSync: dataSync, familyID: familyID)
    }

    @MainActor
    static func remove(_ entry: MealPlanEntry, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) {
        let entryID = entry.id
        modelContext.delete(entry)
        dataSync.deleteMealPlanEntry(id: entryID)
    }
}
