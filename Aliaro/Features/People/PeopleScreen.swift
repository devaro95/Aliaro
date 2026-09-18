import SwiftUI
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
        ScrollView {
            Color.clear.frame(height: 0).trackBottomBarScroll(bottomBarScrollTracker)

            VStack(spacing: 16) {
                ALITopBar(title: "People", accent: ALIColors.peopleAccent) {
                    ALIFloatingButton(accent: ALIColors.peopleAccent) {
                        if isInviteLocked { showPaywall = true } else { showInviteSheet = true }
                    }
                    .scaleEffect(0.72)
                    .aliPremiumLockOverlay(isInviteLocked)
                }

                if let familyName = familySession.familyName {
                    Text(familyName)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                loginBanner

                membersSection

                appFeaturesCard

                historialCard

                #if DEBUG
                debugCard
                #endif

                leaveGroupSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(ALIColors.background)
        .task { await familyService.refreshMembers(modelContext: modelContext) }
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
        if !authSession.isLinked {
            ALICard(containerColor: ALIColors.surfaceVariant) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ALIColors.peopleAccent)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Don't lose this group")
                                .font(ALITypography.bodyLarge)
                                .foregroundStyle(ALIColors.ink)
                            if isCloudBackupLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ALIColors.economiaAccent)
                            }
                        }
                        Text(isCloudBackupLocked
                             ? "Aliaro Premium feature: sign in so you can always get your group back, even after reinstalling the app."
                             : "Sign in so you can always get it back, even after reinstalling the app.")
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                        Button(isCloudBackupLocked ? "Unlock with Premium" : "Sign in") {
                            if isCloudBackupLocked { showPaywall = true } else { showLoginSheet = true }
                        }
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.peopleAccent)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
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
            ALICard {
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        memberRow(member)
                        if index < members.count - 1 {
                            Divider().overlay(ALIColors.outline)
                        }
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
                    memberForPermissions = member
                } label: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(ALIColors.mutedInk)
                }
                .buttonStyle(.plain)
            }
            if canRemove(member) {
                Button {
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
    private var appFeaturesCard: some View {
        Button {
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
    /// who created, edited or deleted what — unless History is currently
    /// premium and this device isn't subscribed, in which case it opens
    /// the paywall instead.
    private var historialCard: some View {
        let isLocked = premium.isLocked(.historial)
        return Button {
            if isLocked { showPaywall = true } else { showHistorialSheet = true }
        } label: {
            ALICard {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ALIColors.peopleAccent)
                        .aliPremiumLockOverlay(isLocked)
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

    private var leaveGroupSection: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                ALIPrimaryButton(
                    text: isLeaving ? "Leaving…" : "Leave family group",
                    accent: ALIColors.error
                ) {
                    showLeaveConfirmation = true
                }
                .disabled(isLeaving)
            }
        }
    }

}
