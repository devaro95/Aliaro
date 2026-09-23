import SwiftUI
import SwiftData
import Charts

/// House tasks statistics: who did what, each member's share of the
/// housework, activity over time, most frequent tasks, streaks and
/// tasks needing attention. Premium (`houseTasksStats`): when locked, the
/// screen still opens as a preview — built from sample data (never the
/// group's real data), blurred and non-interactive, with a banner that
/// leads to the paywall. Unlocks live as soon as the group subscribes.
struct HouseTasksStatsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var premium: PremiumManager

    private let realTasks: [HouseTask]
    private let realLogs: [HouseTaskLog]

    @Query(sort: \FamilyMember.createdAt) private var realMembers: [FamilyMember]

    @State private var showPaywall = false

    init(tasks: [HouseTask], logs: [HouseTaskLog]) {
        self.realTasks = tasks
        self.realLogs = logs
    }

    private var isLocked: Bool { premium.isLocked(.houseTasksStats) }

    /// Everything below reads these — sample data while locked, so the
    /// preview never exposes the group's real statistics.
    private var tasks: [HouseTask] { isLocked ? HouseTasksDemoData.tasks : realTasks }
    private var logs: [HouseTaskLog] { isLocked ? HouseTasksDemoData.logs : realLogs }
    private var members: [FamilyMember] { isLocked ? HouseTasksDemoData.members : realMembers }

    private enum Period: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year", all = "All"
        var id: String { rawValue }

        var component: Calendar.Component? {
            switch self {
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            case .all: return nil
            }
        }

        /// Granularity of the activity chart for this period.
        var chartComponent: Calendar.Component {
            switch self {
            case .week: return .day
            case .month: return .weekOfYear
            case .year, .all: return .month
            }
        }

        var chartBucketCount: Int {
            switch self {
            case .week: return 7
            case .month: return 5
            case .year, .all: return 12
            }
        }
    }

    private struct MemberStat: Identifiable {
        let id: String
        let name: String
        let emoji: String
        let color: Color
        var count: Int = 0
        var taskCounts: [String: Int] = [:]
        var topTask: String? { taskCounts.max { $0.value < $1.value }?.key }
    }

    private struct TaskStat: Identifiable {
        let id: String
        let name: String
        var count: Int
    }

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let label: String
        let order: Int
        let member: String
        let color: Color
        let count: Int
    }

    private struct AttentionTask: Identifiable {
        let id: UUID
        let name: String
        let daysOverdue: Int?
    }

    @State private var period: Period = .month

    private static let memberColors: [Color] = [
        ALIPalette.lavender, ALIPalette.coral, ALIPalette.sky, ALIPalette.mint,
        ALIPalette.sun, ALIPalette.rose, ALIPalette.pistachio, ALIPalette.turquoise, ALIPalette.blush
    ]

    var body: some View {
        trackedBody.trackScreen("house_tasks_stats")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("", selection: $period) {
                        ForEach(Period.allCases) { p in
                            Text(LocalizedStringKey(p.rawValue)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: period) { _, p in
                        Track.event("stats_period_changed", ["screen": "house_tasks_stats", "period": p.rawValue, "locked": isLocked])
                    }

                    summaryCard
                    participationCard
                    chartCard
                    topTasksCard
                    habitsCard
                    attentionCard
                }
                .padding(20)
                .aliPremiumPreview(isLocked)
            }
            .aliPremiumPreviewBanner(isLocked, buttonTitle: "Unlock statistics") { showPaywall = Track.paywall("task_stats_banner") }
            .background(ALIColors.background)
            .navigationTitle("Task statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: Data

    private var periodLogs: [HouseTaskLog] {
        guard let component = period.component,
              let interval = Calendar.current.dateInterval(of: component, for: .now) else { return logs }
        return logs.filter { $0.completedAt >= interval.start && $0.completedAt < interval.end }
    }

    /// Key used to attribute a log to a person: the member ID when known,
    /// otherwise the copied name (member left the group), otherwise "unknown".
    private func memberKey(_ log: HouseTaskLog) -> String {
        if let id = log.createdByID { return id.uuidString }
        if let name = log.createdByName, !name.isEmpty { return "name:\(name)" }
        return "unknown"
    }

    /// Stable, distinct color per participant: current members first (in
    /// join order), then former members found in the logs. Only
    /// unattributed logs ("unknown") are grey.
    private var colorOrder: [String] {
        var keys = members.map { $0.id.uuidString }
        let extra = Set(logs.map(memberKey)).subtracting(keys).subtracting(["unknown"]).sorted()
        keys.append(contentsOf: extra)
        return keys
    }

    private func color(forKey key: String) -> Color {
        if let index = colorOrder.firstIndex(of: key) {
            return Self.memberColors[index % Self.memberColors.count]
        }
        return ALIColors.mutedInk.opacity(0.5)
    }

    private func displayName(forKey key: String, fallback: String?) -> (String, String) {
        if let member = members.first(where: { $0.id.uuidString == key }) { return (member.name, member.emoji) }
        if let fallback, !fallback.isEmpty { return (fallback, "👤") }
        return (String(localized: "Unknown"), "❔")
    }

    /// Every current member (even with 0 tasks) plus anyone else who
    /// logged tasks in the period (former members / unknown).
    private var memberStats: [MemberStat] {
        var stats: [String: MemberStat] = [:]
        for member in members {
            let key = member.id.uuidString
            stats[key] = MemberStat(id: key, name: member.name, emoji: member.emoji, color: color(forKey: key))
        }
        for log in periodLogs {
            let key = memberKey(log)
            if stats[key] == nil {
                let (name, emoji) = displayName(forKey: key, fallback: log.createdByName)
                stats[key] = MemberStat(id: key, name: name, emoji: emoji, color: color(forKey: key))
            }
            stats[key]?.count += 1
            stats[key]?.taskCounts[log.taskName, default: 0] += 1
        }
        return stats.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    private var totalCount: Int { periodLogs.count }

    // MARK: Summary

    private var summaryCard: some View {
        let top = memberStats.first { $0.count > 0 }
        let activeMembers = memberStats.filter { $0.count > 0 }.count
        return ALICard {
            HStack(alignment: .top) {
                summaryItem(title: "Tasks done", value: "\(totalCount)")
                Spacer()
                summaryItem(title: "Participants", value: "\(activeMembers)")
                Spacer()
                summaryItem(title: "MVP", value: top?.name ?? "—")
            }
        }
    }

    private func summaryItem(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
            Text(value)
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    // MARK: Participation

    private var participationCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Participation")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                if totalCount == 0 {
                    emptyText
                } else {
                    Chart(memberStats.filter { $0.count > 0 }) { stat in
                        SectorMark(
                            angle: .value("Tasks", stat.count),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .foregroundStyle(stat.color)
                        .cornerRadius(4)
                    }
                    .frame(height: 170)

                    VStack(spacing: 14) {
                        ForEach(memberStats) { stat in
                            memberRow(stat)
                        }
                    }
                }
            }
        }
    }

    private func memberRow(_ stat: MemberStat) -> some View {
        let share = totalCount > 0 ? Double(stat.count) / Double(totalCount) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(stat.color).frame(width: 10, height: 10)
                Text(stat.name)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Spacer()
                Text("\(stat.count) · \(Int((share * 100).rounded()))%")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.ink)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ALIColors.surfaceVariant)
                    Capsule().fill(stat.color).frame(width: geometry.size.width * share)
                }
            }
            .frame(height: 8)
            if let topTask = stat.topTask {
                Text("Most done: \(topTask)")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Activity chart

    private var chartPoints: [ChartPoint] {
        let calendar = Calendar.current
        let component = period.chartComponent
        guard let currentStart = calendar.dateInterval(of: component, for: .now)?.start else { return [] }
        let formatter = DateFormatter()
        switch component {
        case .day: formatter.setLocalizedDateFormatFromTemplate("EEE")
        case .weekOfYear: formatter.setLocalizedDateFormatFromTemplate("d MMM")
        default: formatter.setLocalizedDateFormatFromTemplate("MMM")
        }

        let starts: [Date] = stride(from: period.chartBucketCount - 1, through: 0, by: -1).compactMap {
            calendar.date(byAdding: component, value: -$0, to: currentStart)
        }
        var counts: [Date: [String: Int]] = [:]
        for log in logs {
            guard let start = calendar.dateInterval(of: component, for: log.completedAt)?.start,
                  starts.contains(start) else { continue }
            counts[start, default: [:]][memberKey(log), default: 0] += 1
        }
        var names: [String: String] = [:]
        for log in logs where names[memberKey(log)] == nil {
            names[memberKey(log)] = displayName(forKey: memberKey(log), fallback: log.createdByName).0
        }
        var points: [ChartPoint] = []
        for (order, start) in starts.enumerated() {
            let label = formatter.string(from: start)
            for (key, count) in counts[start] ?? [:] {
                points.append(ChartPoint(label: label, order: order, member: names[key] ?? "?", color: color(forKey: key), count: count))
            }
            if counts[start] == nil {
                points.append(ChartPoint(label: label, order: order, member: "", color: .clear, count: 0))
            }
        }
        return points
    }

    private var chartCard: some View {
        let points = chartPoints
        var seen = Set<String>()
        let legend = points.filter { seen.insert($0.member).inserted }
        return ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Activity")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                if points.allSatisfy({ $0.count == 0 }) {
                    emptyText
                } else {
                    Chart(points) { point in
                        BarMark(
                            x: .value("Period", point.label),
                            y: .value("Tasks", point.count)
                        )
                        .foregroundStyle(by: .value("Member", point.member))
                    }
                    .chartForegroundStyleScale(
                        domain: legend.map(\.member),
                        range: legend.map(\.color)
                    )
                    .chartLegend(.hidden)
                    .chartXScale(domain: orderedLabels(points))
                    .frame(height: 200)
                }
            }
        }
    }

    private func orderedLabels(_ points: [ChartPoint]) -> [String] {
        var seen = Set<String>()
        return points.sorted { $0.order < $1.order }.map(\.label).filter { seen.insert($0).inserted }
    }

    // MARK: Top tasks

    private var taskStats: [TaskStat] {
        var counts: [String: Int] = [:]
        for log in periodLogs { counts[log.taskName, default: 0] += 1 }
        return counts.map { TaskStat(id: $0.key, name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    private var topTasksCard: some View {
        let stats = Array(taskStats.prefix(5))
        let maxCount = stats.first?.count ?? 1
        return ALICard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Most done tasks")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                if stats.isEmpty {
                    emptyText
                } else {
                    VStack(spacing: 12) {
                        ForEach(stats) { stat in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(stat.name)
                                        .font(ALITypography.bodyMedium)
                                        .foregroundStyle(ALIColors.ink)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(stat.count)×")
                                        .font(ALITypography.bodyMedium)
                                        .foregroundStyle(ALIColors.ink)
                                        .monospacedDigit()
                                }
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(ALIColors.surfaceVariant)
                                        Capsule()
                                            .fill(ALIColors.houseTasksAccent)
                                            .frame(width: geometry.size.width * Double(stat.count) / Double(maxCount))
                                    }
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Habits (streak, busiest day, daily average)

    /// Consecutive days (ending today, or yesterday if nothing yet today)
    /// with at least one task done by anyone. Always over all history.
    private var currentStreak: Int {
        let calendar = Calendar.current
        let days = Set(logs.map { calendar.startOfDay(for: $0.completedAt) })
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private var busiestWeekday: String? {
        guard !periodLogs.isEmpty else { return nil }
        let calendar = Calendar.current
        var counts: [Int: Int] = [:]
        for log in periodLogs { counts[calendar.component(.weekday, from: log.completedAt), default: 0] += 1 }
        guard let weekday = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return calendar.standaloneWeekdaySymbols[weekday - 1].capitalized
    }

    private var dailyAverage: Double {
        guard !periodLogs.isEmpty else { return 0 }
        let calendar = Calendar.current
        let start: Date
        if let component = period.component, let interval = calendar.dateInterval(of: component, for: .now) {
            start = interval.start
        } else {
            start = periodLogs.map(\.completedAt).min() ?? .now
        }
        let days = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: .now)).day ?? 0) + 1)
        return Double(periodLogs.count) / Double(days)
    }

    private var habitsCard: some View {
        ALICard {
            HStack(alignment: .top) {
                summaryItem(title: "Streak", value: String(localized: "\(currentStreak) days"))
                Spacer()
                summaryItem(title: "Busiest day", value: busiestWeekday ?? "—")
                Spacer()
                summaryItem(title: "Per day", value: dailyAverage.formatted(.number.precision(.fractionLength(1))))
            }
        }
    }

    // MARK: Needs attention

    /// Tasks with a cadence that are overdue right now (or never done).
    private var attentionTasks: [AttentionTask] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return tasks.compactMap { task -> AttentionTask? in
            guard let interval = task.intervalDays else { return nil }
            guard let last = logs.filter({ $0.taskID == task.id }).map(\.completedAt).max() else {
                return AttentionTask(id: task.id, name: task.name, daysOverdue: nil)
            }
            let since = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: today).day ?? 0
            return since > interval ? AttentionTask(id: task.id, name: task.name, daysOverdue: since - interval) : nil
        }
        .sorted { ($0.daysOverdue ?? .max) > ($1.daysOverdue ?? .max) }
    }

    private var attentionCard: some View {
        let items = attentionTasks
        return ALICard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Needs attention")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)

                if items.isEmpty {
                    Text("Everything is up to date 🎉")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                } else {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Circle().fill(ALIColors.error).frame(width: 7, height: 7)
                            Text(item.name)
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(item.daysOverdue.map { String(localized: "\($0) days overdue") } ?? String(localized: "Never done"))
                                .font(ALITypography.labelLarge)
                                .foregroundStyle(ALIColors.error)
                        }
                    }
                }
            }
        }
    }

    private var emptyText: some View {
        Text("No tasks done in this period yet.")
            .font(ALITypography.bodyMedium)
            .foregroundStyle(ALIColors.mutedInk)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }
}

