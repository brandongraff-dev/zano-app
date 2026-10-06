// GymLocationServices.swift
// App / ZANO / Features / GymSetup
//
// The three small Core Location / MapKit adapters the gym screens share:
//
//   * `GymLocationAuthorization` — observable authorization level plus the two explicit asks.
//     spec §24: "request When in Use first; Always only at gym setup with a clear explanation".
//     Nothing here asks on its own: `LocationPermissionPrimer` explains first, then calls these.
//     (This replaces the silent `requestAlwaysAuthorization()` `GymVerifier` used to make.)
//   * `GymOneShotLocationFetcher` — "Use current location", moved from `SettingsView.swift`
//     unchanged in behaviour (it only reacts to authorization changes while a fetch is pending).
//   * `GymPlaceSearch` — address / place search for the Add Gym sheet via `MKLocalSearch`
//     (iOS 17's async `start()`), debounced by the caller. `MKLocalSearchCompleter` was the other
//     option; its delegate hands back non-`Sendable` completions on an unspecified thread, which
//     is awkward under Swift 6 strict concurrency, and a debounced full search gives coordinates
//     directly (no second lookup per tap).
//
// Delegate callbacks are `nonisolated` and hop to the main actor with a `Task` carrying only
// `Sendable` values (a status enum, a coordinate, an `Error`) — the same pattern the moved fetcher
// already used.

import Foundation
import Observation
@preconcurrency import CoreLocation
@preconcurrency import MapKit

// MARK: - Authorization

@MainActor
@Observable
final class GymLocationAuthorization: NSObject {
    /// One per app: every gym screen reads the same level, and a `CLLocationManager` isn't
    /// rebuilt on each SwiftUI view re-init.
    static let shared = GymLocationAuthorization()

    enum Level: Equatable {
        case notDetermined
        /// Denied or restricted (parental controls / MDM).
        case denied
        case whenInUse
        case always
    }

    private(set) var level: Level = .notDetermined

    /// Whether the app already made its one "Always" request. iOS shows the upgrade prompt at most
    /// once; after that the only path is the Settings app, so the primer switches its button.
    private(set) var hasRequestedAlways: Bool

    private let manager = CLLocationManager()
    private static let requestedAlwaysKey = "zano.gym.requestedAlwaysLocation.v1"

    override init() {
        hasRequestedAlways = UserDefaults.standard.bool(forKey: Self.requestedAlwaysKey)
        super.init()
        level = Self.level(for: manager.authorizationStatus)
        manager.delegate = self
    }

    /// Step 1 (spec §24): While Using, at gym setup, to drop the pin where the user stands.
    func requestWhenInUse() {
        guard level == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Step 2 (spec §24): Always, after `LocationPermissionPrimer`'s explanation, so arrival can
    /// be noticed without opening the app. From `.notDetermined` iOS shows the While Using prompt
    /// first and offers the upgrade later; from `.whenInUse` it shows the upgrade prompt once.
    func requestAlways() {
        guard level != .always, level != .denied else { return }
        hasRequestedAlways = true
        UserDefaults.standard.set(true, forKey: Self.requestedAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    fileprivate func apply(_ status: CLAuthorizationStatus) {
        level = Self.level(for: status)
    }

    private static func level(for status: CLAuthorizationStatus) -> Level {
        switch status {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

extension GymLocationAuthorization: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.apply(status) }
    }
}

// MARK: - One-shot current location

enum GymLocationError: Error {
    case denied
}

/// One-shot current-location fetch wrapped as `async` (moved from `SettingsView.swift`). Acts on
/// authorization changes only while a `fetch()` is pending — the delegate's first callback fires
/// as soon as it's set, and answering that with `requestLocation()` would take an unprompted fix.
@MainActor
final class GymOneShotLocationFetcher: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func fetch() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                resume(.failure(GymLocationError.denied))
            }
        }
    }

    fileprivate func authorizationDidChange(to status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            resume(.failure(GymLocationError.denied))
        default:
            break
        }
    }

    fileprivate func resume(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension GymOneShotLocationFetcher: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationDidChange(to: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.resume(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(.failure(error)) }
    }
}

// MARK: - Place search

/// One search hit, reduced to plain values the view can hold.
struct GymPlaceResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
@Observable
final class GymPlaceSearch {
    private(set) var results: [GymPlaceResult] = []
    private(set) var isSearching = false
    private(set) var didFail = false
    /// The query the current `results` answer — lets the view tell "no results" from "not run".
    private(set) var answeredQuery = ""

    private static let maxResults = 6

    func clear() {
        results = []
        didFail = false
        answeredQuery = ""
    }

    /// Runs one `MKLocalSearch`. Callers debounce (the Add Gym sheet uses `.task(id:)` + a short
    /// sleep, which also cancels a superseded search). Biased to `region` when given.
    func search(_ rawQuery: String, near region: MKCoordinateRegion?) async {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            clear()
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let region {
            request.region = region
        }

        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = response.mapItems.prefix(Self.maxResults).map { item in
                let placemark = item.placemark
                return GymPlaceResult(
                    name: item.name ?? placemark.title ?? query,
                    subtitle: placemark.title ?? "",
                    latitude: placemark.coordinate.latitude,
                    longitude: placemark.coordinate.longitude
                )
            }
            didFail = false
            answeredQuery = query
        } catch {
            guard !Task.isCancelled else { return }
            // MKError.placemarkNotFound is "no results", not an outage.
            let notFound = (error as? MKError)?.code == .placemarkNotFound
            results = []
            didFail = !notFound
            answeredQuery = query
        }
    }
}
