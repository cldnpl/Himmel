//
//  LocationService.swift
//  Himmel
//
//  Thin CoreLocation wrapper that publishes the user's coordinates + authorization.
//  The class is explicitly nonisolated so that CoreLocation can invoke delegate
//  methods on any queue without tripping Swift 6's strict-concurrency assertions
//  (the project sets SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so we have to opt
//  out here). All UI-visible state mutations are dispatched back to the main actor.
//

import Foundation
import CoreLocation
import Observation

@Observable
nonisolated final class LocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    enum Status: Equatable, Sendable {
        case notDetermined
        case denied
        case restricted
        case granted
    }

    @MainActor var coordinate: CLLocationCoordinate2D?
    @MainActor var status: Status = .notDetermined
    @MainActor var placeLabel: String?

    /// Fired on the main actor whenever `coordinate` is (re)assigned — including
    /// the immediate seed from the cached/persisted last fix on launch. The sky
    /// view model uses this to recompute positions the instant a real location is
    /// known, instead of waiting for its periodic timer (which made the sky open
    /// at the fallback 0,0 location and then visibly jump seconds later).
    @MainActor var onCoordinateChange: (() -> Void)?

    private let manager = CLLocationManager()
    nonisolated(unsafe) private var didStart = false
    nonisolated(unsafe) private var lastGeocodedCoord: CLLocationCoordinate2D?

    /// UserDefaults keys for persisting the last good coordinate across launches,
    /// so even a cold start (before the first GPS fix) paints a near-correct sky.
    private static let kLastLat = "Himmel.lastLatitude"
    private static let kLastLon = "Himmel.lastLongitude"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 250
        let initial = manager.authorizationStatus
        // Seed the last-known coordinate from disk so the very first recompute on
        // launch uses a realistic location rather than the 0,0 fallback.
        let persisted = Self.loadPersistedCoordinate()
        Task { @MainActor in
            self.applyAuthorization(initial)
            if let persisted, self.coordinate == nil {
                self.coordinate = persisted
            }
        }
    }

    /// Asks for permission if needed and starts updates. Safe to call repeatedly.
    @MainActor
    func start() {
        guard !didStart else { return }
        didStart = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            // CoreLocation often has a cached fix available immediately — adopt it
            // now so the first sky render is already at the right place, well
            // before `didUpdateLocations` delivers a fresh fix.
            if let cached = manager.location?.coordinate {
                adopt(coordinate: cached)
            }
        default:
            break
        }
    }

    @MainActor
    func stop() {
        manager.stopUpdatingLocation()
        didStart = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            self.applyAuthorization(newStatus)
            if (newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways)
                && self.didStart {
                self.manager.startUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate
        let shouldGeocode: Bool
        if let prev = lastGeocodedCoord {
            shouldGeocode = distanceMeters(from: prev, to: coord) > 5_000
        } else {
            shouldGeocode = true
        }
        if shouldGeocode { lastGeocodedCoord = coord }
        Task { @MainActor in
            self.adopt(coordinate: coord)
            if shouldGeocode { self.reverseGeocode(location: location) }
        }
    }

    /// Publish a new coordinate, persist it for the next cold start, and notify the
    /// observer so the sky recomputes immediately. Skips no-op reassignments of the
    /// same point to avoid redundant recomputes.
    @MainActor
    private func adopt(coordinate coord: CLLocationCoordinate2D) {
        if let current = coordinate,
           current.latitude == coord.latitude,
           current.longitude == coord.longitude {
            return
        }
        coordinate = coord
        Self.persist(coordinate: coord)
        onCoordinateChange?()
    }

    // MARK: - Persistence

    private static func persist(coordinate coord: CLLocationCoordinate2D) {
        let defaults = UserDefaults.standard
        defaults.set(coord.latitude, forKey: kLastLat)
        defaults.set(coord.longitude, forKey: kLastLon)
    }

    private static func loadPersistedCoordinate() -> CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: kLastLat) != nil,
              defaults.object(forKey: kLastLon) != nil else { return nil }
        let lat = defaults.double(forKey: kLastLat)
        let lon = defaults.double(forKey: kLastLon)
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)),
              !(lat == 0 && lon == 0) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Swallow transient errors; the UI shows an "acquiring location" hint instead.
    }

    // MARK: - Helpers

    @MainActor
    private func applyAuthorization(_ authorization: CLAuthorizationStatus) {
        switch authorization {
        case .notDetermined: status = .notDetermined
        case .restricted:    status = .restricted
        case .denied:        status = .denied
        case .authorizedAlways, .authorizedWhenInUse: status = .granted
        @unknown default:    status = .notDetermined
        }
    }

    @MainActor
    private func reverseGeocode(location: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let p = placemarks?.first else { return }
            let city = p.locality ?? p.administrativeArea
            let country = p.country
            let label: String?
            switch (city, country) {
            case let (c?, k?): label = "\(c), \(k)"
            case let (c?, nil): label = c
            case let (nil, k?): label = k
            default:            label = nil
            }
            Task { @MainActor in self.placeLabel = label }
        }
    }

    private nonisolated func distanceMeters(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
