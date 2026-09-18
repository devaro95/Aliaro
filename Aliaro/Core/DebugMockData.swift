import Foundation
import SwiftData

#if DEBUG
/// Fills the local database with realistic sample content so every tab
/// looks good for App Store screenshots. Debug builds only, and purely
/// local (SwiftData) — nothing here is pushed to Supabase, so it never
/// reaches other devices in the group or the real backend.
enum DebugMockData {
    @MainActor
    static func seed(modelContext: ModelContext) {
        let calendar = Calendar.current

        // Extra family members, if there aren't any others yet — nicer
        // for screenshots that show who did what.
        var members = (try? modelContext.fetch(FetchDescriptor<FamilyMember>())) ?? []
        if members.count <= 1 {
            let extras: [(String, String)] = [("Lucía", "👩"), ("Marcos", "🧑"), ("Nora", "👧")]
            for (name, emoji) in extras {
                let member = FamilyMember(name: name, emoji: emoji, isCurrentDevice: false)
                modelContext.insert(member)
                members.append(member)
            }
        }

        // Weekly menu: dishes + a full week of lunch/dinner.
        let dishNames = ["Lentil stew", "Grilled chicken", "Tomato pasta", "Veggie omelette", "Baked salmon", "Rice & beans", "Caesar salad", "Paella", "Chicken curry", "Pumpkin soup"]
        var dishes: [Dish] = []
        for name in dishNames {
            let dish = Dish(name: name)
            modelContext.insert(dish)
            dishes.append(dish)
        }
        for weekday in 0...6 {
            // Stored raw values match Supabase ("comida"/"cena"), not the
            // English `MealType` case names — see `MealType` in
            // WeeklyMenu+Support.swift.
            for mealType in [MealType.lunch.rawValue, MealType.dinner.rawValue] {
                guard let dish = dishes.randomElement() else { continue }
                modelContext.insert(MealPlanEntry(weekday: weekday, mealType: mealType, dishID: dish.id, dishName: dish.name))
            }
        }

        // Grocery catalog + active shopping list.
        let groceryNames = ["Milk", "Eggs", "Bread", "Tomatoes", "Chicken breast", "Rice", "Olive oil", "Toilet paper"]
        var groceryItems: [GroceryItem] = []
        for name in groceryNames {
            let item = GroceryItem(name: name)
            modelContext.insert(item)
            groceryItems.append(item)
        }
        let existingLists = (try? modelContext.fetch(FetchDescriptor<ShoppingList>())) ?? []
        let list: ShoppingList
        if let first = existingLists.first {
            list = first
        } else {
            list = ShoppingList(name: "Shopping list", position: 0)
            modelContext.insert(list)
        }
        // 3 pending (unchecked) + 5 already bought (checked).
        for (index, item) in groceryItems.enumerated() {
            modelContext.insert(ShoppingListEntry(itemID: item.id, listID: list.id, name: item.name, isChecked: index >= 3))
        }

        // House tasks + a bit of "done" history.
        let taskDefs: [(String, Int?)] = [("Dishwasher", 1), ("Laundry", 3), ("Vacuum", 4), ("Take out trash", 2), ("Change bedsheets", 7), ("Clean bathroom", 5)]
        for (name, interval) in taskDefs {
            let creator = members.randomElement()
            let task = HouseTask(name: name, intervalDays: interval, createdByID: creator?.id, createdByName: creator?.name)
            modelContext.insert(task)
            for i in 0..<Int.random(in: 1...3) {
                let logger = members.randomElement()
                modelContext.insert(HouseTaskLog(
                    taskID: task.id,
                    taskName: task.name,
                    completedAt: calendar.date(byAdding: .day, value: -(i + 1) * (interval ?? 3), to: .now) ?? .now,
                    createdByID: logger?.id,
                    createdByName: logger?.name
                ))
            }
        }

        // Calendar events.
        let eventDefs: [(String, String, Int, Int, Int)] = [
            ("Dentist appointment", "🦷", 1, 9, 10),
            ("Family dinner", "🍽️", 3, 20, 22),
            ("Mia's birthday", "🎂", 6, 0, 24),
            ("Weekend trip", "🚗", 10, 0, 48),
            ("Parent-teacher meeting", "🏫", 14, 17, 18)
        ]
        for (title, emoji, daysFromNow, startHourOffset, durationHours) in eventDefs {
            let baseDay = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: .now)) ?? .now
            let start = calendar.date(byAdding: .hour, value: startHourOffset, to: baseDay) ?? baseDay
            let end = calendar.date(byAdding: .hour, value: durationHours, to: start) ?? start
            let creator = members.randomElement()
            modelContext.insert(FamilyEvent(title: title, startDate: start, endDate: end, emoji: emoji, createdByID: creator?.id, createdByName: creator?.name))
        }

        // Reminders.
        let reminderDefs: [(String, Int)] = [("Take out the recycling", 1), ("Water the plants", 2), ("Pay the rent", 5)]
        for (title, daysFromNow) in reminderDefs {
            let fireDate = calendar.date(byAdding: .day, value: daysFromNow, to: .now) ?? .now
            let creator = members.randomElement()
            modelContext.insert(Reminder(title: title, fireDate: fireDate, notifyEveryone: true, createdByID: creator?.id, createdByName: creator?.name))
        }

        // Expense categories (defaults, if missing) + a handful of expenses.
        var categories = (try? modelContext.fetch(FetchDescriptor<ExpenseCategory>())) ?? []
        if categories.isEmpty {
            for preset in ExpenseCategory.defaults {
                let category = ExpenseCategory(name: preset.name, emoji: preset.emoji, isDefault: true)
                modelContext.insert(category)
                categories.append(category)
            }
        }
        let expenseDefs: [(String, Double, Bool, Int)] = [
            ("Supermarket run", 84.30, false, 1),
            ("Electricity bill", 62.10, false, 1),
            ("Movie night", 28.00, false, 2),
            ("Gas", 45.50, false, 1),
            ("New couch", 210.00, false, 2)
        ]
        for (name, amount, isIncome, categoryCount) in expenseDefs {
            let payer = members.randomElement()
            let categoryIDs = Array(categories.shuffled().prefix(categoryCount)).map(\.id)
            modelContext.insert(Expense(
                name: name,
                amount: amount,
                isIncome: isIncome,
                personID: payer?.id ?? UUID(),
                personName: payer?.name ?? "You",
                categoryIDs: categoryIDs,
                occurredAt: calendar.date(byAdding: .day, value: -Int.random(in: 0...10), to: .now) ?? .now
            ))
        }

        try? modelContext.save()
    }
}
#endif
