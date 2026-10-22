import SwiftUI

/// "By person" view for the family calendar: a day matrix with one
/// column per family member and one row per hour. Each event is drawn in
/// the column of every person it's for, as a colored line spanning its
/// duration with the title next to it. Events for everyone appear in
/// every column. All-day events go in a strip above the hours.
struct FamilyCalendarPeopleView: View {
    let events: [FamilyEvent]
    let members: [FamilyMember]
    @Binding var selectedDay: Date?
    /// Static, purely visual render for the premium preview: no buttons,
    /// no inner scroll, no live "now" line. Only the parent scrolls.
    var isMock: Bool = false
    var onSelect: (FamilyEvent) -> Void

    @State private var availableWidth: CGFloat = 0

    private let hourHeight: CGFloat = 52
    private let gutterWidth: CGFloat = 40
    private let minColumnWidth: CGFloat = 92
    private let headerHeight: CGFloat = 56

    private var calendar: Calendar { Calendar.current }
    private var day: Date { calendar.startOfDay(for: selectedDay ?? .now) }
    private var dayEnd: Date { calendar.date(byAdding: .day, value: 1, to: day) ?? day }

    private static let everyoneID = UUID()

    private static let palette: [Color] = [
        ALIPalette.lavender, ALIPalette.mint, ALIPalette.coral, ALIPalette.sun,
        ALIPalette.rose, ALIPalette.pistachio, ALIPalette.apricot, ALIPalette.periwinkle
    ]

    // MARK: - Data

    private struct Column: Identifiable {
        let id: UUID
        let name: String
        let emoji: String?
        let color: Color
    }

    private var columns: [Column] {
        if members.isEmpty {
            return [Column(id: Self.everyoneID, name: String(localized: "Everyone"), emoji: nil, color: ALIColors.familyAccent)]
        }
        return members.enumerated().map { index, member in
            Column(id: member.id, name: member.name, emoji: member.emoji,
                   color: Self.palette[index % Self.palette.count])
        }
    }

    private var dayEvents: [FamilyEvent] {
        events.filter { $0.startDate < dayEnd && $0.endDate >= day }
    }

    private func isFor(_ event: FamilyEvent, _ column: Column) -> Bool {
        members.isEmpty || event.forEveryone || event.memberIDs.isEmpty || event.memberIDs.contains(column.id)
    }

    /// Events shown in the all-day strip: all-day ones, and timed ones
    /// covering the whole day (middle days of a multi-day event).
    private func isAllDayHere(_ event: FamilyEvent) -> Bool {
        event.isAllDay || (event.startDate <= day && event.endDate >= dayEnd.addingTimeInterval(-1))
    }

    private var timedEvents: [FamilyEvent] { dayEvents.filter { !isAllDayHere($0) } }
    private var allDayEvents: [FamilyEvent] { dayEvents.filter(isAllDayHere) }

    /// Visible hours: 7:00–22:00 by default, stretched to fit the day's events.
    private var hourRange: ClosedRange<Int> {
        var first = 7, last = 22
        for event in timedEvents {
            let start = max(event.startDate, day)
            let end = min(event.endDate, dayEnd)
            first = min(first, calendar.component(.hour, from: start))
            let endHour = end >= dayEnd ? 24 : calendar.component(.hour, from: end) + (calendar.component(.minute, from: end) > 0 ? 1 : 0)
            last = max(last, endHour)
        }
        return first...max(first + 1, last)
    }

    private func yOffset(for date: Date) -> CGFloat {
        let clamped = min(max(date, day), dayEnd)
        let hours = clamped.timeIntervalSince(day) / 3600
        return CGFloat(hours - Double(hourRange.lowerBound)) * hourHeight
    }

    private struct PlacedEvent: Identifiable {
        let event: FamilyEvent
        let lane: Int
        let lanes: Int
        var id: UUID { event.id }
    }

