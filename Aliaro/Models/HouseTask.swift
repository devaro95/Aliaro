import Foundation
import SwiftData

/// A house task (e.g. "Dishwasher", "Take out the trash"). The interval
/// is optional: if set, the task warns (with color) when it's approaching
/// or overdue for its recommended cadence; if not, it just keeps a
/// history of when it was done.
///
/// It can also be scheduled for a specific moment (`scheduledAt`) and
/// assigned to specific people (`memberIDs`): everyone still sees it in the
/// list, but only the assignees get its notifications (created, scheduled
/// time, due).
@Model
final class HouseTask {
    var id: UUID
    var name: String
    var intervalDays: Int?
    var createdAt: Date
    /// When it has to be done. Without an interval it's a one-off task; with
    /// one, it's the first due date and then the cadence takes over.
    var scheduledAt: Date?
    /// For the whole family, or only for `memberIDs` (references to `FamilyMember`).
    var forEveryone: Bool = true
    var memberIDs: [UUID] = []
    /// Who created the task (reference to `FamilyMember`, not a
    /// SwiftData relationship). `createdByName` is copied so it stays
    /// readable even if that person leaves the group.
    var createdByID: UUID?
    var createdByName: String?

    init(
        id: UUID = UUID(),
        name: String,
        intervalDays: Int? = nil,
        createdAt: Date = .now,
        scheduledAt: Date? = nil,
        forEveryone: Bool = true,
        memberIDs: [UUID] = [],
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.intervalDays = intervalDays
        self.createdAt = createdAt
        self.scheduledAt = scheduledAt
        self.forEveryone = forEveryone
        self.memberIDs = memberIDs
        self.createdByID = createdByID
        self.createdByName = createdByName
    }

    /// Whether the task is assigned to this member (all tasks are, unless
    /// it's assigned to specific people).
    func isFor(_ memberID: UUID?) -> Bool {
        guard !forEveryone else { return true }
        guard let memberID else { return false }
        return memberIDs.contains(memberID)
    }

    /// Whether the last "done" covers the scheduled date (done that day, the
    /// day before, or later).
    func lastLogCoversSchedule(_ lastLog: HouseTaskLog?) -> Bool {
        guard let scheduledAt, let lastLog else { return false }
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: scheduledAt)) ?? scheduledAt
        return lastLog.completedAt >= dayBefore
    }

    /// "Done" section of the list: one-off scheduled tasks stay done once
    /// they're done; the rest count as done only for today.
    func isDone(lastLog: HouseTaskLog?) -> Bool {
        guard let lastLog else { return false }
        if scheduledAt != nil && intervalDays == nil && lastLogCoversSchedule(lastLog) { return true }
        return Calendar.current.isDateInToday(lastLog.completedAt)
    }

    /// Scheduled and still waiting for that moment (not done for it yet).
    func pendingSchedule(lastLog: HouseTaskLog?) -> Date? {
        guard let scheduledAt, !lastLogCoversSchedule(lastLog) else { return nil }
        return scheduledAt
    }
}
