//
//  MoonPhase.swift
//  Himmel
//
//  Low-precision lunar phase calculation.
//

import Foundation

enum MoonPhase {

    enum Name: String {
        case newMoon         = "New Moon"
        case waxingCrescent  = "Waxing Crescent"
        case firstQuarter    = "First Quarter"
        case waxingGibbous   = "Waxing Gibbous"
        case fullMoon        = "Full Moon"
        case waningGibbous   = "Waning Gibbous"
        case lastQuarter     = "Last Quarter"
        case waningCrescent  = "Waning Crescent"

        var sfSymbol: String {
            switch self {
            case .newMoon:        return "moonphase.new.moon"
            case .waxingCrescent: return "moonphase.waxing.crescent"
            case .firstQuarter:   return "moonphase.first.quarter"
            case .waxingGibbous:  return "moonphase.waxing.gibbous"
            case .fullMoon:       return "moonphase.full.moon"
            case .waningGibbous:  return "moonphase.waning.gibbous"
            case .lastQuarter:    return "moonphase.last.quarter"
            case .waningCrescent: return "moonphase.waning.crescent"
            }
        }
    }

    struct Snapshot {
        let illumination: Double  // 0 ... 1
        let age: Double           // days since last new moon
        let name: Name
    }

    /// Phase information at the given instant. Uses the mean synodic month
    /// referenced to the new moon of 2000-01-06 18:14 UT (≈ JD 2451550.1).
    static func phase(at date: Date) -> Snapshot {
        let jd = AstronomicalMath.julianDate(from: date)
        let synodic = 29.530_588_853
        var age = (jd - 2_451_550.1).truncatingRemainder(dividingBy: synodic)
        if age < 0 { age += synodic }
        let phaseAngle = 2.0 * .pi * age / synodic
        let illumination = (1 - cos(phaseAngle)) / 2.0

        let name: Name
        switch age {
        case ..<1.845:                name = .newMoon
        case 1.845..<5.537:           name = .waxingCrescent
        case 5.537..<9.228:           name = .firstQuarter
        case 9.228..<12.919:          name = .waxingGibbous
        case 12.919..<16.610:         name = .fullMoon
        case 16.610..<20.302:         name = .waningGibbous
        case 20.302..<23.993:         name = .lastQuarter
        default:                      name = .waningCrescent
        }
        return Snapshot(illumination: illumination, age: age, name: name)
    }
}
