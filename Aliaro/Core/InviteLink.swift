import Foundation

/// Shared utilities for link-based invites (an alternative to the QR code):
/// builds the URL that gets shared and extracts the token back, whether it
/// arrives as a full URL (shared as a link or encoded in the QR code)
/// or the person has pasted the raw token directly.
enum InviteLink {
    /// Universal link (see `apple-app-site-association` on devaroapps.com):
    /// scanned with the iPhone Camera it opens Aliaro straight into joining
    /// the group if installed, or the Aliaro web page (App Store link) if not.
    static func url(token: String) -> URL {
        URL(string: "https://www.devaroapps.com/apps/aliaro/?token=\(token)")!
    }

    /// Token of an invite link opened from outside the app: the universal
    /// link above (with or without `www`), or `aliaro://join?token=…`.
    /// `nil` for any other URL.
    static func token(fromURL url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let isWebInvite = ["http", "https"].contains(components.scheme?.lowercased() ?? "")
            && (components.host?.lowercased() ?? "").hasSuffix("devaroapps.com")
            && components.path.lowercased().hasPrefix("/apps/aliaro")
        let isAppSchemeInvite = components.scheme?.lowercased() == "aliaro"
        guard isWebInvite || isAppSchemeInvite,
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else { return nil }
        return token
    }

    static func token(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
           !token.isEmpty {
            return token
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}
