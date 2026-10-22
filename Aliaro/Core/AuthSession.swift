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
    /// Set between a valid recovery code and the new password being saved
    /// (see `verifyRecoveryCode`). If the app dies in between, the
    /// recovery session is dropped at the next launch.
    private static let pendingRecoveryKey = "aliaro.pendingPasswordRecovery"

    /// While `true`, the session created by the recovery code is kept out
    /// of `isSignedIn`, so the auth flow stays on screen until the new
    /// password is saved.
    private var isRecoveringPassword = false

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
        guard !isRecoveringPassword else { return }
        // Anonymous sessions (from the old optional-login model) don't
        // count as signed in — see `prepareSession`.
        let user = session.flatMap { $0.user.isAnonymous ? nil : $0.user }
        isSignedIn = user != nil
        email = user?.email
        displayName = user.flatMap { Self.name(from: $0) }
        if let user { syncLocaleIfNeeded(user) }
    }

    // MARK: - Email language

    /// App language ("es", "en"…) saved in `user_metadata.locale`, so the
    /// Supabase Auth email templates (confirm signup, reset password) can
    /// pick Spanish or English with `{{ if eq .Data.locale "es" }}`.
    static var appLocale: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Keeps `user_metadata.locale` in line with the device language
    /// (e.g. accounts created before this existed, or a language change).
    /// The update fires `userUpdated`, which lands here again with the
    /// value already equal, so it doesn't loop.
    private func syncLocaleIfNeeded(_ user: User) {
        let locale = Self.appLocale
        if case let .string(current)? = user.userMetadata["locale"], current == locale { return }
        Task {
            _ = try? await supabase.auth.update(user: UserAttributes(data: ["locale": .string(locale)]))
        }
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
        // Recovery code verified but the new password never saved: that
        // session must not count as a login.
        if defaults.bool(forKey: Self.pendingRecoveryKey) {
            try? await supabase.auth.signOut(scope: .local)
            defaults.removeObject(forKey: Self.pendingRecoveryKey)
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
            data: ["name": .string(name), "locale": .string(Self.appLocale)]
        )
        if let session = response.session {
            apply(session)
            return .signedIn
        }
        // With email confirmation on, Supabase doesn't fail for an email that
        // already has an account: it returns an obfuscated user with no
        // identities (and sends nothing). Treat that as "already registered".
        if response.user.identities?.isEmpty ?? false {
            throw SignUpError.emailAlreadyRegistered
        }
        return .needsConfirmation
    }

    enum SignUpError: Error {
        case emailAlreadyRegistered
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

    /// Step 1: checks the recovery code. Supabase opens a session with it,
    /// but it isn't treated as a login until `setNewPassword` succeeds.
    func verifyRecoveryCode(email: String, code: String) async throws {
        isRecoveringPassword = true
        UserDefaults.standard.set(true, forKey: Self.pendingRecoveryKey)
        do {
            try await supabase.auth.verifyOTP(email: email, token: code, type: .recovery)
        } catch {
            isRecoveringPassword = false
            UserDefaults.standard.removeObject(forKey: Self.pendingRecoveryKey)
            throw error
        }
    }

    /// Step 2: saves the new password and signs the person in.
    func setNewPassword(_ newPassword: String) async throws {
        _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
        isRecoveringPassword = false
        UserDefaults.standard.removeObject(forKey: Self.pendingRecoveryKey)
        apply(try? await supabase.auth.session)
    }

    /// Leaving the new-password screen without saving: drops the recovery
    /// session so the person is back at a signed-out login screen.
    func cancelPasswordRecovery() async {
        guard isRecoveringPassword else { return }
        try? await supabase.auth.signOut(scope: .local)
        isRecoveringPassword = false
        UserDefaults.standard.removeObject(forKey: Self.pendingRecoveryKey)
        apply(nil)
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
