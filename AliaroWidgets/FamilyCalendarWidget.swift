import WidgetKit
import SwiftUI

struct FamilyCalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FamilyCalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> FamilyCalendarEntry {
        FamilyCalendarEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyCalendarEntry) -> Void) {
        completion(FamilyCalendarEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyCalendarEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let entry = FamilyCalendarEntry(date: .now, snapshot: snapshot)
        // The grid only depends on the day changing (today's highlight)
        // and the month rolling over — both happen at midnight. The app
        // itself re-writes the snapshot sooner whenever an event changes.
        var calendar = Calendar.current
        calendar.timeZone = .current
        let midnight = calendar.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

private struct MonthDay: Identifiable {
    let id: Date
    let date: Date
    let dayNumber: Int
    let inCurrentMonth: Bool
    let hasEvent: Bool
    let isToday: Bool
}

private func monthDays(anchor: Date, events: [WidgetCalendarEventItem]) -> [MonthDay] {
    var calendar = Calendar.current
    calendar.firstWeekday = 2 // Monday
    guard let monthInterval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
    let firstOfMonth = monthInterval.start
    let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
    let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
    guard let gridStart = calendar.date(byAdding: .day, value: -leadingEmpty, to: firstOfMonth) else { return [] }
    let daysInMonth = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
    let totalCells = Int((Double(leadingEmpty + daysInMonth) / 7.0).rounded(.up)) * 7
    let today = calendar.startOfDay(for: .now)

    return (0..<totalCells).compactMap { offset -> MonthDay? in
        guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
        let dayStart = calendar.startOfDay(for: date)
        let inMonth = calendar.isDate(date, equalTo: anchor, toGranularity: .month)
        let hasEvent = events.contains {
            calendar.startOfDay(for: $0.startDate) <= dayStart && dayStart <= calendar.startOfDay(for: $0.endDate)
        }
        return MonthDay(
            id: dayStart, date: date, dayNumber: calendar.component(.day, from: date),
            inCurrentMonth: inMonth, hasEvent: hasEvent, isToday: dayStart == today
        )
    }
}

struct FamilyCalendarWidgetView: View {
    var snapshot: WidgetSnapshot

    private let weekdaySymbols = ["L", "M", "X", "J", "V", "S", "D"]

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: snapshot.monthAnchor).capitalized
    }

    var body: some View {
        if !snapshot.hasFamilyGroup {
            VStack {
                Label("Calendario", systemImage: "calendar")
                    .font(.caption).bold()
                    .foregroundStyle(.blue)
                Spacer()
                Text("Únete a un grupo familiar en Aliaro")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let days = monthDays(anchor: snapshot.monthAnchor, events: snapshot.monthEvents)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            VStack(spacing: 5) {
                Text(monthTitle)
                    .font(.caption).bold()
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(days) { day in
                        VStack(spacing: 2) {
                            Text("\(day.dayNumber)")
                                .font(.system(size: 11, weight: day.isToday ? .bold : .regular))
                                .foregroundStyle(
                                    day.isToday ? .white : (day.inCurrentMonth ? .primary : .secondary.opacity(0.35))
                                )
                                .frame(width: 18, height: 18)
                                .background {
                                    if day.isToday {
                                        Circle().fill(Color.blue)
                                    }
                                }
                            Circle()
                                .fill(day.hasEvent ? Color.orange : Color.clear)
                                .frame(width: 3.5, height: 3.5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct FamilyCalendarWidget: Widget {
    let kind = "FamilyCalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FamilyCalendarProvider()) { entry in
            FamilyCalendarWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Calendario familiar")
        .description("El calendario de este mes con los eventos de la familia.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemLarge) {
    FamilyCalendarWidget()
} timeline: {
    FamilyCalendarEntry(date: .now, snapshot: .empty)
}
