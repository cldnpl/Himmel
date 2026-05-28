//
//  CelestialObject.swift
//  Himmel
//
//  Data models for everything we render on the celestial sphere.
//

import Foundation
import simd

/// Top-level categorization for tappable sky objects.
enum CelestialObjectType: String, Codable, Hashable {
    case star
    case planet
    case moon
    case sun
    case constellation
    case satellite
    case deepSky

    var displayName: String {
        switch self {
        case .star: return "Star"
        case .planet: return "Planet"
        case .moon: return "Moon"
        case .sun: return "Sun"
        case .constellation: return "Constellation"
        case .satellite: return "Satellite"
        case .deepSky: return "Deep-Sky Object"
        }
    }

    var symbolName: String {
        switch self {
        case .star: return "sparkle"
        case .planet: return "circle.fill"
        case .moon: return "moon.fill"
        case .sun: return "sun.max.fill"
        case .constellation: return "point.3.connected.trianglepath.dotted"
        case .satellite: return "antenna.radiowaves.left.and.right"
        case .deepSky: return "atom"
        }
    }
}

/// Equatorial coordinates (J2000 epoch).
struct EquatorialCoordinate: Hashable, Codable {
    /// Right ascension in hours (0..<24).
    var rightAscensionHours: Double
    /// Declination in degrees (-90...+90).
    var declinationDegrees: Double

    var rightAscensionDegrees: Double { rightAscensionHours * 15.0 }
    var rightAscensionRadians: Double { rightAscensionDegrees * .pi / 180.0 }
    var declinationRadians: Double { declinationDegrees * .pi / 180.0 }

    /// Direct conversion of equatorial coordinates to a unit Cartesian vector in
    /// the (fixed) equatorial frame:
    ///
    ///     x = cos(δ) · cos(α)
    ///     y = cos(δ) · sin(α)
    ///     z = sin(δ)
    ///
    /// where α = right ascension and δ = declination.
    ///
    /// NOTE: This frame is *not* aligned with the observer's horizon. Himmel
    /// renders a topocentric sky (what you actually see from your location at
    /// this instant), so the production path is:
    ///   RA/Dec ──AstronomicalMath.horizontal()──▶ Alt/Az ──worldDirection──▶ XYZ
    /// Use this helper only if you want a location-independent "equatorial globe"
    /// (e.g. an inset star-globe widget).
    var equatorialUnitVector: SIMD3<Float> {
        let ra = Float(rightAscensionRadians)
        let dec = Float(declinationRadians)
        let cosDec = cos(dec)
        return SIMD3<Float>(cosDec * cos(ra), cosDec * sin(ra), sin(dec))
    }
}

/// Topocentric (horizontal) coordinates for a specific observer + time.
struct HorizontalCoordinate: Hashable {
    /// Azimuth, measured clockwise from true North, in degrees (0..<360).
    var azimuthDegrees: Double
    /// Altitude above the horizon, in degrees (-90...+90).
    var altitudeDegrees: Double

    var azimuthRadians: Double { azimuthDegrees * .pi / 180.0 }
    var altitudeRadians: Double { altitudeDegrees * .pi / 180.0 }

    /// Unit direction vector in scene world space matching CoreMotion's
    /// `xMagneticNorthZVertical` reference frame, which is right-handed with
    /// +X = North, +Y = West, +Z = Up.
    ///
    /// Azimuth is measured from North, increasing clockwise toward East, so the
    /// East component is sin(az) and therefore the West (+Y) component is -sin(az).
    /// Az = 0   (N) → (+1,  0, 0)
    /// Az = 90  (E) → ( 0, -1, 0)
    /// Az = 270 (W) → ( 0, +1, 0)
    /// Alt = 90 (zenith) → (0, 0, +1)
    var worldDirection: SIMD3<Float> {
        let alt = Float(altitudeRadians)
        let az = Float(azimuthRadians)
        let cosAlt = cos(alt)
        return SIMD3<Float>(
            x: cos(az) * cosAlt,
            y: -sin(az) * cosAlt,
            z: sin(alt)
        )
    }
}

/// A tappable, renderable object on the celestial sphere.
struct CelestialObject: Identifiable, Hashable {
    let id: String
    let name: String
    let type: CelestialObjectType
    /// Fixed coords for stars/deep-sky; nil for planets (computed at runtime).
    var equatorial: EquatorialCoordinate?
    /// Apparent visual magnitude. Lower = brighter.
    var magnitude: Double?
    /// Optional Bayer / catalog designation.
    var designation: String?
    /// Short tagline shown at the top of the info sheet.
    var subtitle: String
    /// Longer, accessible description.
    var summary: String
    /// Optional fact bullets for the detail sheet.
    var facts: [String]

    init(
        id: String,
        name: String,
        type: CelestialObjectType,
        equatorial: EquatorialCoordinate? = nil,
        magnitude: Double? = nil,
        designation: String? = nil,
        subtitle: String,
        summary: String,
        facts: [String] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.equatorial = equatorial
        self.magnitude = magnitude
        self.designation = designation
        self.subtitle = subtitle
        self.summary = summary
        self.facts = facts
    }
}

/// One drawn line of a constellation, connecting two stars by their catalog IDs.
struct ConstellationLine: Hashable {
    let starA: String
    let starB: String
}

/// Constellation metadata. Tap-targeting happens on its anchor star(s).
struct Constellation: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let lines: [ConstellationLine]
    /// IDs of the brightest stars in the asterism — used to place the label
    /// and to attach a tap target if needed.
    let anchorStarIds: [String]
}
