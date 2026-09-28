import UIKit
import UserNotifications

/// Requests notification permission and registers the device's APNs token,
/// forwarding it to Supabase as soon as there is a member (created or joined
/// a family group).
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    private var pendingToken: String?

    /// Screen to open after tapping a push (`tab` in the payload, an
    /// `AppTab.settingsKey`). Consumed — and reset — by `MainTabContainer`.
    @Published var pendingTab: AppTab?
    private weak var familyService: FamilyService?

    func attach(familyService: FamilyService) {
        self.familyService = familyService
        if let pendingToken {
            Task { await familyService.registerPushToken(pendingToken) }
        }
    }

    func requestAuthorizationAndRegister() {
        // Without this, iOS shows no banner/sound when the notification arrives
        // while the app is in the foreground (it would still arrive with the app
        // in the background or closed, but this is handy for testing).
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Track.event("push_permission_result", ["granted": granted])
            Track.setProperty(granted ? "yes" : "no", for: "push_enabled")
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Re-registers with APNs if permission was already granted, so the
    /// token reaches Supabase once there IS a member. Needed because the
    /// permission prompt runs at the end of the intro — before login and
    /// before creating/joining a group — when `registerPushToken` has no
    /// `memberID` yet and drops the token. Called whenever the member
    /// changes (join/create/restore) and at every launch with a group
    /// (tokens can rotate, or be cleared server-side if APNs rejects them).
    func refreshRegistrationIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            if status == .notDetermined {
                // Never asked on this device (e.g. intro seen on an older
                // build): ask now that there's a group to get pushes from.
                DispatchQueue.main.async { PushNotificationManager.shared.requestAuthorizationAndRegister() }
                return
            }
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            DispatchQueue.main.async {
                UNUserNotificationCenter.current().delegate = PushNotificationManager.shared
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        pendingToken = token
        if let familyService {
            Task { await familyService.registerPushToken(token) }
        }
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    /// Called when a push arrives with the app open in the foreground.
    /// Without implementing this, iOS shows nothing (no banner or sound) in that case.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Track.event("push_received_foreground", ["kind": Self.kind(of: notification)])
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when the user taps a notification (app in any state).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Track.event("push_opened", ["kind": Self.kind(of: response.notification)])
        let tabKey = response.notification.request.content.userInfo["tab"] as? String
        Task { @MainActor in
            if let tabKey, let tab = AppTab.from(settingsKey: tabKey) {
                PushNotificationManager.shared.pendingTab = tab
            }
        }
        completionHandler()
    }

    /// Local reminder vs remote push, plus whatever `type` the payload carries.
    nonisolated private static func kind(of notification: UNNotification) -> String {
        let info = notification.request.content.userInfo
        if let type = info["type"] as? String { return type }
        return notification.request.trigger is UNPushNotificationTrigger ? "remote" : "local"
    }
}

/// Minimal AppDelegate: only to receive the APNs registration callback
/// (SwiftUI App doesn't expose that callback directly).
final class AliaroAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Track.configure()
        KeyboardDismisser.shared.install()
        // So taps on notifications are tracked from the very first launch
        // (not only after the onboarding permission prompt set it).
        UNUserNotificationCenter.current().delegate = PushNotificationManager.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed registering APNs: \(error)")
    }
}
