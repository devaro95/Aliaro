import Foundation

/// Local device identity within a family group in Supabase.
/// One device = one person (no accounts or login). Stored in
/// UserDefaults: not sensitive data, good enough for a household group.
@MainActor
final class FamilySession: ObservableObject {
    static let shared = FamilySession()

    @Published private(set) var deviceID: String
    @Published private(set) var familyID: UUID?
    @Published private(set) var memberID: UUID?
    @Published private(set) var familyName: String?
    /// `AppTab.settingsKey` values the admin has turned off for this
    /// family group — everything not in here shows in the bottom bar.
    /// Cached locally so the bar renders correctly before the network
    /// catches up, kept live via `FamilyService.startSettingsSync`.
    @Published private(set) var disabledTabs: Set<String>
    /// `AppTab.settingsKey` of the tab the app should open on for every
    /// device in the group, chosen by the admin. `nil` means no
    /// preference (falls back to the first visible tab).
    @Published private(set) var startTab: String?
    /// Whether this family group has an active Aliaro Premium
    /// subscription (from *any* member's device, not just this one) —
    /// `families.is_premium`, synced by `FamilyService` the same way as
    /// `disabledTabs`/`startTab`. Once true, every device in the group
    /// sees premium features unlocked, not just the one that subscribed.
    @Published private(set) var isFamilyPremium: Bool
    /// Whether the one-time welcome carousel (`AppIntroView`) has already
    /// been shown on this device. Independent of family membership: stays
    /// `true` even after leaving a group, so it is only ever shown once.
    @Published private(set) var hasSeenAppIntro: Bool

    private enum Keys {
        static let deviceID = "aliaro.deviceID"
        static let familyID = "aliaro.familyID"
        static let memberID = "aliaro.memberID"
        static let familyName = "aliaro.familyName"
        static let disabledTabs = "aliaro.disabledTabs"
        static let startTab = "aliaro.startTab"
        static let isFamilyPremium = "aliaro.isFamilyPremium"
        static let hasSeenAppIntro = "aliaro.hasSeenAppIntro"
    }

    private let defaults = UserDefaults.standard

    var hasJoinedFamily: Bool { familyID != nil && memberID != nil }

    private init() {
        if let existing = defaults.string(forKey: Keys.deviceID) {
            deviceID = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: Keys.deviceID)
            deviceID = generated
        }
        if let familyIDString = defaults.string(forKey: Keys.familyID) {
            familyID = UUID(uuidString: familyIDString)
        }
        if let memberIDString = defaults.string(forKey: Keys.memberID) {
            memberID = UUID(uuidString: memberIDString)
        }
        familyName = defaults.string(forKey: Keys.familyName)
        disabledTabs = Set(defaults.stringArray(forKey: Keys.disabledTabs) ?? [])
        startTab = defaults.string(forKey: Keys.startTab)
        isFamilyPremium = defaults.bool(forKey: Keys.isFamilyPremium)
        hasSeenAppIntro = defaults.bool(forKey: Keys.hasSeenAppIntro)
    }

    func setMembership(familyID: UUID, memberID: UUID, familyName: String) {
        self.familyID = familyID
        self.memberID = memberID
        self.familyName = familyName
        defaults.set(familyID.uuidString, forKey: Keys.familyID)
        defaults.set(memberID.uuidString, forKey: Keys.memberID)
        defaults.set(familyName, forKey: Keys.familyName)
    }

    /// Updates which tabs are hidden from the bottom bar for this family
    /// group. Called from `FamilyService` after fetching/pushing/receiving
    /// (real time) the family's settings.
    func setDisabledTabs(_ tabs: Set<String>) {
        disabledTabs = tabs
        defaults.set(Array(tabs), forKey: Keys.disabledTabs)
    }

    /// Updates the group's chosen start tab (`nil` clears the preference).
    /// Called from `FamilyService` after fetching/pushing/receiving (real
    /// time) the family's settings.
    func setStartTab(_ tab: String?) {
        startTab = tab
        if let tab {
            defaults.set(tab, forKey: Keys.startTab)
        } else {
            defaults.removeObject(forKey: Keys.startTab)
        }
    }

    /// Updates whether this family group currently has an active Aliaro
    /// Premium subscription (called by `FamilyService` after
    /// fetching/pushing/receiving — real time — the family's settings).
    func setFamilyPremium(_ isPremium: Bool) {
        isFamilyPremium = isPremium
        defaults.set(isPremium, forKey: Keys.isFamilyPremium)
    }

    /// Marks the welcome carousel as seen, so it never shows again on this device.
    func markAppIntroSeen() {
        hasSeenAppIntro = true
        defaults.set(true, forKey: Keys.hasSeenAppIntro)
    }

    /// Clears this device's family group membership (when leaving the group).
    func clearMembership() {
        familyID = nil
        memberID = nil
        familyName = nil
        disabledTabs = []
        startTab = nil
        isFamilyPremium = false
        defaults.removeObject(forKey: Keys.familyID)
        defaults.removeObject(forKey: Keys.memberID)
        defaults.removeObject(forKey: Keys.familyName)
        defaults.removeObject(forKey: Keys.disabledTabs)
        defaults.removeObject(forKey: Keys.startTab)
        defaults.removeObject(forKey: Keys.isFamilyPremium)
    }
}
