import WidgetKit
import SwiftUI

struct RemindersEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct RemindersProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemindersEntry {
        RemindersEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (RemindersEntry) -> Void) {
        completion(RemindersEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemindersEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let entry = RemindersEntry(date: .now, snapshot: snapshot)
        // Refresh shortly after the next reminder fires, so it drops off
        // the list, otherwise at least once an hour.
        let afterNextReminder = snapshot.reminders.first?.fireDate.addingTimeInterval(60)
        let fallback = Date().addingTimeInterval(3600)
        let nextRefresh = max(afterNextReminder ?? fallback, Date().addingTimeInterval(300))
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct RemindersWidgetView: View {
    var snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var maxItems: Int {
        switch family {
        case .systemSmall: return 3
        default: return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Recordatorios", systemImage: "bell.fill")
                .font(.caption).bold()
                .foregroundStyle(.orange)

            if !snapshot.hasFamilyGroup {
                emptyState("Únete a un grupo familiar en Aliaro")
            } else if snapshot.reminders.isEmpty {
                emptyState("Sin recordatorios próximos")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.reminders.prefix(maxItems)) { reminder in
                        HStack(alignment: .top, spacing: 6) {
                            Text(reminder.fireDate, style: .time)
                                .font(.caption2).monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(reminder.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        Spacer()
        HStack {
            Spacer()
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        Spacer()
    }
}

struct RemindersWidget: Widget {
    let kind = "RemindersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RemindersProvider()) { entry in
            RemindersWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Recordatorios")
        .description("Tus próximos recordatorios de Aliaro.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    RemindersWidget()
} timeline: {
    RemindersEntry(date: .now, snapshot: .empty)
}
