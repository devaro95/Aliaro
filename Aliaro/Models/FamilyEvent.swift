import Foundation
import SwiftData

/// A shared event on the family calendar (birthday, vacation,
/// plans...) with a start and an end date/time — it can last a few
/// hours or several days.
@Model
final class FamilyEvent {
    var id: UUID
    var title: String
    var note: String?
    var startDate: Date
    var endDate: Date
    var emoji: String
    var createdAt: Date
    /// Who created the event (reference to `FamilyMember`, not a
    /// SwiftData relationship). `createdByName` is copied so it stays
    /// readable even if that person leaves the group.
    var createdByID: UUID?
    var createdByName: String?

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        startDate: Date,
        endDate: Date,
        emoji: String = "🎉",
        createdAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.startDate = startDate
        self.endDate = endDate
        self.emoji = emoji
        self.createdAt = createdAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}
