import SwiftUI

/// Monthly calendar view for "Family": navigates month by month.
/// Month grid with the events written in each day, like Google Calendar:
/// up to `maxLanes` small labels per day in the event's color. Multi-day
/// events are one continuous label across the days they span (same row on
/// every day, title at the start of each week), single-day ones fill the
/// free rows; what doesn't fit shows as "+N".
/// Tapping a day selects it to see its detail below.
struct FamilyCalendarMonthView: View {
    let events: [FamilyEvent]
    @Binding var selectedDay: Date?
    /// Month on screen (owned by the screen, for the color legend).
    @Binding var displayedMonth: Date

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth).capitalized
    }

    /// Days to show in the grid (6 weeks, starting on Monday),
    /// including padding from adjacent months.
    private var gridDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstOfMonth = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstOfMonth) // 1 = Sunday
        let leadingEmpty = (weekday + 5) % 7 // converts to a week starting on Monday
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingEmpty, to: firstOfMonth) else { return [] }

        var days: [Date] = []
        var current = gridStart
        for _ in 0..<42 {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return days
    }

    /// Events (and repetitions) overlapping the visible grid.
    private var gridEvents: [FamilyEvent] {
        guard let first = gridDays.first, let last = gridDays.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        return events.expanded(in: DateInterval(start: first, end: end))
    }

    /// Events that occur entirely on that day (for the ring around the number).
    private func singleDayEvents(on day: Date, in gridEvents: [FamilyEvent]) -> [FamilyEvent] {
        gridEvents.filter { event in
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(for: event.endDate)
            return start == end && calendar.isDate(day, inSameDayAs: event.startDate)
        }
    }

    static let maxLanes = 3

    /// A multi-day event placed in a lane, as grid indexes (inclusive).
    struct LaneBar {
        let lane: Int
        let first: Int
        let last: Int
        let color: Color
        let title: String
    }

    /// Multi-day events in lanes for the whole grid: earlier (and longer)
    /// ones first, each in the first lane free for all its days, so it keeps
    /// the same lane across weeks. Also how many don't fit, per day.
    private func laneLayout(in gridEvents: [FamilyEvent]) -> LaneLayout {
        let days = gridDays.map { calendar.startOfDay(for: $0) }
        guard let gridStart = days.first else { return LaneLayout(bars: [], hidden: []) }
        let lastIndex = days.count - 1

        struct Span {
            let title: String
            let color: String?
            let first: Int
            let last: Int
        }
        var spans: [Span] = []
        for event in gridEvents where !calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
            let startOffset = calendar.dateComponents([.day], from: gridStart, to: calendar.startOfDay(for: event.startDate)).day ?? 0
            let endOffset = calendar.dateComponents([.day], from: gridStart, to: calendar.startOfDay(for: event.endDate)).day ?? 0
            let first = max(0, startOffset)
            let last = min(lastIndex, endOffset)
            if first <= last { spans.append(Span(title: event.title, color: event.color, first: first, last: last)) }
        }
        spans.sort { lhs, rhs in
            if lhs.first != rhs.first { return lhs.first < rhs.first }
            return (lhs.last - lhs.first) > (rhs.last - rhs.first)
        }

        var laneEnds: [Int] = [] // last grid index used by each lane
        var bars: [LaneBar] = []
        var hidden = Array(repeating: 0, count: days.count)
        for span in spans {
            let lane: Int
            if let free = laneEnds.firstIndex(where: { $0 < span.first }) {
                lane = free
                laneEnds[free] = span.last
            } else {
                lane = laneEnds.count
                laneEnds.append(span.last)
            }
            if lane < Self.maxLanes {
                let color = ALIItemColors.color(span.color, fallback: ALIColors.familyAccent)
                bars.append(LaneBar(lane: lane, first: span.first, last: span.last, color: color, title: span.title))
            } else {
                for i in span.first...span.last { hidden[i] += 1 }
            }
        }
        return LaneLayout(bars: bars, hidden: hidden)
    }

    struct LaneLayout {
        let bars: [LaneBar]
        /// Multi-day events that didn't fit in the lanes, per grid day.
        let hidden: [Int]

        func bar(lane: Int, at index: Int) -> LaneBar? {
            bars.first(where: { $0.lane == lane && $0.first <= index && index <= $0.last })
        }
    }

    private func isInDisplayedMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
    }

    var body: some View {
        ALICard {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                dayGrid
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            monthStepButton(systemImage: "chevron.left") { shiftMonth(by: -1) }
            Spacer()
            // Like the "by person" view: tapping the title goes back to today;
            // "Go to today" shows when you're elsewhere.
            let today = calendar.startOfDay(for: .now)
            let atToday = calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
                && (selectedDay.map { calendar.isDate($0, inSameDayAs: today) } ?? true)
            Button {
                Track.event("calendar_go_today", ["screen": "calendar"])
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayedMonth = today
                    selectedDay = today
                }
            } label: {
                VStack(spacing: 2) {
                    Text(monthTitle)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                    if !atToday {
                        Text("Go to today")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            monthStepButton(systemImage: "chevron.right") { shiftMonth(by: 1) }
        }
    }

    private func monthStepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 32, height: 32)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        let symbols = Calendar.autoupdatingCurrent.veryShortStandaloneWeekdaySymbols
        let mondayFirst = Array(symbols[1...] + symbols[..<1])
        return HStack {
            ForEach(Array(mondayFirst.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        // Expanded once per render (repetitions included), then shared by every cell.
        let events = gridEvents
        let layout = laneLayout(in: events)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { index, day in
                dayCell(day, index: index, layout: layout, events: events)
            }
        }
    }

    /// What goes in each of a day's rows: a multi-day bar (fixed row) or a
    /// single-day event (first free rows); plus how many didn't fit.
    private func slots(for index: Int, day: Date, layout: LaneLayout, events: [FamilyEvent]) -> (rows: [DaySlot?], more: Int) {
        var rows: [DaySlot?] = Array(repeating: nil, count: Self.maxLanes)
        for lane in 0..<Self.maxLanes {
            if let bar = layout.bar(lane: lane, at: index) { rows[lane] = .bar(bar) }
        }
        var more = layout.hidden.indices.contains(index) ? layout.hidden[index] : 0
        for event in singleDayEvents(on: day, in: events) {
            if let free = rows.firstIndex(where: { $0 == nil }) {
                rows[free] = .single(title: event.title, color: ALIItemColors.color(event.color, fallback: ALIColors.familyAccent))
            } else {
                more += 1
            }
        }
        return (rows, more)
    }

    enum DaySlot {
        case bar(LaneBar)
        case single(title: String, color: Color)
    }

    private func dayCell(_ day: Date, index: Int, layout: LaneLayout, events: [FamilyEvent]) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let inMonth = isInDisplayedMonth(day)
        let column = index % 7
        let content = slots(for: index, day: day, layout: layout, events: events)

        return Button {
            Track.event("calendar_day_tap", ["screen": "calendar", "is_today": Calendar.current.isDateInToday(day)])
            withAnimation(.easeInOut(duration: 0.15)) { selectedDay = day }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday || isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? ALIColors.onAccent : (isToday ? ALIColors.onAccent : (inMonth ? ALIColors.ink : ALIColors.mutedInk.opacity(0.4))))
                    .frame(width: 22, height: 22)
                    .background(isSelected ? ALIColors.familyAccent : (isToday ? ALIColors.primary : Color.clear), in: Circle())
                    .padding(.top, 3)

                ForEach(0..<Self.maxLanes, id: \.self) { row in
                    slotView(content.rows[row], index: index, column: column)
                }

                Text(content.more > 0 ? "+\(content.more)" : " ")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ALIColors.mutedInk)
                    .frame(height: 10)
            }
            .opacity(inMonth ? 1 : 0.45)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, 2)
            .background(isSelected ? ALIColors.familyAccent.opacity(0.12) : Color.clear)
            .overlay(alignment: .top) { Rectangle().fill(ALIColors.outline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One row of a day: an event label in its color. A multi-day event's
    /// pieces join across days (title only where it starts or a week starts).
    @ViewBuilder
    private func slotView(_ slot: DaySlot?, index: Int, column: Int) -> some View {
        switch slot {
        case .bar(let bar):
            let isStart = index == bar.first || column == 0
            let isEnd = index == bar.last || column == 6
            label(isStart ? bar.title : "", color: bar.color, roundLeading: isStart, roundTrailing: isEnd)
                .padding(.leading, index == bar.first ? 2 : 0)
                .padding(.trailing, index == bar.last ? 2 : 0)
        case .single(let title, let color):
            label(title, color: color, roundLeading: true, roundTrailing: true)
                .padding(.horizontal, 2)
        case nil:
            Color.clear.frame(height: 14)
        }
    }

    private func label(_ title: String, color: Color, roundLeading: Bool, roundTrailing: Bool) -> some View {
        HStack(spacing: 0) {
            if roundLeading {
                Rectangle().fill(color).frame(width: 2)
            }
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ALIColors.onAccent)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 3)
            Spacer(minLength: 0)
        }
        .frame(height: 14)
        .background(ALIItemColors.soft(color, 0.4))
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: roundLeading ? 4 : 0,
            bottomLeadingRadius: roundLeading ? 4 : 0,
            bottomTrailingRadius: roundTrailing ? 4 : 0,
            topTrailingRadius: roundTrailing ? 4 : 0
        ))
    }

    private func shiftMonth(by value: Int) {
        Track.event("calendar_month_change", ["screen": "calendar", "direction": value > 0 ? "next" : "prev"])
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = newMonth }
        }
    }
}
