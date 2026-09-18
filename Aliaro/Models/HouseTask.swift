import Foundation
import SwiftData

/// A recurring house task (e.g. "Dishwasher", "Laundry"). The interval
/// is optional: if set, the task warns (with color) when it's approaching
/// or overdue for its recommended cadence; if not, it just keeps a
/// history of when it was done.
@Model
final class HouseTask {
    var id: UUID
    var name: String
    var intervalDays: Int?
    var createdAt: Date
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
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.intervalDays = intervalDays
        self.createdAt = createdAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}
