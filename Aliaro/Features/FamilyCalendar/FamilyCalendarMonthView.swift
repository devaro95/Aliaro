import SwiftUI

/// Monthly calendar view for "Family": navigates month by month.
/// Multi-day events are drawn as a continuous band joining the days they
/// span (with rounded corners only on the start and end day); single-day
/// events are marked with a dot below the number.
/// Tapping a day selects it to see its detail below.
struct FamilyCalendarMonthView: View {
    let events: [FamilyEvent]
    @Binding var selectedDay: Date?

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: .now)

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

    /// The multi-day event (if any) that covers that date. Single-day
    /// events don't count here — those are marked with a dot, not the
    /// band.
    private func spanningEvent(on day: Date) -> FamilyEvent? {
        events.first { event in
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(for: event.endDate)
            guard start != end else { return false }
            let target = calendar.startOfDay(for: day)
            return target >= start && target <= end
        }
    }

    /// Events that occur entirely on that day (for the little dot below the number).
    private func singleDayEvents(on day: Date) -> [FamilyEvent] {
        events.filter { event in
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(for: event.endDate)
            return start == end && calendar.isDate(day, inSameDayAs: event.startDate)
        }
    }

    /// The id of the multi-day event occupying each grid cell, in the
    /// same order as `gridDays` — this way we know whether the previous
    /// or next cell belongs to the same event to join the band between them.
    private var spanningEventIDs: [UUID?] {
        gridDays.map { spanningEvent(on: $0)?.id }
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
            Text(monthTitle)
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
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
        let ids = spanningEventIDs
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { index, day in
                dayCell(day, index: index, spanningIDs: ids)
            }
        }
    }

    private func dayCell(_ day: Date, index: Int, spanningIDs: [UUID?]) -> some View {
        let singleEvents = singleDayEvents(on: day)
        let spanning = spanningEventIDs.isEmpty ? nil : spanningIDs[index]
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let inMonth = isInDisplayedMonth(day)

        let columnIndex = index % 7
        let isRangeStart = spanning != nil && (columnIndex == 0 || spanningIDs[index - 1] != spanning)
        let isRangeEnd = spanning != nil && (columnIndex == 6 || spanningIDs[index + 1] != spanning)

        return Button {
            Track.event("calendar_day_tap", ["screen": "calendar", "is_today": Calendar.current.isDateInToday(day)])
            withAnimation(.easeInOut(duration: 0.15)) { selectedDay = day }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(inMonth ? ALIColors.ink : ALIColors.mutedInk.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .background(
                        isSelected
                            ? ALIColors.familyAccent
                            : (singleEvents.isEmpty ? Color.clear : ALIColors.calendarActivity.opacity(0.55))
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(isToday && !isSelected ? ALIColors.familyAccent : .clear, lineWidth: 1.5)
                    )
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                    .background(
                        rangeBackground(isStart: isRangeStart, isEnd: isRangeEnd, isActive: spanning != nil)
                    )

                HStack(spacing: 3) {
                    if singleEvents.isEmpty {
                        Color.clear.frame(width: 4, height: 4)
                    } else {
                        ForEach(0..<min(singleEvents.count, 3), id: \.self) { _ in
                            Circle().fill(ALIColors.familyAccent).frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 4)
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Continuous band behind a day that's part of a multi-day event: it
    /// extends a couple of points into the gap with the neighboring cell
    /// when that cell belongs to the same event, so the two bands touch
    /// and look like a single piece. It only has rounded corners at the
    /// event's actual end (or the end of the row, if the event continues
    /// into the following week).
    @ViewBuilder
    private func rangeBackground(isStart: Bool, isEnd: Bool, isActive: Bool) -> some View {
        if isActive {
            UnevenRoundedRectangle(
                topLeadingRadius: isStart ? 15 : 0,
                bottomLeadingRadius: isStart ? 15 : 0,
                bottomTrailingRadius: isEnd ? 15 : 0,
                topTrailingRadius: isEnd ? 15 : 0
            )
            .fill(ALIColors.familyAccent.opacity(0.32))
            .padding(.leading, isStart ? 0 : -2)
            .padding(.trailing, isEnd ? 0 : -2)
        }
    }

    private func shiftMonth(by value: Int) {
        Track.event("calendar_month_change", ["screen": "calendar", "direction": value > 0 ? "next" : "prev"])
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = newMonth }
        }
    }
}
