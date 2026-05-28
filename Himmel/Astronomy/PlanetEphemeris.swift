//
//  PlanetEphemeris.swift
//  Himmel
//
//  Low-precision ephemeris (~1° accuracy) adequate for AR visualisation.
//  Based on Paul Schlyter's "Computing planetary positions" notes
//  (http://stjarnhimlen.se/comp/ppcomp.html). Adequate for Sun, Moon and
//  the five naked-eye planets within a few decades of J2000.
//

import Foundation

enum PlanetEphemeris {

    enum Body: String, CaseIterable {
        case sun, moon, mercury, venus, mars, jupiter, saturn

        var displayName: String {
            switch self {
            case .sun:     return "Sun"
            case .moon:    return "Moon"
            case .mercury: return "Mercury"
            case .venus:   return "Venus"
            case .mars:    return "Mars"
            case .jupiter: return "Jupiter"
            case .saturn:  return "Saturn"
            }
        }

        var celestialType: CelestialObjectType {
            switch self {
            case .sun:  return .sun
            case .moon: return .moon
            default:    return .planet
            }
        }
    }

    // MARK: - Public API

    /// Geocentric equatorial coordinates (RA/Dec, equinox of date) for the given body.
    static func equatorial(for body: Body, at date: Date) -> EquatorialCoordinate {
        let d = daysSinceJ2000(date)
        let eclRad = deg2rad(obliquityDegrees(d: d))
        switch body {
        case .sun:  return sunEquatorial(d: d, eclRad: eclRad)
        case .moon: return moonEquatorial(d: d, eclRad: eclRad)
        default:    return planetEquatorial(body: body, d: d, eclRad: eclRad)
        }
    }

    // MARK: - Helpers

    private static func daysSinceJ2000(_ date: Date) -> Double {
        // Schlyter's epoch is 2000 Jan 0.0 UT = JD 2451543.5
        AstronomicalMath.julianDate(from: date) - 2_451_543.5
    }

    private static func obliquityDegrees(d: Double) -> Double {
        23.4393 - 3.563e-7 * d
    }

    private static func normDeg(_ x: Double) -> Double {
        var y = x.truncatingRemainder(dividingBy: 360.0)
        if y < 0 { y += 360.0 }
        return y
    }

    private static func deg2rad(_ x: Double) -> Double { x * .pi / 180.0 }
    private static func rad2deg(_ x: Double) -> Double { x * 180.0 / .pi }

    // MARK: - Orbital elements

    private struct OrbitalElements {
        var N: Double  // longitude of ascending node (deg)
        var i: Double  // inclination (deg)
        var w: Double  // argument of perihelion (deg)
        var a: Double  // semi-major axis (AU or Earth radii for Moon)
        var e: Double  // eccentricity
        var M: Double  // mean anomaly (deg)
    }

    private static func sunElements(d: Double) -> OrbitalElements {
        OrbitalElements(
            N: 0,
            i: 0,
            w: normDeg(282.9404 + 4.70935e-5 * d),
            a: 1.0,
            e: 0.016709 - 1.151e-9 * d,
            M: normDeg(356.0470 + 0.985_600_2585 * d)
        )
    }

