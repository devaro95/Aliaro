import Foundation

/// A small, pre-computed snapshot of the data the home screen widgets
/// need, written by the main app (`WidgetSnapshotWriter`) to the shared
/// App Group container every time something relevant syncs, and read by
/// the widget extension at every timeline refresh. Widgets never talk to
/// Supabase or SwiftData directly — this file is the only bridge.
struct WidgetReminderItem: Codable, Identifiable {
    var id: UUID
    var title: String
    var fireDate: Date
    var note: String?
}

struct WidgetCalendarEventItem: Codable, Identifiable {
    var id: UUID
    var title: String
    var emoji: String
    var startDate: Date
    var endDate: Date
}

/// `mealType` keeps the same raw values as `MealType` in the app
/// ("comida"/"cena") so no translation layer is needed between the two.
struct WidgetMenuEntryItem: Codable, Identifiable {
    var id: String { mealType }
    var mealType: String
    var dishName: String
}

struct WidgetSnapshot: Codable {
    var familyName: String?
    var hasFamilyGroup: Bool
    var generatedAt: Date
    /// Upcoming reminders (today onward), soonest first, already capped.
    var reminders: [WidgetReminderItem]
    /// Every family event overlapping the month `monthAnchor` falls in —
    /// rebuilt whenever the app syncs, so a fresh widget refresh right
    /// after midnight on the 1st already sees the new month's events.
    var monthEvents: [WidgetCalendarEventItem]
    var monthAnchor: Date
    /// Today's planned dishes from the weekly menu, if any.
    var todayMenu: [WidgetMenuEntryItem]

    static let empty = WidgetSnapshot(
        familyName: nil, hasFamilyGroup: false, generatedAt: .now,
        reminders: [], monthEvents: [], monthAnchor: .now, todayMenu: []
    )
}

enum WidgetSnapshotStore {
    private static let fileName = "widget_snapshot.json"

    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    /// Called by the app after rebuilding the snapshot from SwiftData.
    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Called by the widget extension at every timeline refresh.
    static func load() -> WidgetSnapshot {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }
}
