import Foundation
import Supabase

/// Wraps Supabase Auth (email + password). Signing in is required to use
/// the app: `ContentView` shows `AuthWelcomeView` until `isSignedIn`.
///
/// The person's name is stored in the account's `user_metadata.name` at
/// sign-up, so it doesn't have to be asked again when creating or joining
/// a family group (`displayName`).
///
/// `family_members.auth_user_id` is stamped with the account id when a
/// group is created or joined (see `create-family`/`join-family`), so
/// signing in on a new or reinstalled device recovers that group
/// (`FamilyService.restoreMembership`).
///
/// Privacy note: the Supabase session lives in the Keychain, which —
/// unlike `UserDefaults` — survives an app delete/reinstall.
/// `prepareSession` clears it on a real fresh install so
/// a second-hand phone never inherits the previous owner's account.
@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    private static let hasLaunchedBeforeKey = "aliaro.hasLaunchedBefore"

    /// `false` until the stored session (if any) has been read at launch —
    /// lets `ContentView` avoid flashing the welcome screen for someone
    /// who is already signed in.
    @Published private(set) var hasResolvedSession = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var email: String?
    @Published private(set) var displayName: String?

    private var listenTask: Task<Void, Never>?

    private init() {
        listenTask = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                // The launch state is set by `prepareSession` (from the
                // stored session, even if expired and offline), so the
                // initial event is ignored to avoid logging out offline.
                if event == .initialSession { continue }
                await self?.apply(session)
            }
        }
    }

    private func apply(_ session: Session?) {
        // Anonymous sessions (from the old optional-login model) don't
        // count as signed in — see `prepareSession`.
        let user = session.flatMap { $0.user.isAnonymous ? nil : $0.user }
        isSignedIn = user != nil
        email = user?.email
        displayName = user.flatMap { Self.name(from: $0) }
    }

    private static func name(from user: User) -> String? {
        if case let .string(name)? = user.userMetadata["name"] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    // MARK: - Launch

    /// Called once at launch. Wipes a Keychain session left over from a
    /// previous install, drops any leftover anonymous session, then marks
    /// the session as resolved.
    func prepareSession() async {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.hasLaunchedBeforeKey) {
            // .local: clears the on-device session without needing network.
            try? await supabase.auth.signOut(scope: .local)
            defaults.set(true, forKey: Self.hasLaunchedBeforeKey)
        }
        // Stored session, even if its access token expired: it's refreshed
        // on the first request, so offline launches stay signed in.
        let current = supabase.auth.currentSession
        if let current, current.user.isAnonymous {
            try? await supabase.auth.signOut(scope: .local)
            apply(nil)
        } else {
            apply(current)
        }
        hasResolvedSession = true
    }

    // MARK: - Register

    enum SignUpResult {
        /// Signed in straight away (email confirmation disabled in Supabase).
        case signedIn
        /// Supabase emailed a confirmation code — finish with `confirmSignUp`.
        case needsConfirmation
    }

    func signUp(name: String, email: String, password: String) async throws -> SignUpResult {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["name": .string(name)]
        )
        if let session = response.session {
            apply(session)
            return .signedIn
        }
        return .needsConfirmation
    }

    func confirmSignUp(email: String, code: String) async throws {
        let response = try await supabase.auth.verifyOTP(email: email, token: code, type: .signup)
        if let session = response.session { apply(session) }
    }

    func resendSignUpCode(email: String) async throws {
        try await supabase.auth.resend(email: email, type: .signup)
    }

    // MARK: - Log in / out

    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        apply(session)
    }

    func signOut() async {
        try? await supabase.auth.signOut()
        // Make sure the UI flips even if the network call failed.
        try? await supabase.auth.signOut(scope: .local)
        apply(nil)
    }

    // MARK: - Password recovery (code by email, no deep link needed)

    /// Emails a recovery code. Requires the "Reset Password" email
    /// template in Supabase to include `{{ .Token }}`.
    func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    /// Verifies the recovery code (which signs the person in) and sets the
    /// new password on the account.
    func resetPassword(email: String, code: String, newPassword: String) async throws {
        try await supabase.auth.verifyOTP(email: email, token: code, type: .recovery)
        _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
        apply(try? await supabase.auth.session)
    }

    // MARK: - Account (change password / name)

    /// Re-checks the current password (signing in again) before setting
    /// the new one, so an unlocked phone alone can't change it.
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let email else {
            throw NSError(domain: "Aliaro", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "You're not logged in")])
        }
        _ = try await supabase.auth.signIn(email: email, password: currentPassword)
        _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
        apply(try? await supabase.auth.session)
    }

    /// Permanently deletes the account (App Store 5.1.1(v)). Re-checks the
    /// password first, then `delete-account` (identity taken from the JWT)
    /// leaves every family group — deleting the group if this was the
    /// last member — and removes the Supabase Auth user. Finally drops the
    /// local session.
    func deleteAccount(password: String) async throws {
        guard let email else {
            throw NSError(domain: "Aliaro", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "You're not logged in")])
        }
        _ = try await supabase.auth.signIn(email: email, password: password)
        struct OKResponse: Decodable { let ok: Bool }
        let _: OKResponse = try await invokeEdgeFunction("delete-account")
        try? await supabase.auth.signOut(scope: .local)
        apply(nil)
    }

    /// Keeps `user_metadata.name` in sync with the name shown in the
    /// family group (used as default when creating/joining a group).
    func updateDisplayName(_ name: String) async throws {
        let user = try await supabase.auth.update(user: UserAttributes(data: ["name": .string(name)]))
        displayName = Self.name(from: user)
    }
}