    private static func planetElements(body: Body, d: Double) -> OrbitalElements {
        switch body {
        case .mercury:
            return OrbitalElements(
                N: normDeg(48.3313 + 3.24587e-5 * d),
                i: 7.0047 + 5.00e-8 * d,
                w: normDeg(29.1241 + 1.01444e-5 * d),
                a: 0.387098,
                e: 0.205635 + 5.59e-10 * d,
                M: normDeg(168.6562 + 4.092_334_4368 * d)
            )
        case .venus:
            return OrbitalElements(
                N: normDeg(76.6799 + 2.46590e-5 * d),
                i: 3.3946 + 2.75e-8 * d,
                w: normDeg(54.8910 + 1.38374e-5 * d),
                a: 0.723330,
                e: 0.006773 - 1.302e-9 * d,
                M: normDeg(48.0052 + 1.602_130_2244 * d)
            )
        case .mars:
            return OrbitalElements(
                N: normDeg(49.5574 + 2.11081e-5 * d),
                i: 1.8497 - 1.78e-8 * d,
                w: normDeg(286.5016 + 2.92961e-5 * d),
                a: 1.523688,
                e: 0.093405 + 2.516e-9 * d,
                M: normDeg(18.6021 + 0.524_020_7766 * d)
            )
        case .jupiter:
            return OrbitalElements(
                N: normDeg(100.4542 + 2.76854e-5 * d),
                i: 1.3030 - 1.557e-7 * d,
                w: normDeg(273.8777 + 1.64505e-5 * d),
                a: 5.20256,
                e: 0.048498 + 4.469e-9 * d,
                M: normDeg(19.8950 + 0.083_085_3001 * d)
            )
        case .saturn:
            return OrbitalElements(
                N: normDeg(113.6634 + 2.38980e-5 * d),
                i: 2.4886 - 1.081e-7 * d,
                w: normDeg(339.3939 + 2.97661e-5 * d),
                a: 9.55475,
                e: 0.055546 - 9.499e-9 * d,
                M: normDeg(316.9670 + 0.033_444_2282 * d)
            )
        default:
            return OrbitalElements(N: 0, i: 0, w: 0, a: 1, e: 0, M: 0)
        }
    }

    // MARK: - Sun

    private static func sunEquatorial(d: Double, eclRad: Double) -> EquatorialCoordinate {
        let s = sunElements(d: d)
        let (xs, ys) = sunRectangular(elements: s)
        let xe = xs
        let ye = ys * cos(eclRad)
        let ze = ys * sin(eclRad)
        return equatorialFromRectangular(x: xe, y: ye, z: ze)
    }

    /// Sun's rectangular ecliptic coordinates (heliocentric earth reflected) in AU.
    private static func sunRectangular(elements s: OrbitalElements) -> (x: Double, y: Double) {
        let Mrad = deg2rad(s.M)
        let e = s.e
        let E = solveKepler(M: Mrad, e: e)
        let xv = cos(E) - e
        let yv = sqrt(1 - e * e) * sin(E)
        let v = atan2(yv, xv)
        let r = sqrt(xv * xv + yv * yv)
        let lon = v + deg2rad(s.w)
        return (r * cos(lon), r * sin(lon))
    }

    // MARK: - Planets

    private static func planetEquatorial(body: Body, d: Double, eclRad: Double) -> EquatorialCoordinate {
        let p = planetElements(body: body, d: d)
        let Mrad = deg2rad(p.M)
        let E = solveKepler(M: Mrad, e: p.e)
        let xv = p.a * (cos(E) - p.e)
        let yv = p.a * sqrt(1 - p.e * p.e) * sin(E)
        let v = atan2(yv, xv)
        let r = sqrt(xv * xv + yv * yv)

        let N = deg2rad(p.N), w = deg2rad(p.w), i = deg2rad(p.i)
        let vw = v + w

        // Heliocentric ecliptic rectangular
        let xh = r * (cos(N) * cos(vw) - sin(N) * sin(vw) * cos(i))
        let yh = r * (sin(N) * cos(vw) + cos(N) * sin(vw) * cos(i))
        let zh = r * sin(vw) * sin(i)

        // Translate to geocentric: add Sun (= -Earth's heliocentric position)
        let sunEl = sunElements(d: d)
        let (xs, ys) = sunRectangular(elements: sunEl)

        let xg = xh + xs
        let yg = yh + ys
        let zg = zh

        // Rotate to equatorial
        let xe = xg
        let ye = yg * cos(eclRad) - zg * sin(eclRad)
        let ze = yg * sin(eclRad) + zg * cos(eclRad)
        return equatorialFromRectangular(x: xe, y: ye, z: ze)
    }

    // MARK: - Moon

