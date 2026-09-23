import SwiftUI
import SwiftData

/// "Tasks" tab: log of recurring house tasks (dishwasher,
/// laundry…) — each card shows when it was last done and, if it has
/// a defined cadence, whether it's due soon or already overdue.
struct HouseTasksScreen: View {
    private enum ViewMode {
        case list, calendar
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var premium: PremiumManager

    @Query(sort: \HouseTask.createdAt) private var tasks: [HouseTask]
    @Query(sort: \HouseTaskLog.completedAt, order: .reverse) private var logs: [HouseTaskLog]

    @State private var showAddSheet = false
    @State private var selectedTask: HouseTask?
    @State private var viewMode: ViewMode = .list
    @State private var showPaywall = false
    @State private var showStats = false

    /// The calendar view needs a subscription if `houseTasksCalendar`
    /// is currently premium.
    private var isCalendarViewLocked: Bool { premium.isLocked(.houseTasksCalendar) }
    /// Statistics need a subscription if `houseTasksStats` is currently premium.
    private var isStatsLocked: Bool { premium.isLocked(.houseTasksStats) }
    /// Calendar view open as a premium preview (sample data + floating banner).
    private var isCalendarPreview: Bool { viewMode == .calendar && isCalendarViewLocked }
    /// Beyond 5 tasks, adding another one needs a subscription if
    /// `unlimitedHouseTasks` is currently premium.
    private var isNewTaskLocked: Bool { tasks.count >= 5 && premium.isLocked(.unlimitedHouseTasks) }
    /// If the group loses premium, only the first 5 tasks it ever
    /// created stay usable — the rest get locked behind the paywall
    /// instead of being deleted.
    private var lockedTaskIDs: Set<UUID> {
        guard premium.isLocked(.unlimitedHouseTasks) else { return [] }
        let extra = tasks.sorted { $0.createdAt < $1.createdAt }.dropFirst(5)
        return Set(extra.map(\.id))
    }

    var body: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "House Tasks", accent: ALIColors.houseTasksAccent) {
                    HStack(spacing: 10) {
                        statsButton
                        viewModeToggleButton
                        ALIFloatingButton(accent: ALIColors.houseTasksAccent) {
                            if isNewTaskLocked { showPaywall = true } else { showAddSheet = true }
                        }
                        .scaleEffect(0.72)
                        .aliPremiumLockOverlay(isNewTaskLocked)
                    }
                }

