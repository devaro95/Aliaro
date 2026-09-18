import Foundation

/// Shared utilities for link-based invites (an alternative to the QR code):
/// builds the URL that gets shared and extracts the token back, whether it
/// arrives as a full URL (shared as a link or encoded in the QR code)
/// or the person has pasted the raw token directly.
enum InviteLink {
    static func url(token: String) -> URL {
        URL(string: "https://aliaro.app/join?token=\(token)")!
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
