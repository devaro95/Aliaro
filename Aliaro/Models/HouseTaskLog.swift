import Foundation
import SwiftData

/// A record of "this was done on this day" for a `HouseTask`. `taskID`
/// references the source task (not a SwiftData relationship) — `taskName`
/// is copied so the history stays readable even if the task is renamed
/// or deleted. `createdByID`/`createdByName` record who logged it as "done".
@Model
final class HouseTaskLog {
    var id: UUID
    var taskID: UUID
    var taskName: String
    var completedAt: Date
    var note: String?
    var createdByID: UUID?
    var createdByName: String?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        taskName: String,
        completedAt: Date = .now,
        note: String? = nil,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.taskName = taskName
        self.completedAt = completedAt
        self.note = note
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}
