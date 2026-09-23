import Foundation
import SwiftData
import Supabase

/// Coordinates the remote family group (Supabase) with the local cache
/// (`FamilyMember` in SwiftData) and with the device session.
@MainActor
final class FamilyService: ObservableObject {
    @Published private(set) var isLoading = false
    @Published var lastError: String?
    /// True from the moment the remote family group has been created until
    /// the rest of the setup (local member, default data, sync) finishes
    /// AND at least `minimumCreatingDuration` has elapsed. `ContentView`
    /// shows a friendly "creating your group" screen for as long as this
    /// is true, ahead of `FamilySession.hasJoinedFamily` (which flips to
    /// true immediately, well before that setup is done).
    @Published private(set) var isCreatingFamily = false

    /// Set when `startCreatingFamily` fails. `ContentView` surfaces this
    /// as an alert on top of the "creating your group" screen; once
    /// dismissed, `isCreatingFamily` is already false so the UI falls
    /// back to `FamilyOnboardingView`.
    @Published var createFamilyError: String?

    /// Flips to `true` right after this device creates OR joins a family
    /// group, if it isn't linked to a real account yet, so the UI can
    /// nudge it once to sync via People (so the group survives a
    /// reinstall or a new phone). Reset by whoever consumes it.
    @Published var showSyncReminder = false

    /// Minimum time the "creating your group" screen stays up, regardless
    /// of how fast the setup above actually finishes.
    private static let minimumCreatingDuration: Duration = .seconds(5)

    /// True while recovering an existing family group right after signing
    /// in with email (`restoreMembershipShowingProgress`), so `ContentView`
    /// can show a "loading your family group" screen instead of flashing
    /// the onboarding buttons underneath.
    @Published private(set) var isRestoringFamily = false

    /// Minimum time the "loading your family group" screen stays up,
    /// regardless of how fast the restore actually finishes.
    private static let minimumRestoringDuration: Duration = .seconds(3)

    /// True from the moment this device asks to join a family group (by QR
    /// token or by short code) until the rest of the setup (local member,
    /// members list, settings, sync) finishes AND at least
    /// `minimumJoiningDuration` has elapsed. `ContentView` reuses the same
    /// "loading your family group" screen as `isRestoringFamily` for this,
    /// ahead of `FamilySession.hasJoinedFamily` (which flips to true as
    /// soon as membership is confirmed, well before that setup is done).
    @Published private(set) var isJoiningFamily = false

    /// Set when joining fails. `ContentView` surfaces this as an alert;
    /// once dismissed, `isJoiningFamily` is already false so the UI falls
    /// back to `FamilyOnboardingView`.
    @Published var joinFamilyError: String?

    /// Minimum time the "loading your family group" screen stays up after
    /// joining, regardless of how fast the setup actually finishes.
    private static let minimumJoiningDuration: Duration = .seconds(5)

    let session: FamilySession

    private var settingsChannel: RealtimeChannelV2?
    private var settingsListenTask: Task<Void, Never>?

    init(session: FamilySession) {
        self.session = session
    }

    // MARK: - Create / join

    private struct CreateFamilyResponse: Decodable {
        let familyId: UUID
        let familyName: String
        let memberId: UUID
    }

    /// Kicks off family-group creation and returns immediately:
    /// `isCreatingFamily` flips to `true` synchronously, right here,
    /// before any network call — so the UI can switch to the "creating
    /// your group" screen straight away, and every call below (including
    /// the initial `create-family` request) happens behind that screen
    /// instead of on the name-entry sheet. On failure, `isCreatingFamily`
    /// is cleared and the error is published via `createFamilyError`.
    func startCreatingFamily(familyName: String, myName: String, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) {
        isCreatingFamily = true
        createFamilyError = nil
        Task {
            do {
                try await createFamily(familyName: familyName, myName: myName, modelContext: modelContext, dataSync: dataSync)
            } catch {
                isCreatingFamily = false
                createFamilyError = error.localizedDescription
            }
        }
    }