/// Fixed sample family used by the premium previews of House Tasks
/// (statistics, calendar). Built once; the models are never inserted
/// into a context, so nothing is persisted or synced.
@MainActor
enum HouseTasksDemoData {
    static let members: [FamilyMember] = {
        let now = Date.now
        return [
            FamilyMember(name: "Ana", emoji: "👩", createdAt: now.addingTimeInterval(-3)),
            FamilyMember(name: "Luis", emoji: "👨", createdAt: now.addingTimeInterval(-2)),
            FamilyMember(name: "Marta", emoji: "👧", createdAt: now.addingTimeInterval(-1))
        ]
    }()

    static let tasks: [HouseTask] = [
        HouseTask(name: String(localized: "Dishes"), intervalDays: 1),
        HouseTask(name: String(localized: "Laundry"), intervalDays: 3),
        HouseTask(name: String(localized: "Vacuum"), intervalDays: 4),
        HouseTask(name: String(localized: "Take out the trash"), intervalDays: 2),
        HouseTask(name: String(localized: "Change the sheets"), intervalDays: 7),
        HouseTask(name: String(localized: "Clean the windows"), intervalDays: 30)
    ]

    static let logs: [HouseTaskLog] = {
        let calendar = Calendar.current
        let now = Date.now
        // Uneven share between members, more activity on weekends.
        let memberPattern = [0, 1, 0, 2, 0, 1, 1, 0, 2, 0]
        var logs: [HouseTaskLog] = []
        for day in 0..<180 {
            guard let date = calendar.date(byAdding: .day, value: -day, to: now) else { continue }
            let perDay = (calendar.isDateInWeekend(date) ? 3 : 1) + (day * 7) % 3
            for i in 0..<perDay {
                // "Change the sheets" stops being done 10 days ago and
                // "Clean the windows" never is, to fill "Needs attention".
                var taskIndex = (day * 5 + i * 3) % 5
                if taskIndex == 4 && day < 10 { taskIndex = 0 }
                let task = tasks[taskIndex]
                let member = members[memberPattern[(day + i * 3) % memberPattern.count]]
                logs.append(HouseTaskLog(
                    taskID: task.id,
                    taskName: task.name,
                    completedAt: date.addingTimeInterval(Double(-i * 3600)),
                    createdByID: member.id,
                    createdByName: member.name
                ))
            }
        }
        return logs.sorted { $0.completedAt > $1.completedAt }
    }()
}
