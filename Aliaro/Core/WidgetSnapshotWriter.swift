import Foundation
import SwiftData
import WidgetKit

/// Builds a `WidgetSnapshot` from the current local SwiftData cache and
/// writes it to the shared App Group container for the home screen
/// widgets, then asks WidgetKit to refresh them. Called by
/// `AppDataSyncCoordinator` right after anything the widgets show
/// (reminders, calendar events, weekly menu) changes — locally or from
/// another device via real time.
@MainActor
enum WidgetSnapshotWriter {
    static func refresh(modelContext: ModelContext) {
        let calendar = Calendar.current
        let now = Date()

        let allReminders = (try? modelContext.fetch(FetchDescriptor<Reminder>())) ?? []
        let upcomingReminders = allReminders
            .filter { $0.fireDate >= calendar.startOfDay(for: now) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(8)
            .map { WidgetReminderItem(id: $0.id, title: $0.title, fireDate: $0.fireDate, note: $0.note) }

        var monthEvents: [WidgetCalendarEventItem] = []
        let monthAnchor = calendar.dateInterval(of: .month, for: now)?.start ?? now
        if let monthInterval = calendar.dateInterval(of: .month, for: now) {
            let allEvents = (try? modelContext.fetch(FetchDescriptor<FamilyEvent>())) ?? []
            // Repetitions get their own id so the widget's lists stay unique.
            monthEvents = allEvents.flatMap { event in
                event.occurrences(in: monthInterval).enumerated().map { index, occ in
                    WidgetCalendarEventItem(id: index == 0 ? event.id : UUID(), title: event.title, emoji: event.emoji, startDate: occ.start, endDate: occ.end)
                }
            }
            .sorted { $0.startDate < $1.startDate }
        }

        let allMealPlanEntries = (try? modelContext.fetch(FetchDescriptor<MealPlanEntry>())) ?? []
        // One item per meal; several dishes read as "Lentils · Salad".
        let todayMenu = MealType.allCases.compactMap { mealType -> WidgetMenuEntryItem? in
            let dishes = MenuWriter.dishes(on: now, mealType: mealType, in: allMealPlanEntries)
            guard !dishes.isEmpty else { return nil }
            return WidgetMenuEntryItem(mealType: mealType.rawValue, dishName: dishes.map(\.name).joined(separator: " · "))
        }

        let snapshot = WidgetSnapshot(
            familyName: FamilySession.shared.familyName,
            hasFamilyGroup: FamilySession.shared.hasJoinedFamily,
            generatedAt: now,
            reminders: Array(upcomingReminders),
            monthEvents: monthEvents,
            monthAnchor: monthAnchor,
            todayMenu: todayMenu
        )
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
