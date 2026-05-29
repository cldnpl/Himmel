//
//  SkyViewModel.swift
//  Himmel
//
//  Owns the sky state: where the observer is, what time it is, and the resolved
//  horizontal positions of every renderable object. Pure-ish; no UIKit/SceneKit.
//

import Foundation
import CoreLocation
import Observation

/// One renderable item the AR layer needs to draw and tap-test.
struct ResolvedSkyObject: Identifiable, Hashable {
    let object: CelestialObject
    let horizontal: HorizontalCoordinate

    var id: String { object.id }
}

@Observable
final class SkyViewModel {

    // MARK: - Dependencies

    let locationService: LocationService

    // MARK: - UI state

    var showConstellations: Bool = true
    var showLabels: Bool = false
    /// Live AR Mode: real camera passthrough behind the celestial overlay.
    var isLiveARMode: Bool = false
    /// Within Live AR: overlay the app's spherical sky (dome) blended over the
    /// real sky, instead of projecting bodies only onto the real sky.
    var arShowVirtualSky: Bool = false
    /// Set by the renderer once the phone is aimed clearly above the horizon.
    var liveARPointingAtSky: Bool = false
    var selectedObject: CelestialObject?
    var isFeaturedSheetPresented: Bool = false
    var navigationSearchText: String = ""
    var navigationSearchError: String?
    var navigationTarget: CelestialObject?
    var navigationGuidance: SkyNavigationGuidance = .inactive
    private(set) var navigationAcquisitionToken: Int = 0

    /// Always-current observer time. Updated by the periodic timer.
    private(set) var currentDate: Date = Date()

    /// Resolved positions for the current date+location, used by the AR layer.
    private(set) var resolvedObjects: [ResolvedSkyObject] = []
    private(set) var resolvedConstellations: [ResolvedConstellation] = []
    private(set) var moonSnapshot: MoonPhase.Snapshot = MoonPhase.phase(at: Date())

    /// Cache so we know which star catalog entry maps to which resolved horizontal coord.
    private(set) var starPositions: [String: HorizontalCoordinate] = [:]

    // MARK: - Internals

    private var timer: Timer?
    private var didStart = false

    init(locationService: LocationService = LocationService()) {
        self.locationService = locationService
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true
        locationService.start()
        recompute()
        // Refresh every 5s — celestial sphere drifts ~1°/4min, so this is generous.
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        didStart = false
    }

    private func tick() {
        currentDate = Date()
        recompute()
    }

    // MARK: - Recomputation

