import SwiftUI
import UIKit

/// Full-screen, non-dismissable "Update Aliaro" shown over everything while
/// `ForceUpdate.required` is true. The only way out is updating.
/// `onDebugClose` (debug preview only) adds a way to close it.
struct ForceUpdateView: View {
    var onDebugClose: (() -> Void)? = nil

    @State private var isOpeningStore = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            AliaroWordmark(size: 40)

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 84, height: 84)
                .background(ALIColors.primary)
                .clipShape(Circle())

            Text("Update Aliaro")
                .font(ALITypography.headlineLarge)
                .foregroundStyle(ALIColors.ink)
                .multilineTextAlignment(.center)

            Text("There's a new version of Aliaro. Update it to keep using the app with your family group.")
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: 10) {
                ALIPrimaryButton(text: "Update", enabled: !isOpeningStore) {
                    Track.event("force_update_tap")
                    Task { await openAppStore() }
                }
                if let onDebugClose {
                    ALISecondaryButton(text: "Close preview (debug)") { onDebugClose() }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALIColors.background.ignoresSafeArea())
        .interactiveDismissDisabled()
        .trackScreen("force_update")
    }

    /// Aliaro's App Store id.
    private static let appStoreID = "6811198825"

    private func openAppStore() async {
        isOpeningStore = true
        defer { isOpeningStore = false }
        if let app = URL(string: "itms-apps://apps.apple.com/app/id\(Self.appStoreID)"),
           await UIApplication.shared.open(app) {
            return
        }
        if let web = URL(string: "https://apps.apple.com/app/id\(Self.appStoreID)") {
            await UIApplication.shared.open(web)
        }
    }
}

/// Shows `ForceUpdateView` in its own window above everything (sheets,
/// alerts, full-screen covers), so nothing in the app can be used meanwhile.
@MainActor
enum ForceUpdatePresenter {
    private static var window: UIWindow?

    static func update(required: Bool, debugPreview: Bool) {
        if required || debugPreview {
            show(debugClose: required ? nil : { ForceUpdate.shared.debugPreview = false })
        } else {
            hide()
        }
    }

    private static func show(debugClose: (() -> Void)?) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ??
            UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let host = UIHostingController(rootView: ForceUpdateView(onDebugClose: debugClose))
        host.view.backgroundColor = .clear
        let newWindow = window ?? UIWindow(windowScene: scene)
        newWindow.rootViewController = host
        newWindow.windowLevel = .alert + 1
        newWindow.makeKeyAndVisible()
        window = newWindow
    }

    private static func hide() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }
}
