import SwiftUI

/// Calendar view for "House Tasks": navigates month by month and
/// highlights the days a task was logged as done. Tapping a day shows
/// the detail below of what was marked on that date.
struct HouseTasksCalendarView: View {
    let logs: [HouseTaskLog]

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: .now)

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

    private func logs(on day: Date) -> [HouseTaskLog] {
        logs.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }
    }

    private func isInDisplayedMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
    }

    var body: some View {
        trackedBody.trackScreen("house_tasks_calendar")
    }

    @ViewBuilder
    private var trackedBody: some View {
        VStack(spacing: 16) {
            ALICard {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayHeader
                    dayGrid
                }
            }

            if let selectedDay {
                selectedDaySummary(for: selectedDay)
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(gridDays, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let dayLogs = logs(on: day)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let inMonth = isInDisplayedMonth(day)

        return Button {
            Track.event("calendar_day_tap", ["screen": "house_tasks_calendar", "has_items": !dayLogs.isEmpty, "is_today": isToday])
            withAnimation(.easeInOut(duration: 0.15)) { selectedDay = day }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(inMonth ? ALIColors.ink : ALIColors.mutedInk.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .background(
                        isSelected
                            ? ALIColors.houseTasksAccent
                            : (dayLogs.isEmpty ? Color.clear : ALIColors.calendarActivity.opacity(0.55))
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(isToday && !isSelected ? ALIColors.houseTasksAccent : .clear, lineWidth: 1.5)
                    )

                HStack(spacing: 3) {
                    if dayLogs.isEmpty {
                        Color.clear.frame(width: 4, height: 4)
                    } else {
                        ForEach(0..<min(dayLogs.count, 3), id: \.self) { _ in
                            Circle().fill(ALIColors.houseTasksAccent).frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func selectedDaySummary(for day: Date) -> some View {
        let dayLogs = logs(on: day)
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMMM d"
            return f
        }()

        return ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text(formatter.string(from: day).capitalized)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)

                if dayLogs.isEmpty {
                    Text("No task was logged on this day.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dayLogs.enumerated()), id: \.element.id) { index, log in
                            HStack(spacing: 10) {
                                Circle().fill(ALIColors.success).frame(width: 8, height: 8)
                                Text(log.taskName)
                                    .font(ALITypography.bodyLarge)
                                    .foregroundStyle(ALIColors.ink)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            if index < dayLogs.count - 1 {
                                Divider().overlay(ALIColors.outline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func shiftMonth(by value: Int) {
        Track.event("calendar_month_change", ["screen": "house_tasks_calendar", "direction": value > 0 ? "next" : "prev"])
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = newMonth }
        }
    }
}
