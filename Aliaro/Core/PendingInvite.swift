import Foundation

/// Invite token that arrived by opening an invite link — the QR scanned with
/// the iPhone Camera (universal link to devaroapps.com) or `aliaro://join`.
/// Persisted so it survives sign-up, email confirmation and a relaunch;
/// `FamilyOnboardingView` consumes it as soon as the person is signed in
/// without a group, and `ContentView` discards it if they already have one.
@MainActor
final class PendingInvite: ObservableObject {
    static let shared = PendingInvite()

    @Published private(set) var token: String?

    private static let tokenKey = "pendingInviteToken"
    private static let dateKey = "pendingInviteDate"
    /// Invites expire server-side 15 min after being generated; keeping the
    /// token a bit longer means a slow sign-up gets a clear "this code has
    /// expired" instead of silently landing on the create/join screen.
    private static let maxAge: TimeInterval = 60 * 60

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Self.tokenKey),
           let savedAt = defaults.object(forKey: Self.dateKey) as? Date,
           Date.now.timeIntervalSince(savedAt) < Self.maxAge {
            token = saved
        } else {
            defaults.removeObject(forKey: Self.tokenKey)
            defaults.removeObject(forKey: Self.dateKey)
        }
    }

    /// Stores the invite token if `url` is an Aliaro invite link.
    /// Returns `false` (and does nothing) for any other URL.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let newToken = InviteLink.token(fromURL: url) else { return false }
        token = newToken
        UserDefaults.standard.set(newToken, forKey: Self.tokenKey)
        UserDefaults.standard.set(Date.now, forKey: Self.dateKey)
        Track.event("invite_link_opened", ["scheme": url.scheme])
        return true
    }

    func clear() {
        token = nil
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.dateKey)
    }
}
