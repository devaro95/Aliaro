import Foundation
import StoreKit
import UIKit

/// Decides when to ask for an App Store rating (the system dialog,
/// `SKStoreReviewController`). Only after the family has really used the
/// app, right after something went well, and never too often:
///
/// - at least `minDaysSinceInstall` days since the first launch,
/// - at least `minSessions` sessions (app brought to the foreground),
/// - at least `minPositiveActions` positive actions since the last ask
///   (creating things, completing tasks, ticking off the shopping list…),
/// - at least `minDaysBetweenPrompts` days since the last ask,
/// - at most once per app version.
///
/// Apple shows the dialog at most 3 times a year anyway (and may skip it),
/// so the counters only decide when it's worth *asking* the system.
@MainActor
final class ReviewPrompt {
    static let shared = ReviewPrompt()

    static let minDaysSinceInstall = 3
    static let minSessions = 5
    static let minPositiveActions = 8
    static let minDaysBetweenPrompts = 120
    /// Wait after the action so the sheet that saved it has time to close.
    private static let delay: Duration = .seconds(1.5)

    private enum Keys {
        static let firstLaunch = "aliaro.review.firstLaunch"
        static let sessions = "aliaro.review.sessions"
        static let positiveActions = "aliaro.review.positiveActions"
        static let lastPrompt = "aliaro.review.lastPrompt"
        static let lastPromptVersion = "aliaro.review.lastPromptVersion"
    }

    private let defaults = UserDefaults.standard
    private var pending: Task<Void, Never>?

    private init() {
        if defaults.object(forKey: Keys.firstLaunch) == nil {
            defaults.set(Date.now, forKey: Keys.firstLaunch)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Call when the app becomes active.
    func registerSession() {
        defaults.set(defaults.integer(forKey: Keys.sessions) + 1, forKey: Keys.sessions)
    }

    /// Call right after something went well. If every condition is met,
    /// asks for a rating a moment later.
    func registerPositiveAction(_ source: String) {
        let count = defaults.integer(forKey: Keys.positiveActions) + 1
        defaults.set(count, forKey: Keys.positiveActions)
        guard isEligible else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.requestReview(source: source)
        }
    }

    var isEligible: Bool {
        let now = Date.now
        let firstLaunch = defaults.object(forKey: Keys.firstLaunch) as? Date ?? now
        guard days(from: firstLaunch, to: now) >= Self.minDaysSinceInstall else { return false }
        guard defaults.integer(forKey: Keys.sessions) >= Self.minSessions else { return false }
        guard defaults.integer(forKey: Keys.positiveActions) >= Self.minPositiveActions else { return false }
        if let last = defaults.object(forKey: Keys.lastPrompt) as? Date,
           days(from: last, to: now) < Self.minDaysBetweenPrompts {
            return false
        }
        return defaults.string(forKey: Keys.lastPromptVersion) != appVersion
    }

    private func requestReview(source: String) {
        guard isEligible,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else { return }
        Track.event("review_prompt_requested", [
            "source": source,
            "sessions": defaults.integer(forKey: Keys.sessions),
            "positive_actions": defaults.integer(forKey: Keys.positiveActions),
        ])
        defaults.set(Date.now, forKey: Keys.lastPrompt)
        defaults.set(appVersion, forKey: Keys.lastPromptVersion)
        defaults.set(0, forKey: Keys.positiveActions)
        SKStoreReviewController.requestReview(in: scene)
    }

    private func days(from start: Date, to end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }

    #if DEBUG
    /// Debug menu: shows the system dialog now (in debug/TestFlight builds
    /// it always appears, without sending a real rating).
    func debugRequestNow() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        SKStoreReviewController.requestReview(in: scene)
    }

    /// Debug menu: back to a fresh install.
    func debugReset() {
        [Keys.sessions, Keys.positiveActions, Keys.lastPrompt, Keys.lastPromptVersion].forEach(defaults.removeObject(forKey:))
        defaults.set(Date.now, forKey: Keys.firstLaunch)
    }
    #endif
}