    private static func moonEquatorial(d: Double, eclRad: Double) -> EquatorialCoordinate {
        let NDeg = normDeg(125.1228 - 0.052_953_8083 * d)
        let iDeg = 5.1454
        let wDeg = normDeg(318.0634 + 0.164_357_3223 * d)
        let a = 60.2666 // Earth radii
        let e = 0.054900
        let MDeg = normDeg(115.3654 + 13.064_992_9509 * d)

        let N = deg2rad(NDeg), w = deg2rad(wDeg), iRad = deg2rad(iDeg)
        let Mrad = deg2rad(MDeg)
        let E = solveKepler(M: Mrad, e: e)

        let xv = a * (cos(E) - e)
        let yv = a * sqrt(1 - e * e) * sin(E)
        let v = atan2(yv, xv)
        let r = sqrt(xv * xv + yv * yv)
        let vw = v + w

        let xh = r * (cos(N) * cos(vw) - sin(N) * sin(vw) * cos(iRad))
        let yh = r * (sin(N) * cos(vw) + cos(N) * sin(vw) * cos(iRad))
        let zh = r * sin(vw) * sin(iRad)

        // Main perturbations (Schlyter §13)
        let Ls = normDeg(280.4665 + 0.9856474 * d)
        let Ms = normDeg(356.0470 + 0.985_600_2585 * d)
        let Lm = normDeg(NDeg + wDeg + MDeg)
        let DDeg = Lm - Ls
        let FDeg = Lm - NDeg
        let MmDeg = MDeg

        let lonCorrDeg =
            -1.274 * sin(deg2rad(MmDeg - 2 * DDeg))
          + 0.658 * sin(deg2rad(2 * DDeg))
          - 0.186 * sin(deg2rad(Ms))
          - 0.059 * sin(deg2rad(2 * MmDeg - 2 * DDeg))
          - 0.057 * sin(deg2rad(MmDeg - 2 * DDeg + Ms))
          + 0.053 * sin(deg2rad(MmDeg + 2 * DDeg))
          + 0.046 * sin(deg2rad(2 * DDeg - Ms))
          + 0.041 * sin(deg2rad(MmDeg - Ms))
          - 0.035 * sin(deg2rad(DDeg))
          - 0.031 * sin(deg2rad(MmDeg + Ms))
        let latCorrDeg =
            -0.173 * sin(deg2rad(FDeg - 2 * DDeg))
          - 0.055 * sin(deg2rad(MmDeg - FDeg - 2 * DDeg))
          - 0.046 * sin(deg2rad(MmDeg + FDeg - 2 * DDeg))
          + 0.033 * sin(deg2rad(FDeg + 2 * DDeg))
          + 0.017 * sin(deg2rad(2 * MmDeg + FDeg))

        let lon = atan2(yh, xh) + deg2rad(lonCorrDeg)
        let lat = atan2(zh, sqrt(xh * xh + yh * yh)) + deg2rad(latCorrDeg)

        let xg = r * cos(lon) * cos(lat)
        let yg = r * sin(lon) * cos(lat)
        let zg = r * sin(lat)

        let xe = xg
        let ye = yg * cos(eclRad) - zg * sin(eclRad)
        let ze = yg * sin(eclRad) + zg * cos(eclRad)
        return equatorialFromRectangular(x: xe, y: ye, z: ze)
    }

    // MARK: - Shared math

    /// Solve Kepler's equation `E - e·sin(E) = M` (radians) via Newton iteration.
    private static func solveKepler(M: Double, e: Double, iterations: Int = 8) -> Double {
        var E = M + e * sin(M) * (1.0 + e * cos(M))
        for _ in 0..<iterations {
            let dE = (E - e * sin(E) - M) / (1 - e * cos(E))
            E -= dE
            if abs(dE) < 1e-9 { break }
        }
        return E
    }

    private static func equatorialFromRectangular(x: Double, y: Double, z: Double) -> EquatorialCoordinate {
        var raDeg = rad2deg(atan2(y, x))
        raDeg = normDeg(raDeg)
        let decDeg = rad2deg(atan2(z, sqrt(x * x + y * y)))
        return EquatorialCoordinate(
            rightAscensionHours: raDeg / 15.0,
            declinationDegrees: decDeg
        )
    }
}