    /// Side-by-side lanes for overlapping events within a column.
    private func layout(_ items: [FamilyEvent]) -> [PlacedEvent] {
        let sorted = items.sorted { $0.startDate < $1.startDate }
        var result: [PlacedEvent] = []
        var cluster: [(FamilyEvent, Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(laneEnds.count, 1)
            result += cluster.map { PlacedEvent(event: $0.0, lane: $0.1, lanes: count) }
            cluster.removeAll(); laneEnds.removeAll()
        }

        for event in sorted {
            if event.startDate >= clusterEnd { flush() }
            if let free = laneEnds.firstIndex(where: { $0 <= event.startDate }) {
                laneEnds[free] = event.endDate
                cluster.append((event, free))
            } else {
                laneEnds.append(event.endDate)
                cluster.append((event, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, event.endDate)
        }
        flush()
        return result
    }

    private var columnWidth: CGFloat {
        let usable = availableWidth - gutterWidth
        guard usable > 0, !columns.isEmpty else { return minColumnWidth }
        return max(minColumnWidth, usable / CGFloat(columns.count))
    }

    // MARK: - Body

    var body: some View {
        ALICard(padding: EdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 12)) {
            VStack(spacing: 14) {
                dayHeader
                matrix
            }
        }
    }

    private var dayHeader: some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        let isToday = calendar.isDateInToday(day)

        if isMock {
            return AnyView(
                Text(formatter.string(from: day).capitalized)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .frame(maxWidth: .infinity, minHeight: 36)
            )
        }
        return AnyView(HStack {
            chevron("chevron.left", value: -1)
            Spacer()
            Button {
                selectedDay = calendar.startOfDay(for: .now)
            } label: {
                VStack(spacing: 2) {
                    Text(formatter.string(from: day).capitalized)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                    if !isToday {
                        Text("Go to today")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            chevron("chevron.right", value: 1)
        })
    }

    private func chevron(_ symbol: String, value: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDay = calendar.date(byAdding: .day, value: value, to: day)
            }
            Track.event("calendar_people_day_nav", ["direction": value > 0 ? "next" : "previous"])
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 36, height: 36)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var matrix: some View {
        let hasAllDay = !allDayEvents.isEmpty
        return HStack(alignment: .top, spacing: 0) {
            // Hour gutter (fixed, doesn't scroll sideways).
            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)
                if hasAllDay { allDayGutter }
                hourLabels
            }
            .frame(width: gutterWidth)

            if isMock {
                columnsRow(hasAllDay: hasAllDay)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    columnsRow(hasAllDay: hasAllDay)
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in availableWidth = width }
            }
        )
    }

