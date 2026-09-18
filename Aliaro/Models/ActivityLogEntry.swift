import Foundation
import SwiftData

/// A "History" record: something was created, edited or deleted in the
/// family group, and by whom. `entityName` is copied at the time of the
/// action so the entry stays readable even if the item is later renamed
/// or no longer exists. Weekly menu and shopping lists are excluded on
/// purpose (they don't carry authorship, per the app's own rule).
@Model
final class ActivityLogEntry {
    var id: UUID
    /// e.g. "house_task", "house_task_log", "family_event", "reminder", "expense".
    var entityType: String
    var entityName: String
    /// "created", "updated" or "deleted".
    var action: String
    var actorID: UUID?
    var actorName: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        entityType: String,
        entityName: String,
        action: String,
        actorID: UUID? = nil,
        actorName: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.entityType = entityType
        self.entityName = entityName
        self.action = action
        self.actorID = actorID
        self.actorName = actorName
        self.createdAt = createdAt
    }
}