    private func createFamily(familyName: String, myName: String, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) async throws {
        struct Body: Encodable { let name: String; let deviceId: String; let familyName: String }
        let response: CreateFamilyResponse = try await invokeEdgeFunction(
            "create-family",
            options: FunctionInvokeOptions(body: Body(name: myName, deviceId: session.deviceID, familyName: familyName))
        )
        // isCreatingFamily is already true (set by startCreatingFamily
        // before this call began). Keep the screen up for a minimum
        // duration while the rest of the setup below happens behind it.
        async let minimumWait: Void = Task.sleep(for: Self.minimumCreatingDuration)
        session.setMembership(familyID: response.familyId, memberID: response.memberId, familyName: response.familyName)
        session.setDisabledTabs([]) // a brand-new group starts with every tab on
        PremiumManager.shared.syncFamilyPremiumStatus()
        upsertLocalMember(id: response.memberId, name: myName, isCurrentDevice: true, isCreator: true, modelContext: modelContext)
        // A newly created group has nothing to sync yet, but we start
        // anyway so it's left listening in real time.
        await dataSync.startAll(familyID: response.familyId, currentMemberID: response.memberId, modelContext: modelContext)
        await startSettingsSync(familyID: response.familyId)
        // Every family starts out with a default shopping list.
        let defaultShoppingList = ShoppingList(name: "Shopping list", position: 0)
        modelContext.insert(defaultShoppingList)
        dataSync.pushShoppingList(defaultShoppingList, familyID: response.familyId)
        // ...and its 10 default spending categories, editable/extendable later.
        for preset in ExpenseCategory.defaults {
            let category = ExpenseCategory(name: preset.name, emoji: preset.emoji, isDefault: true)
            modelContext.insert(category)
            dataSync.pushCategory(category, familyID: response.familyId)
        }
        try? modelContext.save()
        try? await minimumWait
        isCreatingFamily = false
        // Only worth asking to save the group if this device isn't
        // already linked to a real account — e.g. it left a previous
        // group and created a new one, so the same email already covers
        // it (see AuthSession).
        showSyncReminder = !AuthSession.shared.isLinked
    }

    private struct JoinFamilyResponse: Decodable {
        let familyId: UUID
        let familyName: String
        let memberId: UUID
    }

    /// Kicks off joining by QR token and returns immediately: `isJoiningFamily`
    /// flips to `true` synchronously, right here, before any network call —
    /// so `ContentView` can switch to the "loading your family group" screen
    /// straight away, the same way `startCreatingFamily` does for creating.
    /// On failure, `isJoiningFamily` is cleared and the error is published
    /// via `joinFamilyError`.
    func startJoiningFamily(token: String, myName: String, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) {
        isJoiningFamily = true
        joinFamilyError = nil
        Task {
            do {
                try await joinFamily(token: token, myName: myName, modelContext: modelContext, dataSync: dataSync)
            } catch {
                isJoiningFamily = false
                joinFamilyError = error.localizedDescription
            }
        }
    }

    /// Same as above, but resolving the invite by its short code (6 characters,
    /// caduca a los 15 min) instead of the QR token.
    func startJoiningFamily(code: String, myName: String, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) {
        isJoiningFamily = true
        joinFamilyError = nil
        Task {
            do {
                try await joinFamily(code: code, myName: myName, modelContext: modelContext, dataSync: dataSync)
            } catch {
                isJoiningFamily = false
                joinFamilyError = error.localizedDescription
            }
        }
    }

    private func joinFamily(token: String, myName: String, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) async throws {
        struct Body: Encodable { let token: String; let name: String; let deviceId: String }
        let response: JoinFamilyResponse = try await invokeEdgeFunction(
            "join-family",
            options: FunctionInvokeOptions(body: Body(token: token, name: myName, deviceId: session.deviceID))
        )
        try await finishJoining(response: response, myName: myName, modelContext: modelContext, dataSync: dataSync)
    }

