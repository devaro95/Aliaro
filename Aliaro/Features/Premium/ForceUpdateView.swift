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

            ForceUpdateIllustration()

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

            ALIPrimaryButton(text: "Update", enabled: !isOpeningStore) {
                Track.event("force_update_tap")
                Task { await openAppStore() }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if let onDebugClose {
                Button(action: onDebugClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ALIColors.ink)
                        .frame(width: 36, height: 36)
                        .background(ALIColors.surfaceVariant, in: Circle())
                }
                .accessibilityLabel("Close preview (debug)")
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
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

/// "Installing on the phone" loop: a phone whose progress bar fills up and
/// turns into the Aliaro icon, which pops in, holds and shrinks away before
/// starting over. 3 s cycle driven by the clock (same timings as Android's
/// `ForceUpdateIllustration`). With Reduce Motion it just shows the icon.
struct ForceUpdateIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cycle = 3.0
    private static let fillEnd = 1.65

    var body: some View {
        if reduceMotion {
            phone(progress: 1, barOpacity: 0, logoScale: 1)
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
                phone(progress: Self.progress(t), barOpacity: Self.barOpacity(t), logoScale: Self.logoScale(t))
            }
        }
    }

    private func phone(progress: CGFloat, barOpacity: Double, logoScale: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ALIColors.surface)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ALIColors.ink, lineWidth: 2.5)

            Capsule()
                .fill(ALIColors.outline)
                .frame(width: 22, height: 5)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 9)

            ZStack(alignment: .leading) {
                Capsule().fill(ALIColors.outline)
                Capsule().fill(ALIColors.primary).frame(width: 52 * progress)
            }
            .frame(width: 52, height: 9)
            .opacity(barOpacity)

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(logoScale)
        }
        .frame(width: 76, height: 132)
        .accessibilityHidden(true)
    }

    // MARK: - Timeline (t in 0..<3 s)

    private static func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 2) }

    private static func progress(_ t: Double) -> CGFloat {
        CGFloat(t < fillEnd ? easeInOut(t / fillEnd) : 1)
    }

    private static func barOpacity(_ t: Double) -> Double {
        t < fillEnd ? 1 : max(0, 1 - (t - fillEnd) / 0.2)
    }

    private static func logoScale(_ t: Double) -> CGFloat {
        let value: Double
        switch t {
        case ..<fillEnd: value = 0
        case ..<2.04: value = 1.2 * easeOut((t - fillEnd) / (2.04 - fillEnd))
        case ..<2.28: value = 1.2 - 0.2 * easeOut((t - 2.04) / 0.24)
        case ..<2.76: value = 1
        default: value = 1 - easeInOut((t - 2.76) / (cycle - 2.76))
        }
        return CGFloat(value)
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
