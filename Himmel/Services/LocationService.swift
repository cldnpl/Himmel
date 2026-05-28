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

    private let manager = CLLocationManager()
    nonisolated(unsafe) private var didStart = false
    nonisolated(unsafe) private var lastGeocodedCoord: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 250
        let initial = manager.authorizationStatus
        Task { @MainActor in self.applyAuthorization(initial) }
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
            self.coordinate = coord
            if shouldGeocode { self.reverseGeocode(location: location) }
        }
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
