import WidgetKit
import SwiftUI

struct TodayMenuEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodayMenuProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayMenuEntry {
        TodayMenuEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayMenuEntry) -> Void) {
        completion(TodayMenuEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayMenuEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let entry = TodayMenuEntry(date: .now, snapshot: snapshot)
        var calendar = Calendar.current
        calendar.timeZone = .current
        let midnight = calendar.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct TodayMenuWidgetView: View {
    var snapshot: WidgetSnapshot

    private func dish(for mealType: String) -> String? {
        snapshot.todayMenu.first { $0.mealType == mealType }?.dishName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's menu", systemImage: "fork.knife")
                .font(.caption).bold()
                .foregroundStyle(.green)

            if !snapshot.hasFamilyGroup {
                Spacer()
                HStack {
                    Spacer()
                    Text("Join a family group in Aliaro")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                Spacer()
            } else {
                mealRow(icon: "sun.max.fill", label: "Lunch", dish: dish(for: "comida"))
                mealRow(icon: "moon.stars.fill", label: "Dinner", dish: dish(for: "cena"))
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func mealRow(icon: String, label: LocalizedStringKey, dish: String?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Group { if let dish { Text(dish) } else { Text("Not planned") } }.font(.caption).lineLimit(1)
            }
        }
    }
}

struct TodayMenuWidget: Widget {
    let kind = "TodayMenuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayMenuProvider()) { entry in
            TodayMenuWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today's menu")
        .description("Today's lunch and dinner from your Aliaro weekly menu.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    TodayMenuWidget()
} timeline: {
    TodayMenuEntry(date: .now, snapshot: .empty)
}