                switch viewMode {
                case .list:
                    if tasks.isEmpty {
                        ALIEmptyState(
                            emoji: "🧺",
                            title: "No tasks yet",
                            subtitle: "Add the dishwasher, laundry, or anything you want to keep on top of."
                        )
                    } else {
                        ALICard {
                            VStack(spacing: 0) {
                                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                                    let isLocked = lockedTaskIDs.contains(task.id)
                                    HouseTaskRow(
                                        task: task,
                                        lastLog: lastLog(for: task),
                                        locked: isLocked,
                                        onToggleToday: {
                                            if isLocked { showPaywall = true } else { toggleToday(task) }
                                        },
                                        onOpenDetail: {
                                            if isLocked { showPaywall = true } else { selectedTask = task }
                                        }
                                    )
                                    if index < tasks.count - 1 {
                                        Divider().overlay(ALIColors.outline)
                                    }
                                }
                            }
                        }
                    }
                case .calendar:
                    if isCalendarViewLocked {
                        HouseTasksCalendarView(logs: HouseTasksDemoData.logs)
                            .aliPremiumPreview(true)
                    } else {
                        HouseTasksCalendarView(logs: logs)
                    }
                }
            }
            .padding(.horizontal, 20)
            // Extra room while the calendar preview banner floats over
            // the content, so everything can still be scrolled into view.
            .padding(.bottom, isCalendarPreview ? 320 : 100)
        }
        .overlay(alignment: .bottom) {
            if isCalendarPreview {
                // Floats just above the bottom bar (which lives in
                // `MainTabContainer`'s ZStack, over this screen).
                ALIPremiumPreviewBanner(
                    message: .tasksCalendar,
                    buttonTitle: "Unlock calendar"
                ) { showPaywall = true }
                .padding(.horizontal, 16)
                // Bottom bar: 56pt tall + 8pt below it, measured from the
                // safe-area bottom — plus a 12pt gap above it.
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(ALIColors.background)
        .sheet(isPresented: $showAddSheet) {
            AddHouseTaskSheet(taskToEdit: nil)
        }
        .sheet(item: $selectedTask) { task in
            HouseTaskDetailSheet(task: task, logs: logs.filter { $0.taskID == task.id })
        }
        .sheet(isPresented: $showStats) {
            HouseTasksStatsScreen(tasks: tasks, logs: logs)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// Opens the statistics screen — always: if `houseTasksStats` is
    /// locked it shows as a premium preview with sample data.
    private var statsButton: some View {
        Button {
            showStats = true
        } label: {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
                .aliPremiumPreviewOverlay(isStatsLocked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Statistics")
    }

    /// Button that toggles between the list view and the calendar view. If
    /// the calendar view is locked it still switches, as a premium preview
    /// with sample data.
    private var viewModeToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewMode = (viewMode == .list) ? .calendar : .list
            }
        } label: {
            Image(systemName: viewMode == .list ? "calendar" : "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 40, height: 40)
                .background(ALIColors.surfaceVariant)
                .clipShape(Circle())
                .aliPremiumPreviewOverlay(viewMode == .list && isCalendarViewLocked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewMode == .list ? "View as calendar" : "View as list")
    }

    private func lastLog(for task: HouseTask) -> HouseTaskLog? {
        logs.first { $0.taskID == task.id }
    }

    /// Same as checking/unchecking in the shopping list: if it's already
    /// done today, tapping the circle undoes it; otherwise it logs a "done" now.
    private func toggleToday(_ task: HouseTask) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let todayLog = lastLog(for: task), Calendar.current.isDateInToday(todayLog.completedAt) {
                let logID = todayLog.id
                modelContext.delete(todayLog)
                dataSync.deleteHouseTaskLog(id: logID)
            } else {
                // Record who did it — needed for per-member statistics.
                let actorID = familySession.memberID
                let actorName = actorID.flatMap { modelContext.familyMemberName(id: $0) }
                let log = HouseTaskLog(taskID: task.id, taskName: task.name, createdByID: actorID, createdByName: actorName)
                modelContext.insert(log)
                if let familyID = familySession.familyID {
                    dataSync.pushHouseTaskLog(log, familyID: familyID)
                    dataSync.logActivity(
                        entityType: "house_task_log", entityName: task.name, action: "created",
                        actorID: actorID, actorName: actorName,
                        familyID: familyID, modelContext: modelContext
                    )
                }
            }
        }
    }
}

/// Row for a task: "done today" checkbox + name + cadence status.
private struct HouseTaskRow: View {
    let task: HouseTask
    let lastLog: HouseTaskLog?
    var locked: Bool = false
    let onToggleToday: () -> Void
    let onOpenDetail: () -> Void

    private var daysSince: Int? {
        guard let lastLog else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastLog.completedAt), to: Calendar.current.startOfDay(for: .now)).day
    }

    private var isDoneToday: Bool { daysSince == 0 }

    private var statusLabel: String {
        guard let name = task.createdByName, !name.isEmpty else { return status.text }
        return "\(status.text) · \(name)"
    }

    private var status: (color: Color, text: String) {
        guard let interval = task.intervalDays else {
            if let daysSince {
                let text = daysSince == 0
                    ? String(localized: "Done today")
                    : (daysSince == 1 ? String(localized: "\(daysSince) day ago") : String(localized: "\(daysSince) days ago"))
                return (ALIColors.mutedInk, text)
            }
            return (ALIColors.mutedInk, String(localized: "Not logged yet"))
        }
        guard let daysSince else {
            return (ALIColors.error, String(localized: "Never logged · every \(interval) days"))
        }
        if daysSince == 0 {
            return (ALIColors.success, String(localized: "Done today"))
        } else if Double(daysSince) <= Double(interval) * 0.7 {
            return (ALIColors.success, String(localized: "Up to date · \(daysSince) days ago"))
        } else if daysSince <= interval {
            return (ALIColors.sun, String(localized: "Due soon · \(daysSince) days ago"))
        } else {
            return (ALIColors.error, String(localized: "Overdue · \(daysSince) days ago"))
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            if locked {
                ALIPremiumLockBadge()
            }
            Button(action: onToggleToday) {
                ZStack {
                    Circle()
                        .fill(isDoneToday ? ALIColors.success : ALIColors.surfaceVariant)
                        .frame(width: 26, height: 26)
                    if isDoneToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ALIColors.onAccent)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onOpenDetail) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.name)
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(ALIColors.ink)
                        HStack(spacing: 6) {
                            Circle().fill(status.color).frame(width: 7, height: 7)
                            Text(statusLabel)
                                .font(ALITypography.labelLarge)
                                .foregroundStyle(ALIColors.mutedInk)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(locked ? 0.55 : 1)
        .padding(.vertical, 12)
    }
}
