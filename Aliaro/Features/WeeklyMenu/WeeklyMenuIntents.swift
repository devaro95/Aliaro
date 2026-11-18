import AppIntents
import Foundation
import SwiftData
import Supabase

/// Siri / Shortcuts actions to hear today's menu without opening the app
/// ("¿Qué hay de cena en Aliaro?"). Phrases live in `AliaroShortcuts`.
/// They run in the app's process in the background (no UI): they ask
/// Supabase for the family's menu, so the answer is up to date even if
/// another member changed it while the app was closed, and fall back to
/// the local SwiftData cache when offline or slow. Free for everyone.
struct TodayLunchIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's lunch"
    static let description = IntentDescription("Tells you what's for lunch today in your Aliaro menu.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = await TodayMenuLookup.answer(for: .lunch)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

struct TodayDinnerIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's dinner"
    static let description = IntentDescription("Tells you what's for dinner today in your Aliaro menu.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = await TodayMenuLookup.answer(for: .dinner)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

struct TodayMenuIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's menu"
    static let description = IntentDescription("Tells you today's lunch and dinner from your Aliaro menu.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = await TodayMenuLookup.answer(for: nil)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

/// Finds today's dishes and builds the sentence Siri says.
@MainActor
enum TodayMenuLookup {
    private struct MealDish {
        var mealType: String
        var name: String
    }

    /// Max wait for Supabase before answering from the local cache, so
    /// Siri never hangs on a bad connection.
    private static let remoteTimeout: Duration = .seconds(3)

    /// `meal == nil` = whole menu (lunch and dinner).
    static func answer(for meal: MealType?) async -> String {
        Track.event("menu_siri_asked", ["meal": meal.map { String(describing: $0) } ?? "both"])

        guard FamilySession.shared.hasJoinedFamily, let familyID = FamilySession.shared.familyID else {
            return String(localized: "Open Aliaro and join a family group to check the menu.")
        }

        let dishes = await remoteToday(familyID: familyID) ?? localToday()
        let lunch = dishes.first { $0.mealType == MealType.lunch.rawValue }?.name
        let dinner = dishes.first { $0.mealType == MealType.dinner.rawValue }?.name

        switch meal {
        case .lunch:
            if let lunch { return String(localized: "Today for lunch: \(lunch).") }
            return String(localized: "There's nothing planned for lunch today.")
        case .dinner:
            if let dinner { return String(localized: "Today for dinner: \(dinner).") }
            return String(localized: "There's nothing planned for dinner today.")
        case nil:
            switch (lunch, dinner) {
            case let (lunch?, dinner?):
                return String(localized: "Today for lunch: \(lunch), and for dinner: \(dinner).")
            case let (lunch?, nil):
                return String(localized: "Today for lunch: \(lunch). Dinner isn't planned yet.")
            case let (nil, dinner?):
                return String(localized: "Lunch isn't planned yet. Today for dinner: \(dinner).")
            case (nil, nil):
                return String(localized: "There's nothing on today's menu.")
            }
        }
    }

    /// Weekly menu today. MealPlanEntry.weekday: 0 = Monday ... 6 = Sunday
    /// (see WidgetSnapshotWriter). When the dated menu (`meal_plan_days`)
    /// lands, this and the two lookups below are the only places to change.
    private static var todayWeekday: Int {
        (Calendar.current.component(.weekday, from: .now) + 5) % 7
    }

    /// nil = Supabase failed or took longer than `remoteTimeout`.
    private static func remoteToday(familyID: UUID) async -> [MealDish]? {
        let weekday = todayWeekday
        let timeout = remoteTimeout
        let rows: [RemoteMealPlanEntry]? = await withTaskGroup(of: [RemoteMealPlanEntry]?.self) { group in
            group.addTask {
                try? await supabase
                    .from(RemoteMealPlanEntry.tableName)
                    .select()
                    .eq("family_id", value: familyID)
                    .eq("weekday", value: weekday)
                    .execute()
                    .value
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return rows?.map { MealDish(mealType: $0.meal_type, name: $0.dish_name) }
    }

    private static func localToday() -> [MealDish] {
        let weekday = todayWeekday
        let descriptor = FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.weekday == weekday })
        let entries = (try? AliaroApp.sharedModelContainer.mainContext.fetch(descriptor)) ?? []
        return entries.map { MealDish(mealType: $0.mealType, name: $0.dishName) }
    }
}
