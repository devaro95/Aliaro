import Foundation
import Supabase

/// Wraps Supabase Auth so the app always has a session — anonymous by
/// default, "linked" once the person actually signs in with their email.
///
/// The trick that makes login optional while still recoverable: an
/// anonymous session already has a stable user id from the moment the app
/// is installed, and `family_members.auth_user_id` is stamped with it as
/// soon as a group is created or joined (see `create-family`/`join-family`).
/// Linking an email to that SAME session (instead of creating a new one)
/// means the id never changes — so if the person later reinstalls and
/// signs back in with that email, the backend can find the family group
/// that id already belongs to (`restore-membership`) and hand it right
/// back. Someone who never taps "sign in" is unaffected: everything still
/// works exactly as before, just tied to an anonymous id instead of a
/// device id de-facto.
///
/// Confirmation happens by typing the 6-digit code Supabase emails (its
/// default OTP template), not by tapping a link: `requestLink`/`requestSignIn`
/// send the code, and `confirmLink`/`confirmSignIn` exchange it for a
/// session via `verifyOTP`.
///
/// Privacy note: the Supabase session (anonymous or linked) lives in the
/// Keychain, which — unlike `UserDefaults` — survives an app delete/
/// reinstall by design. Left alone, that would let someone who buys or
/// is given a phone (without a factory reset) inherit the previous
/// owner's session and family group. `wipeStaleSessionIfFreshInstall`
/// closes that: it detects a real fresh install (no `UserDefaults` flag
/// set — reinstalling wipes `UserDefaults` too) and clears any leftover
/// Keychain session before `ensureSession` would otherwise pick it back
/// up. Trade-off: this also means the SAME owner reinstalling the app
/// has to sign back in with their email to recover their group, instead
/// of it happening automatically — chosen deliberately over the privacy
/// risk.
@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    private static let hasLaunchedBeforeKey = "aliaro.hasLaunchedBefore"

    @Published private(set) var isAnonymous = true
    @Published private(set) var email: String?

    /// Whether this device is signed in with a real (non-anonymous) account.
    var isLinked: Bool { !isAnonymous }

    private var listenTask: Task<Void, Never>?

    private init() {
        listenTask = Task { [weak self] in
            for await (_, session) in supabase.auth.authStateChanges {
                await self?.apply(session)
            }
        }
    }

    private func apply(_ session: Session?) {
        isAnonymous = session?.user.isAnonymous ?? true
        email = session?.user.email
    }

    /// Called once at launch, before `ensureSession()`. Wipes any Keychain
    /// session left over from a previous install — see the type doc above
    /// for why. No-ops on every launch except the first one after a real
    /// install (fresh device, or a genuine reinstall), detected via a
    /// `UserDefaults` flag that a reinstall clears just like the Keychain
    /// item would otherwise survive.
    func wipeStaleSessionIfFreshInstall() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.hasLaunchedBeforeKey) else { return }
        // .local: clears the on-device session without needing network,
        // so this can't get stuck offline right after a fresh install.
        try? await supabase.auth.signOut(scope: .local)
        defaults.set(true, forKey: Self.hasLaunchedBeforeKey)
    }

    /// Called once at launch: makes sure there is always a session, so
    /// every family group always has an owner id to attach to — even
    /// before the person ever taps "sign in". Safe to call repeatedly.
    func ensureSession() async {
        if (try? await supabase.auth.session) != nil { return }
        do {
            _ = try await supabase.auth.signInAnonymously()
        } catch {
            print("⚠️ Could not start anonymous session: \(error)")
        }
    }

    // MARK: - Linking (turning this device's anonymous id into a real account)

    /// Sends a 6-digit confirmation code to `email`, without losing the
    /// current session — the family group already attached to it stays
    /// attached. Throws if that email already belongs to another account
    /// (manual linking refuses duplicates); the caller should offer "sign
    /// in" instead in that case. `confirmLink` finishes this.
    func requestLink(email: String) async throws {
        try await supabase.auth.update(user: UserAttributes(email: email))
    }

    /// Exchanges the code sent by `requestLink` for the linked email.
    func confirmLink(email: String, code: String) async throws {
        try await supabase.auth.verifyOTP(email: email, token: code, type: .emailChange)
    }

    // MARK: - Signing in (recovering an account on a new/reinstalled device)

    /// Sends a 6-digit sign-in code to an existing account. `confirmSignIn`
    /// finishes this, switching this device over to that account's
    /// identity (replacing the local anonymous session).
    func requestSignIn(email: String) async throws {
        try await supabase.auth.signInWithOTP(email: email)
    }

    /// Exchanges the code sent by `requestSignIn` for a session.
    func confirmSignIn(email: String, code: String) async throws {
        try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
    }

    #if DEBUG
    /// Debug-only: signs out and starts a brand-new anonymous session, so
    /// the "save your group" flow can be tested repeatedly. Reinstalling
    /// the app is NOT enough for this on its own — Supabase's session
    /// lives in the Keychain, which survives an app delete/reinstall.
    func debugResetSession() async {
        try? await supabase.auth.signOut()
        await ensureSession()
    }
    #endif
}
