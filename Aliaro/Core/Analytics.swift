import Foundation
import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Thin wrapper over Firebase Analytics — the only place in the app that
/// talks to Firebase directly, so screens call `Track.event(...)` /
/// `.trackScreen(...)` and never import Firebase themselves.
///
/// Config file: `GoogleService-Info.plist` in `Aliaro/` (production).
/// Debug builds prefer `GoogleService-Info-Dev.plist` if present, so dev
/// events don't pollute production data. Without any plist, every call
/// here is a silent no-op (the app keeps working, just untracked).
///
/// Privacy: no free text typed by the user is ever sent (titles, notes,
/// amounts…), only types, counts and flags — except grocery item and dish
/// names, which are product data, not personal data.
enum Track {
    private(set) static var isEnabled = false

    // MARK: Setup

    static func configure() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else { isEnabled = true; return }
        #if DEBUG
        let candidates = ["GoogleService-Info-Dev", "GoogleService-Info"]
        #else
        let candidates = ["GoogleService-Info"]
        #endif
        for name in candidates {
            if let path = Bundle.main.path(forResource: name, ofType: "plist"),
               let options = FirebaseOptions(contentsOfFile: path) {
                FirebaseApp.configure(options: options)
                isEnabled = true
                return
            }
        }
        print("ℹ️ Analytics disabled: no GoogleService-Info.plist in the bundle")
        #endif
    }

    // MARK: Events

    /// Logs a custom event. Names/keys must be snake_case (≤40 chars);
    /// values are sanitized to what Firebase accepts (String ≤100 chars,
    /// numbers; Bool → 0/1; nil dropped).
    static func event(_ name: String, _ params: [String: Any?] = [:]) {
        var clean: [String: Any] = [:]
        for (key, value) in params {
            guard let value else { continue }
            switch value {
            case let b as Bool: clean[key] = b ? 1 : 0
            case let s as String: clean[key] = String(s.prefix(100))
            case let i as Int: clean[key] = i
            case let d as Double: clean[key] = d
            case let d as Decimal: clean[key] = NSDecimalNumber(decimal: d).doubleValue
            case let u as UUID: clean[key] = u.uuidString
            case let date as Date: clean[key] = Int(date.timeIntervalSince1970)
            default: clean[key] = String(describing: value).prefix(100).description
            }
        }
        #if DEBUG
        print("📊 \(name) \(clean)")
        #endif
        #if canImport(FirebaseAnalytics)
        guard isEnabled else { return }
        Analytics.logEvent(name, parameters: clean.isEmpty ? nil : clean)
        #endif
    }

    /// Screen view (Firebase's standard `screen_view`, so it shows in the
    /// "Pages and screens" report).
    static func screen(_ name: String) {
        #if DEBUG
        print("📊 screen_view \(name)")
        #endif
        #if canImport(FirebaseAnalytics)
        guard isEnabled else { return }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: name
        ])
        #endif
    }

    // MARK: Paywall

    /// What the user tapped that led to the paywall (e.g. "invite_member").
    /// Set by `paywall(_:)` right before the sheet opens and read by
    /// `PaywallView` when it appears.
    private(set) static var pendingPaywallTrigger: String = "unknown"

    /// Records that a premium-locked control was tapped and returns `true`,
    /// so call sites stay one-liners: `showPaywall = Track.paywall("x")`.
    @discardableResult
    static func paywall(_ trigger: String) -> Bool {
        pendingPaywallTrigger = trigger
        event("premium_locked_tap", ["trigger": trigger])
        return true
    }

    // MARK: User identity / properties

    static func setUser(id: UUID?) {
        #if canImport(FirebaseAnalytics)
        guard isEnabled else { return }
        Analytics.setUserID(id?.uuidString)
        #endif
    }

    static func setProperty(_ value: String?, for name: String) {
        #if canImport(FirebaseAnalytics)
        guard isEnabled else { return }
        Analytics.setUserProperty(value.map { String($0.prefix(36)) }, forName: name)
        #endif
    }

    /// Refreshes every user property from the current session state —
    /// called at launch and whenever membership / premium state changes.
    @MainActor
    static func refreshUserProperties(memberCount: Int? = nil, role: String? = nil) {
        let session = FamilySession.shared
        let premium = PremiumManager.shared
        setUser(id: session.memberID)
        setProperty(session.hasJoinedFamily ? "yes" : "no", for: "in_family")
        setProperty(session.isFamilyPremium ? "yes" : "no", for: "family_premium")
        setProperty(premium.subscriptions.isSubscribed ? "yes" : "no", for: "is_subscriber")
        setProperty(AuthSession.shared.isLinked ? "yes" : "no", for: "email_linked")
        setProperty(session.disabledTabs.isEmpty ? "none" : session.disabledTabs.sorted().joined(separator: ","), for: "hidden_tabs")
        setProperty(session.startTab ?? "default", for: "start_tab")
        if let memberCount { setProperty(String(memberCount), for: "family_size") }
        if let role { setProperty(role, for: "family_role") }
    }

    /// StoreKit 2 transactions aren't picked up automatically by Firebase:
    /// forward each verified one so revenue shows up in the console.
    static func logTransaction(_ transaction: Any) {
        #if canImport(FirebaseAnalytics)
        guard isEnabled else { return }
        if #available(iOS 15.0, *), let transaction = transaction as? StoreKitTransaction {
            Analytics.logTransaction(transaction)
        }
        #endif
    }
}

#if canImport(StoreKit)
import StoreKit
typealias StoreKitTransaction = StoreKit.Transaction
#endif

// MARK: - Screen tracking modifier

private struct TrackScreenModifier: ViewModifier {
    let name: String
    @State private var appearedAt: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                appearedAt = .now
                Track.screen(name)
            }
            .onDisappear {
                guard let appearedAt else { return }
                let seconds = Int(Date.now.timeIntervalSince(appearedAt))
                Track.event("screen_exit", ["screen": name, "seconds": seconds])
                self.appearedAt = nil
            }
    }
}

extension View {
    /// Logs `screen_view` when the view appears and `screen_exit` (with
    /// time spent, in seconds) when it goes away.
    func trackScreen(_ name: String) -> some View {
        modifier(TrackScreenModifier(name: name))
    }
}
