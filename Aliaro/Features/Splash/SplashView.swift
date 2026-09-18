import SwiftUI

/// App splash screen: "Aliaro" typed in letter by letter with a wave
/// motion, finishing with the dot of the "i" dropping into place — the
/// animated form of `AliaroWordmark`.
struct SplashView: View {
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            ALIColors.background.ignoresSafeArea()
            AliaroWordmark(size: 48, animated: true, onFinished: onFinished)
        }
    }
}
