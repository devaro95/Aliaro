import Foundation
import SwiftData
import SwiftUI
import CryptoKit

/// A category of the family calendar ("Birthday", "Trip", "Sport"…) with
/// its color: events take the color of their category. They replace the
/// old event icons: each icon became a default category (`defaults`,
/// created once per family on first sync, with a fixed id per family so
/// several devices never duplicate them). The family can rename them,
/// change their color, delete them or add their own. Categories are
/// optional: an event without one shows `noneColor`.
@Model
final class EventCategory {
    var id: UUID
    var name: String
    /// "RRGGBB" from `ALIItemColors.palette`.
    var color: String
    /// Key of a default category ("birthday"…); nil for the family's own ones.
    var defaultKey: String?
    var position: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        color: String,
        defaultKey: String? = nil,
        position: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.defaultKey = defaultKey
        self.position = position
        self.createdAt = createdAt
    }

    var swiftUIColor: Color { ALIItemColors.color(color, fallback: ALIColors.familyAccent) }

    /// Name to show: default ones are stored with their English name and
    /// shown translated until the family renames them.
    var displayName: String {
        guard let defaultKey, let preset = Self.defaults.first(where: { $0.key == defaultKey }), name == preset.name else { return name }
        return String(localized: String.LocalizationValue(preset.name))
    }

    var isDefault: Bool { defaultKey != nil }
}

extension EventCategory {
    /// The categories every family starts with (the old event icons).
    /// `icon` keeps filling `family_events.emoji` for older app versions.
    static let defaults: [(key: String, name: String, color: String, icon: String)] = [
        ("party", "Party", "FF8FA3", ALIIcon.party),
        ("birthday", "Birthday", "FFC49B", ALIIcon.cake),
        ("trip", "Trip", "5DADE2", ALIIcon.plane),
        ("holidays", "Holidays", "4ECDC4", ALIIcon.beach),
        ("christmas", "Christmas", "6BCB77", ALIIcon.xmas),
        ("health", "Health", "8FD9C4", ALIIcon.health),
        ("sport", "Sport", "F8B259", ALIIcon.sport),
        ("school", "School", "A78BFA", ALIIcon.graduation),
        ("special", "Special", "D291BC", ALIIcon.heart),
        ("other", "Other", "A3C4BC", ALIIcon.calendar),
    ]

    /// Color of events without a category (always the same).
    static let noneColor = ALIColors.familyAccent

    /// Stored in `family_events.emoji` for events saved without a category,
    /// so they aren't mistaken for old events (whose icon gives the category).
    static let noneIcon = "none"

    /// Default category for an old event's icon ("cake" → birthday).
    static func defaultKey(forIcon icon: String) -> String {
        let token = ALIIcon.token(for: icon, fallback: ALIIcon.calendar)
        return defaults.first { $0.icon == token }?.key ?? "other"
    }

    static func icon(forDefaultKey key: String?) -> String {
        defaults.first { $0.key == key }?.icon ?? ALIIcon.calendar
    }

    /// Fixed id of a default category within a family (same on every device).
    static func defaultID(familyID: UUID, key: String) -> UUID {
        let digest = Insecure.MD5.hash(data: Data("event-category:\(familyID.uuidString.lowercased()):\(key)".utf8))
        var bytes = Array(digest)
        bytes[6] = (bytes[6] & 0x0F) | 0x30 // version 3 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

extension FamilyEvent {
    /// The event's category: its own, or (events from before categories)
    /// the default one matching its old icon. nil = no category. (The
    /// category may have been deleted: check it exists.)
    func resolvedCategoryID(familyID: UUID) -> UUID? {
        if let categoryID { return categoryID }
        guard emoji != EventCategory.noneIcon else { return nil }
        return EventCategory.defaultID(familyID: familyID, key: EventCategory.defaultKey(forIcon: emoji))
    }
}
