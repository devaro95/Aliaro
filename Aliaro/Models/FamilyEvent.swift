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
    /// Who the event is for: the whole family (`forEveryone`) or just
    /// `memberIDs` (reference `FamilyMember`, not a SwiftData relationship).
    var forEveryone: Bool = true
    var memberIDs: [UUID] = []
    /// All-day event (birthday, holiday…): no time shown. Stored as
    /// `startDate` = start of the first day, `endDate` = 23:59:59 of the
    /// last day (local time), so every existing day-range check still works.
    var isAllDay: Bool = false

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        startDate: Date,
        endDate: Date,
        emoji: String = ALIIcon.party,
        createdAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil,
        forEveryone: Bool = true,
        memberIDs: [UUID] = [],
        isAllDay: Bool = false
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
        self.forEveryone = forEveryone
        self.memberIDs = memberIDs
        self.isAllDay = isAllDay
    }

    /// "Everyone" or the names of the people the event is for.
    func attendeesLabel(members: [FamilyMember]) -> String {
        if forEveryone { return String(localized: "Everyone") }
        let names = members.filter { memberIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? String(localized: "Everyone") : names.joined(separator: ", ")
    }
}
