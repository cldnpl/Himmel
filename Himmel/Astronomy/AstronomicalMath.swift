//
//  AstronomicalMath.swift
//  Himmel
//
//  Pure-function module for the small slice of spherical astronomy Himmel needs:
//  Julian Date, sidereal time, and equatorial → horizontal coordinate transforms.
//  Formulas: Meeus, "Astronomical Algorithms" (low-precision forms).
//

import Foundation


enum AstronomicalMath {

    // MARK: - Julian Date

    /// Julian Date for an arbitrary UTC instant.
    static func julianDate(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
    }

    /// Centuries since the J2000.0 epoch (TT, but TT-UT is irrelevant here).
    static func julianCenturies(from date: Date) -> Double {
        (julianDate(from: date) - 2_451_545.0) / 36_525.0
    }

    // MARK: - Sidereal time

    /// Greenwich Mean Sidereal Time in degrees [0, 360). Meeus eq. 12.4.
    static func greenwichMeanSiderealTimeDegrees(at date: Date) -> Double {
        let jd = julianDate(from: date)
        let t = (jd - 2_451_545.0) / 36_525.0
        var gmst = 280.460_618_37
            + 360.985_647_366_29 * (jd - 2_451_545.0)
            + 0.000_387_933 * t * t
            - (t * t * t) / 38_710_000.0
        gmst = gmst.truncatingRemainder(dividingBy: 360.0)
        if gmst < 0 { gmst += 360.0 }
        return gmst
    }

    /// Local Mean Sidereal Time in degrees for the given longitude (east positive).
    static func localSiderealTimeDegrees(at date: Date, longitudeDegrees: Double) -> Double {
        var lst = greenwichMeanSiderealTimeDegrees(at: date) + longitudeDegrees
        lst = lst.truncatingRemainder(dividingBy: 360.0)
        if lst < 0 { lst += 360.0 }
        return lst
    }

    // MARK: - Equatorial → Horizontal

    /// Convert equatorial (RA/Dec) to topocentric horizontal (Az/Alt) for an observer.
    /// Azimuth in the returned value is measured from true North, increasing clockwise.
    static func horizontal(
        from equatorial: EquatorialCoordinate,
        at date: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double
    ) -> HorizontalCoordinate {
        let lstDeg = localSiderealTimeDegrees(at: date, longitudeDegrees: longitudeDegrees)
        var haDeg = lstDeg - equatorial.rightAscensionDegrees
        haDeg = haDeg.truncatingRemainder(dividingBy: 360.0)
        if haDeg < -180 { haDeg += 360 } else if haDeg > 180 { haDeg -= 360 }

        let haRad = haDeg * .pi / 180.0
        let decRad = equatorial.declinationRadians
        let latRad = latitudeDegrees * .pi / 180.0

        let sinAlt = sin(decRad) * sin(latRad) + cos(decRad) * cos(latRad) * cos(haRad)
        let altRad = asin(max(-1.0, min(1.0, sinAlt)))

        // Meeus azimuth (measured westward from South); convert to "from North, CW".
        let y = sin(haRad)
        let x = cos(haRad) * sin(latRad) - tan(decRad) * cos(latRad)
        let azFromSouth = atan2(y, x)
        var azDeg = azFromSouth * 180.0 / .pi + 180.0
        azDeg = azDeg.truncatingRemainder(dividingBy: 360.0)
        if azDeg < 0 { azDeg += 360.0 }

        return HorizontalCoordinate(
            azimuthDegrees: azDeg,
            altitudeDegrees: altRad * 180.0 / .pi
        )
    }
}
