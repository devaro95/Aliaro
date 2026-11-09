import CoreLocation

/// Asks for location ("while using") before opening a screen that needs it
/// (Places), so the system prompt shows before navigating instead of on top
/// of the map.
@MainActor
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermission()

    private let manager = CLLocationManager()
    private var pending: [() -> Void] = []

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Runs `then` right away when the user already answered; otherwise asks
    /// first and runs it after they answer (allowed or not).
    func requestIfNeeded(then: @escaping () -> Void) {
        guard manager.authorizationStatus == .notDetermined else {
            then()
            return
        }
        pending.append(then)
        Track.event("location_permission_prompt", ["source": "places"])
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // Called once on creation too: only act after a real answer.
            guard status != .notDetermined, !self.pending.isEmpty else { return }
            let granted = status == .authorizedWhenInUse || status == .authorizedAlways
            Track.event("location_permission_result", ["granted": granted])
            let actions = self.pending
            self.pending.removeAll()
            actions.forEach { $0() }
        }
    }
}