    private func joinFamily(code: String, myName: String, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) async throws {
        struct Body: Encodable { let code: String; let name: String; let deviceId: String }
        let response: JoinFamilyResponse = try await invokeEdgeFunction(
            "join-family",
            options: FunctionInvokeOptions(body: Body(code: code, name: myName, deviceId: session.deviceID))
        )
        try await finishJoining(response: response, myName: myName, modelContext: modelContext, dataSync: dataSync)
    }

    private func finishJoining(response: JoinFamilyResponse, myName: String, modelContext: ModelContext, dataSync: AppDataSyncCoordinator) async throws {
        // isJoiningFamily is already true (set by startJoiningFamily before
        // this call began). Keep the screen up for a minimum duration while
        // the rest of the setup below happens behind it.
        async let minimumWait: Void = Task.sleep(for: Self.minimumJoiningDuration)
        session.setMembership(familyID: response.familyId, memberID: response.memberId, familyName: response.familyName)
        PremiumManager.shared.syncFamilyPremiumStatus()
        upsertLocalMember(id: response.memberId, name: myName, isCurrentDevice: true, isCreator: false, modelContext: modelContext)
        await refreshMembers(modelContext: modelContext)
        // Joining an existing group inherits its configuration, same as
        // menu/calendar/etc: fetch which tabs the admin already hid.
        await refreshFamilySettings()
        await startSettingsSync(familyID: response.familyId)
        // Fetches everything the group already has (menu, calendar, shopping
        // list, tasks, reminders) instead of waiting for the tab view to
        // trigger the startup on its own: joining should leave the app
        // with the data loaded right away.
        await dataSync.startAll(familyID: response.familyId, currentMemberID: response.memberId, modelContext: modelContext)
        try? await minimumWait
        isJoiningFamily = false
        // Same nudge as creating a group: joining one is just as much at
        // risk of being lost on this device alone if it isn't linked yet.
        showSyncReminder = !AuthSession.shared.isLinked
    }

    // MARK: - Restore (signing in on a new/reinstalled device)

    private struct RestoreMembershipResponse: Decodable {
        let found: Bool
        let familyId: UUID?
        let familyName: String?
        let memberId: UUID?
        let memberName: String?
        let isCreator: Bool?
        let isAdmin: Bool?
        let restrictedPermissions: [String]?
    }

    /// After signing in to a linked (non-anonymous) account, looks up
    /// whether it's already tied to a family group and, if so, restores
    /// this device into it — same effect as joining, but recovering the
    /// existing group instead of creating/joining a new one. Returns
    /// `true` if a group was found and restored.
    func restoreMembership(modelContext: ModelContext, dataSync: AppDataSyncCoordinator) async throws -> Bool {
        struct Body: Encodable { let deviceId: String }
        let response: RestoreMembershipResponse = try await supabase.functions.invoke(
            "restore-membership",
            options: FunctionInvokeOptions(body: Body(deviceId: session.deviceID))
        )
        guard response.found,
              let familyId = response.familyId,
              let familyName = response.familyName,
              let memberId = response.memberId,
              let memberName = response.memberName else {
            return false
        }
        session.setMembership(familyID: familyId, memberID: memberId, familyName: familyName)
        PremiumManager.shared.syncFamilyPremiumStatus()
        upsertLocalMember(
            id: memberId, name: memberName, isCurrentDevice: true,
            isCreator: response.isCreator ?? false, isAdmin: response.isAdmin ?? false,
            restrictedPermissions: response.restrictedPermissions ?? [], modelContext: modelContext
        )
        await refreshMembers(modelContext: modelContext)
        await refreshFamilySettings()
        await startSettingsSync(familyID: familyId)
        await dataSync.startAll(familyID: familyId, currentMemberID: memberId, modelContext: modelContext)
        return true
    }

