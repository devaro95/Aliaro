import SwiftUI
import SwiftData

/// Entry gate when the device doesn't yet belong to any family group:
/// create a new one or join by scanning someone else's QR code.
struct FamilyOnboardingView: View {
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var dataSync: AppDataSyncCoordinator
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.modelContext) private var modelContext
    @State private var route: Route?
    @State private var isRestoring = false
    @State private var showNoGroupFoundAlert = false
    /// True right after launch, before we've silently checked whether this
    /// device (its Supabase session — anonymous ones included, since that
    /// survives an app reinstall in the Keychain — or a linked account)
    /// already belongs to a family group. Kept `true` on a match so this
    /// view never flashes the create/join buttons before `ContentView`
    /// swaps to `MainTabContainer`.
    @State private var isCheckingForExistingGroup = true

    private enum Route: Identifiable {
        case createName
        case scanQR
        case joinByCode
        case login

        var id: String {
            switch self {
            case .createName: return "createName"
            case .scanQR: return "scanQR"
            case .joinByCode: return "joinByCode"
            case .login: return "login"
            }
        }
    }

    var body: some View {
        Group {
            if isCheckingForExistingGroup {
                checkingView
            } else {
                onboardingView
            }
        }
        .task {
            // Silent, best-effort: if this session (anonymous or linked)
            // already owns a family group — the common case right after
            // reinstalling on the same device — drop straight into it
            // instead of showing "create/join". Any failure just falls
            // through to the normal onboarding screen.
            defer { isCheckingForExistingGroup = false }
            // Make sure there's a session to check with — this normally
            // finished during the splash/intro screens already, but a
            // fresh reinstall can reach here before it has.
            await authSession.ensureSession()
            _ = try? await familyService.restoreMembership(modelContext: modelContext, dataSync: dataSync)
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
                Text("🏡").font(.system(size: 56))
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
                    route = .createName
                }
                ALISecondaryButton(text: "Join with a QR code") {
                    route = .scanQR
                }
                ALITextButton(text: "Join with a code") {
                    route = .joinByCode
                }
                ALITextButton(text: isRestoring ? "Checking your account…" : "Already have an account? Log in") {
                    route = .login
                }
                .disabled(isRestoring)
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
            case .login:
                LoginSheet(mode: .signIn) {
                    Task { await restoreAfterSignIn() }
                }
            }
        }
        .alert("No group found", isPresented: $showNoGroupFoundAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That account isn't linked to a family group yet. Create or join one below — it'll stay saved to it from now on.")
        }
    }

    /// After confirming sign-in in `LoginSheet`, checks whether that
    /// account is already tied to a family group (from a previous
    /// install) and, if so, drops straight into it instead of the
    /// create/join screen.
    private func restoreAfterSignIn() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            // Shows ContentView's full-screen "loading your family group"
            // for at least 3s while this runs — see `isRestoringFamily`.
            let found = try await familyService.restoreMembershipShowingProgress(modelContext: modelContext, dataSync: dataSync)
            if !found {
                showNoGroupFoundAlert = true
            }
        } catch {
            showNoGroupFoundAlert = true
        }
    }
}
