import Foundation
import CoreLocation

/// One location fix, for the iMessage app's leave-by time (the app has its
/// own LocationManager). Asks for permission only when you tap the button.
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    static let shared = OneShotLocation()

    private let manager = CLLocationManager()
    private var fixWaiters: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    private var permissionWaiters: [CheckedContinuation<Bool, Never>] = []
    /// Counts location requests, so an old request's timeout can't end a newer one early.
    private var fixRound = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAllowed: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// Your location, or nil if it's not allowed or doesn't arrive in 8 seconds.
    func current() async -> CLLocationCoordinate2D? {
        guard isAllowed else { return nil }
        return await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            guard fixWaiters.count == 1 else { return }
            fixRound += 1
            let round = fixRound
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                if self.fixRound == round { self.finishFix(nil) }
            }
        }
    }

    /// Shows the permission prompt (if it hasn't been answered) and returns
    /// whether location is allowed.
    func requestPermission() async -> Bool {
        if isAllowed { return true }
        guard manager.authorizationStatus == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            permissionWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    private func finishFix(_ coordinate: CLLocationCoordinate2D?) {
        guard !fixWaiters.isEmpty else { return }
        fixRound += 1
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(returning: coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finishFix(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishFix(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor in
            let allowed = status == .authorizedWhenInUse || status == .authorizedAlways
            let waiters = self.permissionWaiters
            self.permissionWaiters = []
            waiters.forEach { $0.resume(returning: allowed) }
        }
    }
}
