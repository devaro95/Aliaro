import Foundation
import SwiftData

/// A one-off reminder that sends a push notification to all devices of
/// the recipients (sent by the server). `notifyEveryone` decides whether
/// the alert is for the whole family or just the `recipientIDs` (reference
/// `FamilyMember`, not a SwiftData relationship). `advanceNoticeSeconds`
/// are extra alerts before `fireDate`, in addition to the exact-time
/// alert, which is always sent.
@Model
final class Reminder {
    var id: UUID
    var title: String
    var note: String?
    var fireDate: Date
    var notifyEveryone: Bool
    var recipientIDs: [UUID]
    /// Additional alerts before `fireDate`, in seconds of advance notice
    /// (maximum 2). The exact-time alert is always sent, on top of
    /// these.
    var advanceNoticeSeconds: [Int]
    var notificationID: String
    var createdAt: Date
    /// Who created the reminder (reference to `FamilyMember`, not a
    /// SwiftData relationship). `createdByName` is copied so it stays
    /// readable even if that person leaves the group.
    var createdByID: UUID?
    var createdByName: String?

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        fireDate: Date,
        notifyEveryone: Bool = true,
        recipientIDs: [UUID] = [],
        advanceNoticeSeconds: [Int] = [],
        notificationID: String = UUID().uuidString,
        createdAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.fireDate = fireDate
        self.notifyEveryone = notifyEveryone
        self.recipientIDs = recipientIDs
        self.advanceNoticeSeconds = advanceNoticeSeconds
        self.notificationID = notificationID
        self.createdAt = createdAt
        self.createdByID = createdByID
        self.createdByName = createdByName
    }
}
