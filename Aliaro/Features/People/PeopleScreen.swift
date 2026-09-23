import SwiftUI
import StoreKit
import SwiftData

/// "People" tab: who's in the family group, the button to invite
/// someone else by showing a QR code, a way into `AppFeaturesSheet`
/// (admin only can actually change it) to pick which tabs show up in
/// everyone's bottom bar and which one opens first, and the group's
/// "History" of who created, edited or deleted what.
struct PeopleScreen: View {
    @EnvironmentObject private var bottomBarScrollTracker: BottomBarScrollTracker
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var premium: PremiumManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    /// Dismissing the "save your group" banner is per-device, not tied to
    /// the family group — reappears if they ever leave and join another.
    @State private var showLoginSheet = false
    @State private var showInviteSheet = false
    @State private var showFeaturesSheet = false
    @State private var showHistorialSheet = false
    @State private var showPaywall = false
    @State private var showManageSubscription = false
    @State private var showLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var leaveError: String?
    @State private var memberPendingRemoval: FamilyMember?
    @State private var isRemovingMember = false
    @State private var removeMemberError: String?
    @State private var memberForPermissions: FamilyMember?

    #if DEBUG
    @State private var isSeedingMockData = false
    #endif

    var body: some View {
        trackedBody.trackScreen("people")
    }

    @ViewBuilder
    private var trackedBody: some View {
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "People", accent: ALIColors.peopleAccent)

                membersSection

                appFeaturesCard

                historialCard

                if premium.subscriptions.isSubscribed {
                    subscriptionCard
                }

