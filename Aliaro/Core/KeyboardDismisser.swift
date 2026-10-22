import UIKit

/// App-wide "tap outside to close the keyboard": every key window gets a
/// tap recognizer that ends editing when the tap lands anywhere that isn't
/// a text input. It doesn't cancel touches, so buttons, lists and other
/// controls keep working normally on the same tap.
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()

    private var observer: NSObjectProtocol?

    /// Call once at launch.
    func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let window = notification.object as? UIWindow else { return }
            self.attach(to: window)
        }
    }

    private func attach(to window: UIWindow) {
        let alreadyAttached = window.gestureRecognizers?.contains { $0.delegate === self } ?? false
        guard !alreadyAttached else { return }
        let tap = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        tap.requiresExclusiveTouchType = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    /// Taps on a text field/view (or inside one) must not close the
    /// keyboard — that's the user moving to (or staying in) an input.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView || current is UISearchBar { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