    /// Effective observer coordinate. Falls back to a sensible default if location
    /// is not yet available, so the AR sky is still populated.
    private var effectiveCoordinate: CLLocationCoordinate2D {
        // Fallback: 0°N 0°E — neutral default; sky will be rough but populated.
        locationService.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    func recompute() {
        let now = currentDate
        let coord = effectiveCoordinate

        // Stars (fixed equatorial coords).
        var stars: [ResolvedSkyObject] = []
        var starPos: [String: HorizontalCoordinate] = [:]
        stars.reserveCapacity(StarCatalog.stars.count)
        starPos.reserveCapacity(StarCatalog.stars.count)
        // Occupied 0.5°-grid cells, so constellation vertices that coincide with a
        // named catalog star don't get a second, duplicate dot stacked on top.
        var occupiedCells = Set<Int>()
        for star in StarCatalog.stars {
            guard let eq = star.equatorial else { continue }
            let horiz = AstronomicalMath.horizontal(
                from: eq,
                at: now,
                latitudeDegrees: coord.latitude,
                longitudeDegrees: coord.longitude
            )
            stars.append(ResolvedSkyObject(object: star, horizontal: horiz))
            starPos[star.id] = horiz
            occupiedCells.insert(Self.gridCell(raHours: eq.rightAscensionHours, decDegrees: eq.declinationDegrees))
        }

        // Constellation vertex stars: a tappable dot at every stick-figure vertex
        // across all 88 IAU figures, deduplicated against named stars and each
        // other. Magnitude is set above the 3.6 floating-label threshold so they
        // render as quiet dots; the "Star in <Constellation>" copy shows on tap.
        for constellation in ConstellationCatalog.all {
            for path in constellation.paths {
                for point in path {
                    let cell = Self.gridCell(raHours: point.raHours, decDegrees: point.decDegrees)
                    guard occupiedCells.insert(cell).inserted else { continue }
                    let eq = point.equatorial
                    let horiz = AstronomicalMath.horizontal(
                        from: eq,
                        at: now,
                        latitudeDegrees: coord.latitude,
                        longitudeDegrees: coord.longitude
                    )
                    let id = "cvx-\(cell)"
                    let obj = CelestialObject(
                        id: id,
                        name: "\(constellation.name) Star",
                        type: .star,
                        equatorial: eq,
                        magnitude: 4.5,
                        designation: nil,
                        subtitle: "Star in \(constellation.name)",
                        summary: "One of the stars that trace the figure of \(constellation.name).",
                        facts: []
                    )
                    stars.append(ResolvedSkyObject(object: obj, horizontal: horiz))
                    starPos[id] = horiz
                }
            }
        }

        // Sun, Moon, and naked-eye planets.
        var bodies: [ResolvedSkyObject] = []
        for body in PlanetEphemeris.Body.allCases {
            let eq = PlanetEphemeris.equatorial(for: body, at: now)
            let horiz = AstronomicalMath.horizontal(
                from: eq,
                at: now,
                latitudeDegrees: coord.latitude,
                longitudeDegrees: coord.longitude
            )
            let obj = CelestialObject(
                id: "body-\(body.rawValue)",
                name: body.displayName,
                type: body.celestialType,
                equatorial: eq,
                magnitude: nil,
                designation: nil,
                subtitle: subtitle(for: body),
                summary: summary(for: body),
                facts: facts(for: body, at: now)
            )
            bodies.append(ResolvedSkyObject(object: obj, horizontal: horiz))
        }

        self.resolvedObjects = stars + bodies
        self.starPositions = starPos
        self.resolvedConstellations = Self.resolveConstellations(
            at: now,
            latitudeDegrees: coord.latitude,
            longitudeDegrees: coord.longitude
        )
        self.moonSnapshot = MoonPhase.phase(at: now)
    }

    /// Pack an RA/Dec position into a single integer key on a ~0.5° grid, used to
    /// deduplicate coincident stars. RA is converted to degrees (×15) so the cell
    /// size is uniform on the sky near the equator.
    private static func gridCell(raHours: Double, decDegrees: Double) -> Int {
        let raDeg = raHours * 15.0
        let raIndex = Int((raDeg * 2.0).rounded())          // 0.5° bins, 0…720
        let decIndex = Int(((decDegrees + 90.0) * 2.0).rounded()) // 0.5° bins, 0…360
        return raIndex * 1000 + decIndex
    }

    /// Resolve every catalog constellation's RA/Dec stick-figure into horizontal
    /// line segments for the given observer + instant. Each polyline becomes a
    /// chain of endpoint-to-endpoint segments.
    private static func resolveConstellations(
        at date: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double
    ) -> [ResolvedConstellation] {
        ConstellationCatalog.all.map { c in
            var segments: [ResolvedConstellation.Segment] = []
            for path in c.paths where path.count >= 2 {
                var prev = AstronomicalMath.horizontal(
                    from: path[0].equatorial,
                    at: date,
                    latitudeDegrees: latitudeDegrees,
                    longitudeDegrees: longitudeDegrees
                )
                for idx in 1..<path.count {
                    let cur = AstronomicalMath.horizontal(
                        from: path[idx].equatorial,
                        at: date,
                        latitudeDegrees: latitudeDegrees,
                        longitudeDegrees: longitudeDegrees
                    )
                    segments.append(.init(a: prev, b: cur))
                    prev = cur
                }
            }
            return ResolvedConstellation(
                id: c.id,
                name: c.name,
                summary: c.summary,
                segments: segments
            )
        }
    }

    // MARK: - Selection

    func select(objectID id: String) {
        // Tear down any active search-navigation guidance BEFORE the sheet opens,
        // so the renderer stops solving directional angles / arrows for a target
        // the user has just arrived at and tapped (prevents a render-loop race
        // with the presentation transition). No-op when nothing is being tracked.
        if navigationTarget != nil {
            clearNavigationTarget()
        }

        if let match = resolvedObjects.first(where: { $0.id == id }) {
            selectedObject = match.object
        } else if id.hasPrefix("constellation-") {
            let constellationID = String(id.dropFirst("constellation-".count))
            guard let match = resolvedConstellations.first(where: { $0.id == constellationID }) else { return }
            selectedObject = CelestialObject(
                id: id,
                name: match.name,
                type: .constellation,
                subtitle: "Recognizable star pattern",
                summary: match.summary,
                facts: [
                    "Line segments: \(match.segments.count)"
                ]
            )
        }
    }

    func dismissSelection() { selectedObject = nil }

    func toggleConstellations() { showConstellations.toggle() }

    func toggleLiveARMode() { isLiveARMode.toggle() }

    func toggleARSky() { arShowVirtualSky.toggle() }

    func presentFeatured() { isFeaturedSheetPresented = true }
    func dismissFeatured() { isFeaturedSheetPresented = false }

    // MARK: - Navigation search

    @discardableResult
    func submitNavigationSearch() -> Bool {
        let query = normalizedSearchString(navigationSearchText)
        guard !query.isEmpty else {
            navigationSearchError = nil
            return false
        }

        guard let target = navigationCandidate(matching: query) else {
            navigationSearchError = "Body not found"
            return false
        }

        navigationTarget = target
        navigationSearchText = target.name
        navigationSearchError = nil
        navigationGuidance = SkyNavigationGuidance(
            targetID: target.id,
            targetName: target.name,
            direction: nil,
            isTargetVisible: false,
            angularDistanceDegrees: 180,
            yawDegrees: 0,
            pitchDegrees: 0,
            intensity: 0.18
        )
        return true
    }

    func clearNavigationTarget() {
        navigationTarget = nil
        navigationSearchText = ""
        navigationSearchError = nil
        navigationGuidance = .inactive
    }

    func updateNavigationGuidance(_ guidance: SkyNavigationGuidance) {
        guard navigationTarget?.id == guidance.targetID else { return }
        let didAcquireTarget = guidance.isTargetVisible && !navigationGuidance.isTargetVisible
        navigationGuidance = guidance
        if didAcquireTarget {
            navigationAcquisitionToken += 1
        }
    }

    private func navigationCandidate(matching normalizedQuery: String) -> CelestialObject? {
        let candidates = navigationCandidates()
        if let exact = candidates.first(where: { $0.aliases.contains(normalizedQuery) }) {
            return exact.object
        }

        let prefixMatches = candidates.filter { candidate in
            candidate.aliases.contains { $0.hasPrefix(normalizedQuery) }
        }
        if prefixMatches.count == 1 { return prefixMatches[0].object }

        return nil
    }

    private struct NavigationCandidate {
        let object: CelestialObject
        let aliases: Set<String>
    }

    private func navigationCandidates() -> [NavigationCandidate] {
        var candidates: [NavigationCandidate] = []
        candidates.reserveCapacity(resolvedObjects.count + resolvedConstellations.count)

        for resolved in resolvedObjects {
            var aliases: Set<String> = [
                normalizedSearchString(resolved.object.name),
                normalizedSearchString(resolved.object.id)
            ]
            if let designation = resolved.object.designation {
                aliases.insert(normalizedSearchString(designation))
            }
            candidates.append(NavigationCandidate(object: resolved.object, aliases: aliases))
        }

        for constellation in resolvedConstellations {
            let object = CelestialObject(
                id: "constellation-\(constellation.id)",
                name: constellation.name,
                type: .constellation,
                subtitle: "Recognizable star pattern",
                summary: constellation.summary,
                facts: [
                    "Line segments: \(constellation.segments.count)"
                ]
            )
            candidates.append(NavigationCandidate(object: object, aliases: [
                normalizedSearchString(constellation.name),
                normalizedSearchString(constellation.id),
                normalizedSearchString("constellation \(constellation.name)")
            ]))
        }

        return candidates
    }

    private func normalizedSearchString(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: - Copy for Sun/Moon/planets

    private func subtitle(for body: PlanetEphemeris.Body) -> String {
        switch body {
        case .sun:     return "The star at the heart of our solar system"
        case .moon:    return "Earth's only natural satellite"
        case .mercury: return "The smallest planet — closest to the Sun"
        case .venus:   return "The brightest planet, often the evening or morning 'star'"
        case .mars:    return "The Red Planet"
        case .jupiter: return "The largest planet in the solar system"
        case .saturn:  return "The ringed gas giant"
        case .uranus:  return "The tilted ice giant"
        case .neptune: return "The windiest planet — most distant from the Sun"
        }
    }

    private func summary(for body: PlanetEphemeris.Body) -> String {
        switch body {
        case .sun:
            return "A G-type main-sequence star that drives weather, climate and life on Earth. Never observe the Sun directly through optical aids without proper filters."
        case .moon:
            return "Locked in synchronous rotation, the Moon shows us the same face at all times. Its phases are caused by the changing geometry between the Earth, Moon and Sun."
        case .mercury:
            return "A rocky, cratered world only slightly larger than Earth's Moon. From Earth it's tricky to spot — always close to the Sun, briefly visible at twilight."
        case .venus:
            return "Cloaked in thick clouds of sulfuric acid, Venus reflects sunlight so effectively that it's the third-brightest object in our sky after the Sun and Moon."
        case .mars:
            return "A cold desert world whose reddish color comes from iron oxide on its surface. Hosts the tallest volcano in the solar system, Olympus Mons."
        case .jupiter:
            return "A gas giant more massive than all other planets combined. Visible as a bright steady point with at least four moons resolvable in binoculars."
        case .saturn:
            return "Best known for its spectacular rings of ice and rock. A small telescope reveals them clearly, even at magnifications around 30×."
        case .uranus:
            return "An ice giant that rotates almost on its side, likely after an ancient collision. Just barely visible to the naked eye under very dark skies as a faint blue-green point."
        case .neptune:
            return "The most distant major planet, a deep-blue ice giant with the fiercest winds in the solar system. Never visible to the unaided eye — binoculars or a telescope are required."
        }
    }

    private func facts(for body: PlanetEphemeris.Body, at date: Date) -> [String] {
        let base: [String]
        switch body {
        case .moon:
            let phase = MoonPhase.phase(at: date)
            base = [
                "Phase: \(phase.name.rawValue)",
                String(format: "Illumination: %.0f%%", phase.illumination * 100),
                "Mean distance: 384,400 km"
            ]
        case .sun:
            base = ["Distance: 1 AU (≈150 million km)", "Spectral type: G2 V"]
        case .mercury: base = ["Diameter: 4,879 km", "Orbital period: 88 Earth days"]
        case .venus:   base = ["Diameter: 12,104 km", "Orbital period: 225 Earth days"]
        case .mars:    base = ["Diameter: 6,779 km", "Orbital period: 687 Earth days"]
        case .jupiter: base = ["Diameter: 139,820 km", "Orbital period: 11.9 Earth years"]
        case .saturn:  base = ["Diameter: 116,460 km", "Orbital period: 29.5 Earth years"]
        case .uranus:  base = ["Diameter: 50,724 km", "Orbital period: 84 Earth years"]
        case .neptune: base = ["Diameter: 49,244 km", "Orbital period: 165 Earth years"]
        }
        // Append moon-system info for planets that have satellites.
        return base + SatelliteCatalog.facts(for: body)
    }
}
