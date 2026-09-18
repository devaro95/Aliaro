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
            monthEvents = allEvents
                .filter { $0.startDate < monthInterval.end && $0.endDate >= monthInterval.start }
                .sorted { $0.startDate < $1.startDate }
                .map { WidgetCalendarEventItem(id: $0.id, title: $0.title, emoji: $0.emoji, startDate: $0.startDate, endDate: $0.endDate) }
        }

        // MealPlanEntry.weekday: 0 = Monday ... 6 = Sunday. Calendar's
        // `.weekday` component is always 1 = Sunday ... 7 = Saturday
        // regardless of locale/firstWeekday, hence the +5 offset.
        let weekdayComponent = calendar.component(.weekday, from: now)
        let todayWeekday = (weekdayComponent + 5) % 7
        let allMealPlanEntries = (try? modelContext.fetch(FetchDescriptor<MealPlanEntry>())) ?? []
        let mealOrder = ["comida", "cena"]
        let todayMenu = allMealPlanEntries
            .filter { $0.weekday == todayWeekday }
            .sorted { (mealOrder.firstIndex(of: $0.mealType) ?? 0) < (mealOrder.firstIndex(of: $1.mealType) ?? 0) }
            .map { WidgetMenuEntryItem(mealType: $0.mealType, dishName: $0.dishName) }

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