                #if DEBUG
                debugCard
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .task { await familyService.refreshMembers(modelContext: modelContext) }
        .onChange(of: members.count, initial: true) { _, count in
            let me = members.first(where: { $0.isCurrentDevice })
            Track.refreshUserProperties(
                memberCount: count,
                role: me.map { $0.isCreator ? "creator" : ($0.isAdmin ? "admin" : "member") }
            )
        }
        .refreshable { await familyService.refreshMembers(modelContext: modelContext) }
        .sheet(isPresented: $showInviteSheet) {
            InviteQRSheet()
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet(mode: .link)
        }
        .sheet(isPresented: $showFeaturesSheet) {
            AppFeaturesSheet()
        }
        .sheet(isPresented: $showHistorialSheet) {
            HistorialSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(item: $memberForPermissions) { member in
            MemberPermissionsSheet(member: member)
        }
        .alert(
            "Remove \(memberPendingRemoval?.name ?? String(localized: "this person")) from the group?",
            isPresented: Binding(
                get: { memberPendingRemoval != nil },
                set: { if !$0 { memberPendingRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let member = memberPendingRemoval {
                    Task { await removeMember(member) }
                }
            }
            Button("Cancel", role: .cancel) { memberPendingRemoval = nil }
        } message: {
            Text("They will no longer see or share this group's menu, shopping, tasks, calendar and reminders.")
        }
        .alert("Couldn't remove", isPresented: .constant(removeMemberError != nil)) {
            Button("OK", role: .cancel) { removeMemberError = nil }
        } message: {
            Text(removeMemberError ?? "")
        }
        .alert(
            "Leave the family group?",
            isPresented: $showLeaveConfirmation
        ) {
            Button("Leave group", role: .destructive) {
                Task { await leaveGroup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop seeing and sharing \(familySession.familyName ?? String(localized: "this group"))'s menu, shopping, tasks, calendar and reminders. This action can't be undone.")
        }
        .alert("Couldn't leave the group", isPresented: .constant(leaveError != nil)) {
            Button("OK", role: .cancel) { leaveError = nil }
        } message: {
            Text(leaveError ?? "")
        }
    }

    /// Beyond 4 members, inviting another one needs a subscription if
    /// `extraMembers` is currently premium.
    private var isInviteLocked: Bool { members.count >= 4 && premium.isLocked(.extraMembers) }

    /// Only the creator can remove others (never themselves: that's
    /// what "Leave group" is for).
    private func canRemove(_ member: FamilyMember) -> Bool {
        guard !member.isCurrentDevice else { return false }
        return members.first(where: { $0.isCurrentDevice })?.isCreator ?? false
    }

    /// Whether the person on this device can open `MemberPermissionsSheet`
    /// for someone else: the creator can, and so can any admin — except
    /// on the creator's own row, whose permissions can never be changed.
    private func canManagePermissions(_ member: FamilyMember) -> Bool {
        guard !member.isCreator else { return false }
        return members.first(where: { $0.isCurrentDevice })?.canManageOthersPermissions ?? false
    }

    private func removeMember(_ member: FamilyMember) async {
        isRemovingMember = true
        defer { isRemovingMember = false }
        do {
            try await familyService.removeMember(memberID: member.id)
            memberPendingRemoval = nil
        } catch {
            removeMemberError = error.localizedDescription
        }
    }

    private func leaveGroup() async {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await familyService.leaveFamily(modelContext: modelContext, dataSync: dataSync)
        } catch {
            leaveError = error.localizedDescription
        }
    }

    /// Nudge to link an email: without it, this group only lives on this
    /// device, tied to an anonymous id that a reinstall would lose.
    /// Can't be dismissed — only hidden once the device is actually
    /// linked, since losing the group is permanent otherwise. Linking
    /// itself is an Aliaro Premium feature (`cloudBackup`) — tapping
    /// "Sign in" opens the paywall instead when it's locked.
    private var isCloudBackupLocked: Bool { premium.isLocked(.cloudBackup) }

    @ViewBuilder
    private var loginBanner: some View {
        // Footer row of the members card: no second background, just a
        // divider like between members, with a compact action on the right.
        if !authSession.isLinked {
            Divider().overlay(ALIColors.outline)
                .padding(.top, 8)
            HStack(spacing: 12) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ALIColors.peopleAccent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Don't lose this group")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                    Text(isCloudBackupLocked
                         ? "Aliaro Premium feature: sign in so you can always get your group back, even after reinstalling the app."
                         : "Sign in so you can always get it back, even after reinstalling the app.")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button {
                    if isCloudBackupLocked { showPaywall = Track.paywall("cloud_backup_banner") } else {
                        Track.event("login_banner_tap")
                        showLoginSheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isCloudBackupLocked {
                            Image(systemName: "crown.fill").font(.system(size: 11, weight: .bold))
                        }
                        Text(isCloudBackupLocked ? "Unlock" : "Sign in")
                    }
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(isCloudBackupLocked ? ALIColors.sun : ALIColors.peopleAccent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        if members.isEmpty {
            ALIEmptyState(
                emoji: "👋",
                title: "No one else here yet",
                subtitle: "Tap the + to invite your family with a QR code."
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Family group (\(members.count))")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .padding(.leading, 4)
                ALICard {
                    VStack(spacing: 0) {
                        familyHeader
                            .padding(.bottom, 12)
                        Divider().overlay(ALIColors.outline)
                            .padding(.bottom, 8) // same gap as above the "Don't lose" divider
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            memberRow(member)
                            if index < members.count - 1 {
                                Divider().overlay(ALIColors.outline)
                            }
                        }
                        loginBanner
                    }
                }
            }
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        HStack(spacing: 12) {
            Text(member.name)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.ink)
            if member.isCurrentDevice {
                memberBadge("You")
            }
            if member.isCreator {
                memberBadge("Creator")
            } else if member.isAdmin {
                memberBadge("Admin")
            }
            Spacer()
            if canManagePermissions(member) {
                Button {
                    Track.event("member_permissions_open", ["target_is_admin": member.isAdmin])
                    memberForPermissions = member
                } label: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(ALIColors.mutedInk)
                }
                .buttonStyle(.plain)
            }
            if canRemove(member) {
                Button {
                    Track.event("member_remove_tap")
                    memberPendingRemoval = member
                } label: {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .foregroundStyle(ALIColors.error)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    private func memberBadge(_ text: String) -> some View {
        Text(text)
            .font(ALITypography.labelLarge)
            .foregroundStyle(ALIColors.mutedInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ALIColors.surfaceVariant)
            .clipShape(Capsule())
    }

    /// Entry point into `AppFeaturesSheet`. Open to everyone — the sheet
    /// itself is what locks the controls for non-admins.
    /// Only on the device that holds the subscription (the payer): it's
    /// the only one that can manage/cancel it — Apple's own sheet, which
    /// also works for TestFlight/Sandbox purchases.
    private var subscriptionCard: some View {
        Button {
            Track.event("manage_subscription_open")
            showManageSubscription = true
        } label: {
            ALICard {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ALIColors.sun)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aliaro Premium")
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(ALIColors.ink)
                        Text("Manage or cancel your subscription")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk)
                }
            }
        }
        .buttonStyle(.plain)
        .manageSubscriptionsSheet(isPresented: $showManageSubscription)
    }

    private var appFeaturesCard: some View {
        Button {
            Track.event("app_features_open")
            showFeaturesSheet = true
        } label: {
            ALICard {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ALIColors.peopleAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App features")
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(ALIColors.ink)
                        Text("Choose what shows up in the bottom bar")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Entry point into `HistorialSheet`: everyone in the group can see
    /// who created, edited or deleted what. If History is locked it still
    /// opens, as a premium preview with sample data.
    private var historialCard: some View {
        let isLocked = premium.isLocked(.historial)
        return Button {
            Track.event("history_open", ["locked": premium.isLocked(.historial)])
            showHistorialSheet = true
        } label: {
            ALICard {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ALIColors.peopleAccent)
                        .aliPremiumPreviewOverlay(isLocked)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("History")
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(ALIColors.ink)
                        Text("See who created, edited or deleted what")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ALIColors.mutedInk)
                }
            }
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    /// Debug-only: fills every tab with sample content so the app is
    /// ready for App Store screenshots. Local data only, never synced.
    private var debugCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug")
                        .font(ALITypography.bodyLarge)
                        .foregroundStyle(ALIColors.ink)
                    Text("Fills every tab with sample content, for App Store screenshots.")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }
                ALIPrimaryButton(
                    text: isSeedingMockData ? "Adding sample data\u{2026}" : "Seed mock data for screenshots",
                    accent: ALIColors.peopleAccent
                ) {
                    isSeedingMockData = true
                    DebugMockData.seed(modelContext: modelContext)
                    isSeedingMockData = false
                }
                .disabled(isSeedingMockData)

                ALIPrimaryButton(
                    text: "Reset session (sign out, new anonymous id)",
                    accent: ALIColors.error
                ) {
                    Task { await authSession.debugResetSession() }
                }
            }
        }
    }
    #endif

    /// First row of the members card: the group's name, and its two
    /// actions — leave (asks first) and invite someone new.
    private var familyHeader: some View {
        HStack(spacing: 10) {
            Text(familySession.familyName ?? String(localized: "Family group"))
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            leaveGroupButton
            inviteButton
        }
    }

    private var leaveGroupButton: some View {
        Button {
            Track.event("leave_group_tap", ["members": members.count])
            showLeaveConfirmation = true
        } label: {
            Group {
                if isLeaving {
                    ProgressView()
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ALIColors.error)
                }
            }
            .frame(width: 38, height: 38)
            .background(ALIColors.error.opacity(0.12))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isLeaving)
        .accessibilityLabel("Leave family group")
    }

    private var inviteButton: some View {
        Button {
            if isInviteLocked { showPaywall = Track.paywall("invite_member") } else {
                Track.event("invite_tap", ["members": members.count])
                showInviteSheet = true
            }
        } label: {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 38, height: 38)
                .background(ALIColors.peopleAccent)
                .clipShape(Circle())
                .aliPremiumLockOverlay(isInviteLocked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invite")
    }

}
