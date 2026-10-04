import SwiftUI
import SwiftData

/// Shown right after logging in / creating an account when the account
/// doesn't belong to any family group yet: create a new one or join an
/// existing one (QR or code).
struct FamilyOnboardingView: View {
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var pendingInvite: PendingInvite
    @Environment(\.modelContext) private var modelContext
    @State private var route: Route?
    /// True until we've silently checked whether the signed-in account
    /// already belongs to a family group (e.g. logging in on a new or
    /// reinstalled device). Kept `true` on a match so this view never
    /// flashes the create/join buttons before `ContentView` swaps to
    /// `MainTabContainer`.
    @State private var isCheckingForExistingGroup = true
    /// Resolving an invite link opened from outside the app (QR scanned
    /// with the iPhone Camera) — see `joinPendingInviteIfNeeded`.
    @State private var isOpeningInvite = false
    /// Invite link whose group needs the person's name before joining
    /// (only when the account has no name of its own).
    @State private var inviteNeedingName: InviteNeedingName?
    @State private var inviteErrorMessage: String?

    private struct InviteNeedingName: Identifiable {
        let token: String
        let familyName: String
        var id: String { token }
    }

    private enum Route: Identifiable {
        case createName
        case scanQR
        case joinByCode

        var id: String {
            switch self {
            case .createName: return "createName"
            case .scanQR: return "scanQR"
            case .joinByCode: return "joinByCode"
            }
        }
    }

    var body: some View {
        trackedBody.trackScreen("family_onboarding")
    }

    @ViewBuilder
    private var trackedBody: some View {
        Group {
            if isCheckingForExistingGroup || isOpeningInvite {
                checkingView
            } else {
                onboardingView
            }
        }
        .task {
            // If this account already belongs to a family group — the
            // common case right after logging in — restore it behind the
            // "loading your family group" screen, so Home appears with
            // everything already loaded. No group (or any failure) just
            // falls through to the normal create/join screen.
            // Unstructured Task: this view is swapped out as soon as the
            // loading screen appears, which would cancel `.task`'s work.
            let familyService = familyService, modelContext = modelContext, dataSync = dataSync
            _ = try? await Task {
                try await familyService.restoreMembership(modelContext: modelContext, dataSync: dataSync, showingProgress: true)
            }.value
            isCheckingForExistingGroup = false
            joinPendingInviteIfNeeded()
        }
        // Invite link opened while this screen is already showing.
        .onChange(of: pendingInvite.token) { _, _ in
            joinPendingInviteIfNeeded()
        }
        .sheet(item: $inviteNeedingName) { invite in
            NameEntrySheet(title: "What's your name?", confirmTitle: "Join group", joiningFamilyName: invite.familyName) { name in
                pendingInvite.clear()
                familyService.startJoiningFamily(token: invite.token, myName: name, modelContext: modelContext, dataSync: dataSync)
            }
        }
        .alert("Couldn't join family group", isPresented: Binding(
            get: { inviteErrorMessage != nil },
            set: { if !$0 { inviteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inviteErrorMessage ?? "")
        }
    }

    /// Joins the group of an invite link opened from outside the app (QR
    /// scanned with the iPhone Camera), straight away — this runs as soon
    /// as the person is signed in and known to have no group, whether they
    /// just logged in, signed up or already had the app open. The member's
    /// name is always the account's.
    private func joinPendingInviteIfNeeded() {
        guard let token = pendingInvite.token,
              !FamilySession.shared.hasJoinedFamily,
              !isCheckingForExistingGroup, !isOpeningInvite,
              !familyService.isJoiningFamily, !familyService.isRestoringFamily else { return }
        route = nil
        isOpeningInvite = true
        Task {
            defer { isOpeningInvite = false }
            do {
                let familyName = try await familyService.inviteInfo(token: token)
                Track.event("join_invite_checked", ["method": "link", "valid": true])
                if let myName = authSession.displayName {
                    pendingInvite.clear()
                    familyService.startJoiningFamily(token: token, myName: myName, modelContext: modelContext, dataSync: dataSync)
                } else {
                    inviteNeedingName = InviteNeedingName(token: token, familyName: familyName)
                }
            } catch {
                Track.event("join_invite_checked", ["method": "link", "valid": false])
                pendingInvite.clear()
                inviteErrorMessage = error.localizedDescription
            }
        }
    }

    private var checkingView: some View {
        VStack {
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALIColors.background)
    }

    private var onboardingView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                ALIIconView(icon: ALIIcon.home, size: 52)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Welcome to")
                        .font(ALITypography.headlineLarge)
                        .foregroundStyle(ALIColors.ink)
                    AliaroWordmark(size: 26)
                }
                Text("Everything you organize here is shared with your family group.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                ALIPrimaryButton(text: "Create my family group", accent: ALIColors.familyAccent) {
                    Track.event("onboarding_choice", ["choice": "create"])
                    route = .createName
                }
                ALISecondaryButton(text: "Join with a QR code") {
                    Track.event("onboarding_choice", ["choice": "join_qr"])
                    route = .scanQR
                }
                ALITextButton(text: "Join with a code") {
                    Track.event("onboarding_choice", ["choice": "join_code"])
                    route = .joinByCode
                }
                ALITextButton(text: "Not \(authSession.email ?? "you")? Log out") {
                    Track.event("onboarding_choice", ["choice": "logout"])
                    Task { await authSession.signOut() }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALIColors.background)
        .sheet(item: $route) { route in
            switch route {
            case .createName:
                CreateFamilySheet { familyName, myName in
                    familyService.startCreatingFamily(familyName: familyName, myName: myName, modelContext: modelContext, dataSync: dataSync)
                }
            case .scanQR:
                JoinByQRSheet()
            case .joinByCode:
                JoinByCodeSheet()
            }
        }
    }
}