    /// Same as `restoreMembership`, but drives `isRestoringFamily` around
    /// it so `ContentView` can show a "loading your family group" screen
    /// — kept up for at least `minimumRestoringDuration`, longer if the
    /// restore itself takes more than that. Use this from UI flows (e.g.
    /// right after signing in with email); `restoreMembership` alone is
    /// for the silent, no-visible-loading check at cold launch.
    func restoreMembershipShowingProgress(modelContext: ModelContext, dataSync: AppDataSyncCoordinator) async throws -> Bool {
        isRestoringFamily = true
        async let minimumWait: Void = Task.sleep(for: Self.minimumRestoringDuration)
        do {
            let found = try await restoreMembership(modelContext: modelContext, dataSync: dataSync)
            try? await minimumWait
            isRestoringFamily = false
            return found
        } catch {
            try? await minimumWait
            isRestoringFamily = false
            throw error
        }
    }

    // MARK: - Invite (QR)

    struct InviteResponse: Decodable {
        let token: String
        // 6-character code (letters/digits, no ambiguous characters) as an
        // alternative to scanning the QR: typed in manually, same 15-min expiry.
        let shortCode: String
        // Decoded as a String (not Date): the default decoder used by
        // `functions.invoke` doesn't understand the fractional-second format
        // that Postgres returns for a timestamptz. Converted to Date separately.
        let expiresAt: String

        var expiresAtDate: Date {
            AliaroDateFormatting.fractional.date(from: expiresAt)
                ?? AliaroDateFormatting.plain.date(from: expiresAt)
                ?? .now
        }
    }

    /// Looks up the name of the group an invite token points to without
    /// consuming it, so it can be shown in the dialog before confirming the
    /// join (QR or link).
    func inviteInfo(token: String) async throws -> String {
        struct Body: Encodable { let token: String }
        struct Response: Decodable { let familyName: String }
        let response: Response = try await invokeEdgeFunction(
            "invite-info",
            options: FunctionInvokeOptions(body: Body(token: token))
        )
        return response.familyName
    }

    /// Same as above, resolving by the 6-character short code instead of the QR token.
    /// Sends the device id too: the server uses it to rate-limit repeated
    /// wrong guesses (brute-forcing a short code) from the same device.
    func inviteInfo(code: String) async throws -> String {
        struct Body: Encodable { let code: String; let deviceId: String }
        struct Response: Decodable { let familyName: String }
        let response: Response = try await invokeEdgeFunction(
            "invite-info",
            options: FunctionInvokeOptions(body: Body(code: code, deviceId: session.deviceID))
        )
        return response.familyName
    }

    func createInvite() async throws -> InviteResponse {
        guard let familyID = session.familyID, let memberID = session.memberID else {
            throw NSError(domain: "Aliaro", code: 0, userInfo: [NSLocalizedDescriptionKey: "You don't belong to a family group yet"])
        }
        struct Body: Encodable { let familyId: UUID; let memberId: UUID }
        return try await invokeEdgeFunction(
            "create-invite",
            options: FunctionInvokeOptions(body: Body(familyId: familyID, memberId: memberID))
        )
    }

    // MARK: - Members

    private struct RemoteMember: Decodable {
        let id: UUID
        let name: String
        let emoji: String
        let is_creator: Bool
        let is_admin: Bool
        let restricted_permissions: [String]
        // String, not Date: PostgREST's default decoder doesn't support
        // Postgres's fractional-second format. Converted separately.
        let joined_at: String

        var joinedAtDate: Date {
            AliaroDateFormatting.fractional.date(from: joined_at)
                ?? AliaroDateFormatting.plain.date(from: joined_at)
                ?? .now
        }
    }

