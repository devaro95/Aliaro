import SwiftUI
import SwiftData

/// Visual root of the app: shows the one-time welcome carousel on first
/// launch, then prompts to create/join a family group before showing the
/// tabs if this device does not yet belong to one.
struct ContentView: View {
    @EnvironmentObject private var familySession: FamilySession
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @Environment(\.modelContext) private var modelContext

    @State private var showSplash = true

    var body: some View {
        Group {
            if showSplash {
                SplashView { showSplash = false }
            } else if dataSync.wasRemovedFromFamily {
                RemovedFromFamilyLoadingView()
            } else if familyService.isCreatingFamily {
                // Shown ahead of `hasJoinedFamily`, which flips to true the
                // moment the group is created remotely — well before its
                // default data and sync are actually set up.
                CreatingFamilyGroupView()
            } else if familyService.isRestoringFamily || familyService.isJoiningFamily {
                // Same idea, right after signing in with email and
                // recovering an existing group — see `restoreMembershipShowingProgress`
                // — or right after asking to join one by QR/code — see
                // `startJoiningFamily`.
                RestoringFamilyGroupView()
            } else if !familySession.hasSeenAppIntro {
                AppIntroView {
                    familySession.markAppIntroSeen()
                    // Ask for notification permission right as onboarding
                    // ends (skip or last page), not at cold launch.
                    PushNotificationManager.shared.requestAuthorizationAndRegister()
                }
            } else if familySession.hasJoinedFamily {
                MainTabContainer()
            } else {
                FamilyOnboardingView()
            }
        }
        .background(ALIColors.background)
        .onChange(of: dataSync.wasRemovedFromFamily) { _, removed in
            guard removed else { return }
            Task { await familyService.handleRemovedFromFamily(modelContext: modelContext, dataSync: dataSync) }
        }
        // Non-blocking, one-time nudge right after creating or joining a
        // group (if not already linked): explains why syncing matters and
        // points to People, rather than asking for the email right here.
        .sheet(isPresented: Binding(
            get: { familyService.showSyncReminder },
            set: { if !$0 { familyService.showSyncReminder = false } }
        )) {
            SyncReminderSheet()
        }
        .alert("Couldn't create family group", isPresented: Binding(
            get: { familyService.createFamilyError != nil },
            set: { if !$0 { familyService.createFamilyError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(familyService.createFamilyError ?? "")
        }
        .alert("Couldn't join family group", isPresented: Binding(
            get: { familyService.joinFamilyError != nil },
            set: { if !$0 { familyService.joinFamilyError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(familyService.joinFamilyError ?? "")
        }
    }
}

/// Shown briefly right after detecting in real time that we've been
/// removed from the group, while the session and local data are cleared
/// (before moving on to "Welcome to Aliaro"), so the screen doesn't look
/// frozen without explanation.
private struct RemovedFromFamilyLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Leaving family group…")
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALIColors.background)
    }
}

/// Shown right after signing in with email while an existing family
/// group (if any) is fetched and synced back onto this device — see
/// `FamilyService.isRestoringFamily` — and reused right after asking to
/// join a group by QR or by code, while its data is fetched and synced
/// for the first time — see `FamilyService.isJoiningFamily`.
private struct RestoringFamilyGroupView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("🏡")
                .font(.system(size: 64))
                .scaleEffect(isAnimating ? 1.08 : 0.96)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: 8) {
                Text("Loading your family group…")
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)
                    .multilineTextAlignment(.center)
                Text("It'll be ready in just a moment.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
            }

            ProgressView()
                .tint(ALIColors.familyAccent)
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALIColors.background)
        .onAppear { isAnimating = true }
    }
}

/// Shown right after the family group is created remotely, while its
/// default data (shopping list, categories) is seeded and sync starts up
/// behind the scenes — see `FamilyService.isCreatingFamily`.
private struct CreatingFamilyGroupView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("🏡")
                .font(.system(size: 64))
                .scaleEffect(isAnimating ? 1.08 : 0.96)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: 8) {
                Text("Creating your family group…")
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)
                    .multilineTextAlignment(.center)
                Text("It'll be ready in just a moment.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
            }

            ProgressView()
                .tint(ALIColors.familyAccent)
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALIColors.background)
        .onAppear { isAnimating = true }
    }
}
