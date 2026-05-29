//
//  SatelliteCatalog.swift
//  Himmel
//
//  Natural-satellite (moon) data for the planets, surfaced as info in each
//  planet's detail sheet rather than rendered in 3D — at the dome radius the
//  angular separation between a planet and its moons is far below one pixel.
//

import Foundation

enum SatelliteCatalog {

    /// Static description of a planet's moon system.
    struct MoonSystem {
        /// Total confirmed natural satellites.
        let totalCount: Int
        /// The major moons, brightest / largest first.
        let majorMoons: [String]
    }

    /// Moon systems keyed by `PlanetEphemeris.Body`. Bodies without satellites
    /// (Sun, Moon, Mercury, Venus) are intentionally absent.
    static func system(for body: PlanetEphemeris.Body) -> MoonSystem? {
        switch body {
        case .mars:
            return MoonSystem(totalCount: 2, majorMoons: ["Phobos", "Deimos"])
        case .jupiter:
            return MoonSystem(
                totalCount: 95,
                majorMoons: ["Io", "Europa", "Ganymede", "Callisto"]
            )
        case .saturn:
            return MoonSystem(
                totalCount: 146,
                majorMoons: ["Titan", "Rhea", "Iapetus", "Dione", "Tethys", "Enceladus"]
            )
        case .uranus:
            return MoonSystem(
                totalCount: 28,
                majorMoons: ["Titania", "Oberon", "Umbriel", "Ariel", "Miranda"]
            )
        case .neptune:
            return MoonSystem(
                totalCount: 16,
                majorMoons: ["Triton", "Proteus", "Nereid"]
            )
        case .sun, .moon, .mercury, .venus:
            return nil
        }
    }

    /// Fact rows ("Label: value") describing the moon system, ready to append to
    /// a planet's detail-sheet facts. Empty for moonless bodies.
    static func facts(for body: PlanetEphemeris.Body) -> [String] {
        guard let system = system(for: body) else { return [] }
        var rows: [String] = ["Moons: \(system.totalCount)"]
        if !system.majorMoons.isEmpty {
            rows.append("Major moons: \(system.majorMoons.joined(separator: ", "))")
        }
        return rows
    }
}
