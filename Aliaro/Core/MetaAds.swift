import UIKit
import FacebookCore

/// Meta (Facebook) SDK, used only to measure installs and opens coming from
/// Meta ads (App Events + SKAdNetwork / Aggregated Event Measurement), which
/// Meta requires to run app-install campaigns on iOS 14.5+.
///
/// No Facebook Login and no IDFA: the app never shows the ATT prompt, so
/// advertiser tracking stays off and Meta measures with AEM/SKAdNetwork only.
/// Like Firebase, it's never started in DEBUG so test runs don't pollute the
/// ad stats (and the dev bundle id isn't registered in the Meta app).
/// Keys live in Info.plist (FacebookAppID / FacebookClientToken).
enum MetaAds {
    static func configure(
        application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        #if DEBUG
        return
        #else
        Settings.shared.isAutoLogAppEventsEnabled = true
        // Initializes the SDK; from here on it logs app installs/activations
        // automatically (fb_mobile_activate_app) every time the app becomes active.
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        #endif
    }
}