    /// Manual refresh (pull-to-refresh) of the member list. The live listing
    /// is kept up to date in real time by `AppDataSyncCoordinator`; this is
    /// just a fallback to force a manual reload.
    func refreshMembers(modelContext: ModelContext) async {
        guard let familyID = session.familyID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let remoteMembers: [RemoteMember] = try await supabase
                .from("family_members")
                .select("id,name,emoji,is_creator,is_admin,restricted_permissions,joined_at")
                .eq("family_id", value: familyID)
                .order("joined_at")
                .execute()
                .value
            for remote in remoteMembers {
                upsertLocalMember(
                    id: remote.id,
                    name: remote.name,
                    emoji: remote.emoji,
                    joinedAt: remote.joinedAtDate,
                    isCurrentDevice: remote.id == session.memberID,
                    isCreator: remote.is_creator,
                    isAdmin: remote.is_admin,
                    restrictedPermissions: remote.restricted_permissions,
                    modelContext: modelContext
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func upsertLocalMember(
        id: UUID,
        name: String,
        emoji: String = "🙂",
        joinedAt: Date = .now,
        isCurrentDevice: Bool,
        isCreator: Bool,
        isAdmin: Bool = false,
        restrictedPermissions: [String] = [],
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = name
            existing.emoji = emoji
            existing.isCurrentDevice = isCurrentDevice
            existing.isCreator = isCreator
            existing.isAdmin = isAdmin
            existing.restrictedPermissions = restrictedPermissions
        } else {
            let member = FamilyMember(
                id: id, name: name, emoji: emoji, createdAt: joinedAt, isCurrentDevice: isCurrentDevice,
                isCreator: isCreator, isAdmin: isAdmin, restrictedPermissions: restrictedPermissions
            )
            modelContext.insert(member)
        }
    }

    // MARK: - RLS self-heal (link this device's auth_user_id)

    /// Called once per launch, right after `AuthSession.ensureSession()`,
    /// whenever this device already belongs to a family group. Supabase
    /// RLS now scopes every table read/write to `family_members.auth_user_id
    /// = auth.uid()`, but that column is only stamped at create/join time
    /// (`create-family`/`join-family`) — a member row created before the
    /// login-opcional feature existed has it `null`, or a device that lost
    /// its Keychain session could drift out of sync with it. This calls
    /// the `link-member-auth` edge function (service role, so it isn't
    /// itself blocked by RLS) to (re)stamp the row for THIS device's
    /// current session id. Idempotent and cheap; best-effort — a failure
    /// here just means sync stays broken until the next successful call,
    /// same as any other transient network issue, so it's never surfaced
    /// as a user-facing error.
    func linkAuthIfNeeded() async {
        guard let familyID = session.familyID, let memberID = session.memberID else { return }
        struct Body: Encodable { let familyId: UUID; let memberId: UUID; let deviceId: String }
        struct LinkResponse: Decodable { let ok: Bool; let updated: Bool }
        do {
            let _: LinkResponse = try await invokeEdgeFunction(
                "link-member-auth",
                options: FunctionInvokeOptions(body: Body(familyId: familyID, memberId: memberID, deviceId: session.deviceID))
            )
        } catch {
            print("⚠️ linkAuthIfNeeded failed (will retry next launch): \(error)")
        }
    }

    // MARK: - Remove a member (creator only)

    /// The group's creator removes another member. The removed device
    /// finds out in real time (`AppDataSyncCoordinator.wasRemovedFromFamily`)
    /// and clears its own session — here we only need to delete the record.
    func removeMember(memberID: UUID) async throws {
        guard let familyID = session.familyID, let requesterID = session.memberID else {
            throw NSError(domain: "Aliaro", code: 0, userInfo: [NSLocalizedDescriptionKey: "You don't belong to a family group yet"])
        }
        struct Body: Encodable { let familyId: UUID; let requesterMemberId: UUID; let targetMemberId: UUID }
        struct OKResponse: Decodable { let ok: Bool }
        let _: OKResponse = try await invokeEdgeFunction(
            "remove-family-member",
            options: FunctionInvokeOptions(body: Body(familyId: familyID, requesterMemberId: requesterID, targetMemberId: memberID))
        )
    }

    // MARK: - Permissions (creator, or an admin, only — never the creator's own)

    /// Changes what a member is allowed to do: the creator can change
    /// anyone's permissions (including making/unmaking admins); an admin
    /// can change anyone's except the creator's. The target device finds
    /// out in real time (`family_members` UPDATE), same as any other
    /// synced field.
    func updateMemberPermissions(targetMemberID: UUID, restrictedPermissions: Set<String>, isAdmin: Bool) async throws {
        guard let familyID = session.familyID, let requesterID = session.memberID else {
            throw NSError(domain: "Aliaro", code: 0, userInfo: [NSLocalizedDescriptionKey: "You don't belong to a family group yet"])
        }
        struct Body: Encodable {
            let familyId: UUID
            let requesterMemberId: UUID
            let targetMemberId: UUID
            let restrictedPermissions: [String]
            let isAdmin: Bool
        }
        struct PermissionsResponse: Decodable { let ok: Bool; let restrictedPermissions: [String]; let isAdmin: Bool }
        let _: PermissionsResponse = try await invokeEdgeFunction(
            "update-member-permissions",
            options: FunctionInvokeOptions(body: Body(
                familyId: familyID, requesterMemberId: requesterID, targetMemberId: targetMemberID,
                restrictedPermissions: Array(restrictedPermissions), isAdmin: isAdmin
            ))
        )
    }

    // MARK: - We've been removed (detected in real time)

    /// Clears the session and local data when `AppDataSyncCoordinator`
    /// detects that our own member has disappeared from `family_members`
    /// (the creator has removed us from the group).
    func handleRemovedFromFamily(modelContext: ModelContext, dataSync: AppDataSyncCoordinator) async {
        await dataSync.stopAll()
        await stopSettingsSync()
        clearAllLocalData(modelContext: modelContext)
        session.clearMembership()
        dataSync.wasRemovedFromFamily = false
    }

    // MARK: - Leave the group

    /// Removes this device from the family group: notifies the backend
    /// (which notifies the rest), clears the local session and all cached
    /// data (members and synced content) to leave the app like a fresh install.
    func leaveFamily(modelContext: ModelContext, dataSync: AppDataSyncCoordinator) async throws {
        guard let familyID = session.familyID, let memberID = session.memberID else { return }
        struct Body: Encodable { let familyId: UUID; let memberId: UUID }
        struct OKResponse: Decodable { let ok: Bool }
        let _: OKResponse = try await invokeEdgeFunction(
            "leave-family",
            options: FunctionInvokeOptions(body: Body(familyId: familyID, memberId: memberID))
        )
        await dataSync.stopAll()
        await stopSettingsSync()
        clearAllLocalData(modelContext: modelContext)
        session.clearMembership()
    }

    private func clearAllLocalData(modelContext: ModelContext) {
        let types: [any PersistentModel.Type] = [
            FamilyMember.self, Dish.self, MealPlanEntry.self, GroceryItem.self,
            ShoppingList.self, ShoppingListEntry.self, HouseTask.self, HouseTaskLog.self,
            FamilyEvent.self, Reminder.self, Expense.self, ExpenseCategory.self, ActivityLogEntry.self,
            ExpenseArchive.self,
        ]
        for type in types {
            try? modelContext.delete(model: type)
        }
        try? modelContext.save()
    }

    // MARK: - Family settings (which tabs show up in the bottom bar, and which one opens first)

    private struct RemoteFamilySettings: Decodable {
        let disabled_tabs: [String]
        let start_tab: String?
        let is_premium: Bool
    }

    /// Fetches which tabs the admin has turned off (and which one is the
    /// group's start tab) for this family and updates the session. Used
    /// on launch and right after joining a group.
    func refreshFamilySettings() async {
        guard let familyID = session.familyID else { return }
        do {
            let row: RemoteFamilySettings = try await supabase
                .from("families")
                .select("disabled_tabs,start_tab,is_premium")
                .eq("id", value: familyID)
                .single()
                .execute()
                .value
            session.setDisabledTabs(Set(row.disabled_tabs))
            session.setStartTab(row.start_tab)
            session.setFamilyPremium(row.is_premium)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Admin-only: turns tabs on/off in the bottom bar for the whole
    /// family group. `tabs` is the full set of `AppTab.settingsKey`
    /// values that should be hidden.
    func updateDisabledTabs(_ tabs: Set<String>) async throws {
        try await updateFamilySettings(disabledTabs: tabs, startTab: session.startTab)
    }

    /// Admin-only: picks which tab the app opens on for every device in
    /// the group. `nil` means no preference (falls back to the first
    /// visible tab).
    func updateStartTab(_ tab: String?) async throws {
        try await updateFamilySettings(disabledTabs: session.disabledTabs, startTab: tab)
    }

    private func updateFamilySettings(disabledTabs: Set<String>, startTab: String?) async throws {
        guard let familyID = session.familyID, let memberID = session.memberID else {
            throw NSError(domain: "Aliaro", code: 0, userInfo: [NSLocalizedDescriptionKey: "You don't belong to a family group yet"])
        }
        struct Body: Encodable { let familyId: UUID; let requesterMemberId: UUID; let disabledTabs: [String]; let startTab: String? }
        struct SettingsResponse: Decodable { let ok: Bool; let disabledTabs: [String]; let startTab: String? }
        let response: SettingsResponse = try await invokeEdgeFunction(
            "update-family-settings",
            options: FunctionInvokeOptions(body: Body(familyId: familyID, requesterMemberId: memberID, disabledTabs: Array(disabledTabs), startTab: startTab))
        )
        session.setDisabledTabs(Set(response.disabledTabs))
        session.setStartTab(response.startTab)
    }

    /// Keeps `FamilySession.disabledTabs`/`startTab` live-updated when the
    /// admin changes them from another device. Mirrors `RemoteSync`'s
    /// channel setup, but `families` has no `family_id` column to filter
    /// on (its own `id` is the family), so it isn't a `FamilySynced` table.
    func startSettingsSync(familyID: UUID) async {
        await stopSettingsSync()
        let newChannel = supabase.channel("sync-family-settings-\(familyID.uuidString)")
        let updates = newChannel.postgresChange(UpdateAction.self, schema: "public", table: "families", filter: "id=eq.\(familyID.uuidString)")
        await newChannel.subscribe()
        settingsChannel = newChannel

        settingsListenTask = Task { [weak self] in
            for await change in updates {
                guard let data = try? JSONEncoder().encode(change.record),
                      let row = try? JSONDecoder().decode(RemoteFamilySettings.self, from: data) else { continue }
                await MainActor.run {
                    self?.session.setDisabledTabs(Set(row.disabled_tabs))
                    self?.session.setStartTab(row.start_tab)
                    self?.session.setFamilyPremium(row.is_premium)
                }
            }
        }
    }

    func stopSettingsSync() async {
        settingsListenTask?.cancel()
        settingsListenTask = nil
        if let settingsChannel {
            await supabase.removeChannel(settingsChannel)
        }
        settingsChannel = nil
    }

    // MARK: - Push

    func registerPushToken(_ apnsToken: String) async {
        guard let memberID = session.memberID else { return }
        struct Body: Encodable { let memberId: UUID; let apnsToken: String }
        struct OKResponse: Decodable { let ok: Bool }
        do {
            let _: OKResponse = try await invokeEdgeFunction(
                "register-push-token",
                options: FunctionInvokeOptions(body: Body(memberId: memberID, apnsToken: apnsToken))
            )
        } catch {
            lastError = error.localizedDescription
        }
    }
}
