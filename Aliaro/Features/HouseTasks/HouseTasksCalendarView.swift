import SwiftUI

/// Calendar view for "House Tasks": navigates month by month and
/// highlights the days with tasks to do (scheduled date) and the days a
/// task was logged as done. Tapping a day shows below what's to do and
/// what was done on that date.
struct HouseTasksCalendarView: View {
    var tasks: [HouseTask] = []
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

    /// Next date the task is due: its pending scheduled date; for recurring
    /// tasks, last "done" + interval (or the schedule, or today if never done).
    private func nextDueDate(for task: HouseTask) -> Date? {
        let lastLog = logs.first { $0.taskID == task.id }
        if let pending = task.pendingSchedule(lastLog: lastLog) { return calendar.startOfDay(for: pending) }
        guard let interval = task.intervalDays, interval > 0 else { return nil }
        if let lastLog {
            return calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: lastLog.completedAt))
        }
        return calendar.startOfDay(for: .now)
    }

    /// Whether the task has to be done on `day`: its next due date and, for
    /// recurring tasks, every following repetition (from today if overdue).
    private func isDue(_ task: HouseTask, on day: Date) -> Bool {
        guard let next = nextDueDate(for: task) else { return false }
        let target = calendar.startOfDay(for: day)
        if target == next { return true }
        guard let interval = task.intervalDays, interval > 0 else { return false }
        let base = max(next, calendar.startOfDay(for: .now))
        guard target >= base, let diff = calendar.dateComponents([.day], from: base, to: target).day else { return false }
        return diff % interval == 0
    }

    /// Tag color of a task (default accent when it has none).
    private func taskColor(_ hex: String?) -> Color {
        ALIItemColors.color(hex, fallback: ALIColors.houseTasksAccent)
    }

    /// Color of the task a "done" log belongs to.
    private func logColor(_ log: HouseTaskLog) -> Color {
        taskColor(tasks.first { $0.id == log.taskID }?.color)
    }

    private func pendingTasks(on day: Date) -> [HouseTask] {
        tasks.filter { isDue($0, on: day) }
    }

    /// First due date after today of each task (soonest first, max 5): the
    /// "Coming up" reminder shown under today.
    private var upcomingTasks: [(task: HouseTask, date: Date)] {
        let today = calendar.startOfDay(for: .now)
        let items: [(task: HouseTask, date: Date)] = tasks.compactMap { task in
            guard let next = nextDueDate(for: task) else { return nil }
            if next > today { return (task, next) }
            guard let interval = task.intervalDays, interval > 0,
                  let date = calendar.date(byAdding: .day, value: interval, to: today) else { return nil }
            return (task, date)
        }
        return Array(items.sorted { $0.date < $1.date }.prefix(5))
    }

    /// "Tomorrow" or "Mon 27".
    private func upcomingLabel(_ date: Date) -> String {
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEd")
        return f.string(from: date).capitalized
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
                if calendar.isDateInToday(selectedDay) {
                    upcomingSummary
                }
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
        let dayPending = pendingTasks(on: day)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let inMonth = isInDisplayedMonth(day)

        return Button {
            Track.event("calendar_day_tap", ["screen": "house_tasks_calendar", "has_items": !dayLogs.isEmpty || !dayPending.isEmpty, "is_today": isToday])
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

                // Hollow dots = to do, filled = done (max 3 in total).
                HStack(spacing: 3) {
                    let pendingDots = min(dayPending.count, 3)
                    let doneDots = min(dayLogs.count, 3 - pendingDots)
                    if pendingDots + doneDots == 0 {
                        Color.clear.frame(width: 5, height: 5)
                    } else {
                        ForEach(Array(dayPending.prefix(pendingDots).enumerated()), id: \.offset) { _, task in
                            Circle().stroke(taskColor(task.color), lineWidth: 1.2).frame(width: 5, height: 5)
                        }
                        ForEach(Array(dayLogs.prefix(doneDots).enumerated()), id: \.offset) { _, log in
                            Circle().fill(logColor(log)).frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func selectedDaySummary(for day: Date) -> some View {
        let dayLogs = logs(on: day)
        let dayPending = pendingTasks(on: day)
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMMM d"
            return f
        }()

        return ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text(calendar.isDateInToday(day) ? String(localized: "Today") : formatter.string(from: day).capitalized)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)

                if dayLogs.isEmpty && dayPending.isEmpty {
                    Text("No tasks for this day.")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                } else {
                    if !dayPending.isEmpty {
                        daySection(title: "To do", items: dayPending.map { ($0.name, taskColor($0.color)) }, done: false)
                    }
                    if !dayLogs.isEmpty {
                        daySection(title: "Done", items: dayLogs.map { ($0.taskName, logColor($0)) }, done: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingSummary: some View {
        let items = upcomingTasks
        if !items.isEmpty {
            ALICard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Coming up")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .padding(.bottom, 2)
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 10) {
                            Circle().stroke(taskColor(item.task.color), lineWidth: 2).frame(width: 10, height: 10)
                            Text(item.task.name)
                                .font(ALITypography.bodyLarge)
                                .foregroundStyle(ALIColors.ink)
                            Spacer()
                            Text(upcomingLabel(item.date))
                                .font(ALITypography.labelLarge)
                                .foregroundStyle(ALIColors.mutedInk)
                        }
                        .padding(.vertical, 8)
                        if index < items.count - 1 {
                            Divider().overlay(ALIColors.outline)
                        }
                    }
                }
            }
        }
    }

    private func daySection(title: LocalizedStringKey, items: [(name: String, color: Color)], done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
                .padding(.bottom, 2)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    if done {
                        Circle().fill(item.color).frame(width: 10, height: 10)
                    } else {
                        Circle().stroke(item.color, lineWidth: 2).frame(width: 10, height: 10)
                    }
                    Text(item.name)
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(done ? ALIColors.mutedInk : ALIColors.ink)
                        .strikethrough(done, color: ALIColors.mutedInk)
                    Spacer()
                }
                .padding(.vertical, 8)
                if index < items.count - 1 {
                    Divider().overlay(ALIColors.outline)
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
