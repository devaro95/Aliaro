import Foundation
import SwiftData

/// A person in the family group. It can be a local label (to direct a
/// reminder to someone without the app) or a real person, synced from
/// Supabase after creating or joining a group by QR code.
/// `isCurrentDevice` marks the person on this device.
@Model
final class FamilyMember {
    var id: UUID
    var name: String
    var emoji: String
    var createdAt: Date
    var isCurrentDevice: Bool
    /// Who created the family group. Only this person can remove
    /// other members from the group, and their own permissions can
    /// never be restricted — they always have every permission.
    var isCreator: Bool = false
    /// Promoted by the creator (or another admin): has every
    /// permission, same as the creator, and can also change other
    /// members' permissions — except the creator's.
    var isAdmin: Bool = false
    /// `FamilyPermission.rawValue`s this member does NOT have. Ignored
    /// for the creator and for admins, who always have everything.
    var restrictedPermissions: [String] = []

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🙂",
        createdAt: Date = .now,
        isCurrentDevice: Bool = false,
        isCreator: Bool = false,
        isAdmin: Bool = false,
        restrictedPermissions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.createdAt = createdAt
        self.isCurrentDevice = isCurrentDevice
        self.isCreator = isCreator
        self.isAdmin = isAdmin
        self.restrictedPermissions = restrictedPermissions
    }

    /// Whether this member has the given permission: the creator and
    /// any admin always do, everyone else does unless it's been
    /// specifically turned off for them.
    func can(_ permission: FamilyPermission) -> Bool {
        isCreator || isAdmin || !restrictedPermissions.contains(permission.rawValue)
    }

    /// Whether this member can open `MemberPermissionsSheet` to change
    /// OTHER members' permissions (never the creator's own).
    var canManageOthersPermissions: Bool { isCreator || isAdmin }
}

extension ModelContext {
    /// Name of the group member with this id, if it's in the local cache.
    /// Used when creating shared items to record who created them.
    func familyMemberName(id: UUID) -> String? {
        let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == id })
        return (try? fetch(descriptor))?.first?.name
    }
}