    private func columnsRow(hasAllDay: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(columns) { column in
                VStack(spacing: 0) {
                    columnHeader(column)
                    if hasAllDay { allDayCell(column) }
                    timeColumn(column)
                }
                .frame(width: columnWidth)
            }
        }
    }

    /// A button normally; just the label in mock mode.
    @ViewBuilder
    private func tappable<Label: View>(_ action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        if isMock {
            label()
        } else {
            Button(action: action, label: label).buttonStyle(.plain)
        }
    }

    private func columnHeader(_ column: Column) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(column.color.opacity(0.35))
                if let emoji = column.emoji {
                    ALIIconView(icon: emoji, size: 16, fallback: ALIIcon.user)
                } else {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ALIColors.ink)
                }
            }
            .frame(width: 28, height: 28)
            Text(column.name)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .frame(height: headerHeight, alignment: .top)
    }

    private var allDayGutter: some View {
        Text("All day")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(ALIColors.mutedInk)
            .multilineTextAlignment(.center)
            .frame(height: allDayHeight)
    }

    private var allDayHeight: CGFloat {
        let maxCount = columns.map { column in allDayEvents.filter { isFor($0, column) }.count }.max() ?? 0
        return CGFloat(max(maxCount, 1)) * 24 + 8
    }

    private func allDayCell(_ column: Column) -> some View {
        VStack(spacing: 4) {
            ForEach(allDayEvents.filter { isFor($0, column) }, id: \.id) { event in
                tappable({ onSelect(event) }) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ALIColors.onAccent)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                        .background(color(for: event, in: column))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .frame(height: allDayHeight, alignment: .top)
        .overlay(alignment: .bottom) { Rectangle().fill(ALIColors.outline).frame(height: 1) }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(Array(hourRange), id: \.self) { hour in
                Text(String(format: "%02d:00", hour % 24))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(height: hour == hourRange.upperBound ? 0 : hourHeight, alignment: .top)
                    .offset(y: -6)
            }
        }
    }

    private var gridHeight: CGFloat { CGFloat(hourRange.count - 1) * hourHeight }

    private func timeColumn(_ column: Column) -> some View {
        let items = layout(timedEvents.filter { isFor($0, column) })
        let laneWidthBase = columnWidth - 6

        return ZStack(alignment: .topLeading) {
            // Hour grid lines.
            VStack(spacing: 0) {
                ForEach(0..<(hourRange.count - 1), id: \.self) { _ in
                    Rectangle().fill(ALIColors.outline).frame(height: 1)
                        .frame(height: hourHeight, alignment: .top)
                }
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(ALIColors.outline).frame(width: 1)
            }

            ForEach(items) { item in
                let top = yOffset(for: item.event.startDate)
                let height = max(yOffset(for: item.event.endDate) - top, 22)
                let laneWidth = laneWidthBase / CGFloat(item.lanes)
                eventBlock(item.event, column: column, height: height)
                    .frame(width: laneWidth - 2, height: height)
                    .offset(x: 3 + CGFloat(item.lane) * laneWidth, y: top)
            }

            if !isMock && calendar.isDateInToday(day) {
                nowLine
            }
        }
        .frame(width: columnWidth, height: gridHeight, alignment: .topLeading)
        .clipped()
    }

    private func eventBlock(_ event: FamilyEvent, column: Column, height: CGFloat) -> some View {
        let tint = color(for: event, in: column)
        let time: String = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "\(f.string(from: max(event.startDate, day))) – \(f.string(from: min(event.endDate, dayEnd)))"
        }()

        return tappable({
            Track.event("calendar_event_open", ["source": "people_view"])
            onSelect(event)
        }) {
            HStack(alignment: .top, spacing: 5) {
                Capsule().fill(tint).frame(width: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ALIColors.ink)
                        .lineLimit(height > 40 ? 2 : 1)
                    if height > 36 {
                        Text(time)
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(ALIColors.mutedInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.trailing, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tint.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// Personal events take the person's color; shared ones the calendar accent.
    private func color(for event: FamilyEvent, in column: Column) -> Color {
        (event.forEveryone || event.memberIDs.isEmpty) ? ALIColors.familyAccent : column.color
    }

    private var nowLine: some View {
        TimelineView(.everyMinute) { context in
            let y = yOffset(for: context.date)
            if y >= 0 && y <= gridHeight {
                Rectangle()
                    .fill(ALIColors.error)
                    .frame(height: 1.5)
                    .offset(y: y)
            }
        }
    }
}

/// Sample data for the "by person" view when it's opened as a premium
/// preview: three people with a believable day of plans.
enum FamilyCalendarPeopleDemoData {
    static let members: [FamilyMember] = HouseTasksDemoData.members

    /// Built once: recreating the sample events on every render gave them
    /// new ids each scroll frame, so the blocks kept re-animating.
    static let today: [FamilyEvent] = events(on: .now)

    static func events(on day: Date) -> [FamilyEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        func at(_ hour: Double) -> Date { start.addingTimeInterval(hour * 3600) }
        let ana = members[0].id, luis = members[1].id, marta = members[2].id

        return [
            FamilyEvent(title: String(localized: "Work"), startDate: at(9), endDate: at(15), emoji: ALIIcon.laptop, forEveryone: false, memberIDs: [ana]),
            FamilyEvent(title: String(localized: "Gym"), startDate: at(18.5), endDate: at(19.5), emoji: ALIIcon.gym, forEveryone: false, memberIDs: [ana]),
            FamilyEvent(title: String(localized: "School"), startDate: at(9), endDate: at(14), emoji: ALIIcon.school, forEveryone: false, memberIDs: [marta]),
            FamilyEvent(title: String(localized: "Football practice"), startDate: at(17), endDate: at(18.5), emoji: ALIIcon.sport, forEveryone: false, memberIDs: [marta]),
            FamilyEvent(title: String(localized: "Dentist"), startDate: at(10), endDate: at(11), emoji: ALIIcon.doctor, forEveryone: false, memberIDs: [luis]),
            FamilyEvent(title: String(localized: "Pick up Marta"), startDate: at(14), endDate: at(14.5), emoji: ALIIcon.car, forEveryone: false, memberIDs: [luis]),
            FamilyEvent(title: String(localized: "Shopping"), startDate: at(16), endDate: at(17), emoji: ALIIcon.cart, forEveryone: false, memberIDs: [luis, ana]),
            FamilyEvent(title: String(localized: "Family dinner"), startDate: at(21), endDate: at(22), emoji: ALIIcon.dining)
        ]
    }
}
