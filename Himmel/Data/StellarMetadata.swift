//
//  StellarMetadata.swift
//  Himmel
//
//  Presentation-focused stellar facts for the detail sheet. Values are kept in
//  English display units so the UI can render a consistent four-field footer.
//

import Foundation

struct StellarMetadata: Hashable {
    let age: String
    let color: String
    let temperature: String
    let distanceFromEarth: String
    /// Physical diameter, expressed relative to the Sun (or km for the Sun).
    let diameter: String

    static func make(for object: CelestialObject) -> StellarMetadata {
        if object.type == .sun {
            return StellarMetadata(
                age: "4.6 billion years",
                color: "Yellow-white",
                temperature: "5,778 K",
                distanceFromEarth: "0.000016 light-years",
                diameter: "1,392,700 km"
            )
        }

        if let curated = curatedByID[object.id.lowercased()] {
            return curated
        }

        let classification = StellarClassification.infer(from: object)
        return StellarMetadata(
            age: fallbackAge(for: classification),
            color: fallbackColor(for: classification),
            temperature: fallbackTemperature(for: classification),
            distanceFromEarth: lightYearDistance(from: object) ?? "Unknown",
            diameter: fallbackDiameter(for: classification)
        )
    }

    private static let curatedByID: [String: StellarMetadata] = [
        "sirius": StellarMetadata(age: "242 million years", color: "Blue-white", temperature: "9,940 K", distanceFromEarth: "8.6 light-years", diameter: "1.7× the Sun"),
        "vega": StellarMetadata(age: "455 million years", color: "Blue-white", temperature: "9,600 K", distanceFromEarth: "25 light-years", diameter: "2.4× the Sun"),
        "rigel": StellarMetadata(age: "8 million years", color: "Blue supergiant", temperature: "12,100 K", distanceFromEarth: "860 light-years", diameter: "78× the Sun"),
        "betelgeuse": StellarMetadata(age: "8-10 million years", color: "Red supergiant", temperature: "3,500 K", distanceFromEarth: "550 light-years", diameter: "≈ 764× the Sun"),
        "aldebaran": StellarMetadata(age: "6.4 billion years", color: "Orange-red giant", temperature: "3,900 K", distanceFromEarth: "65 light-years", diameter: "44× the Sun"),
        "antares": StellarMetadata(age: "11 million years", color: "Red supergiant", temperature: "3,660 K", distanceFromEarth: "550 light-years", diameter: "≈ 680× the Sun"),
        "arcturus": StellarMetadata(age: "7.1 billion years", color: "Orange giant", temperature: "4,290 K", distanceFromEarth: "37 light-years", diameter: "25× the Sun"),
        "polaris": StellarMetadata(age: "70 million years", color: "Yellow-white supergiant", temperature: "6,000 K", distanceFromEarth: "447 light-years", diameter: "37× the Sun"),
        "capella": StellarMetadata(age: "590 million years", color: "Yellow giant pair", temperature: "5,700 K", distanceFromEarth: "42 light-years", diameter: "12× the Sun"),
        "procyon": StellarMetadata(age: "1.9 billion years", color: "Yellow-white", temperature: "6,530 K", distanceFromEarth: "11.4 light-years", diameter: "2× the Sun"),
        "altair": StellarMetadata(age: "1.2 billion years", color: "White", temperature: "7,550 K", distanceFromEarth: "17 light-years", diameter: "1.8× the Sun"),
        "deneb": StellarMetadata(age: "10 million years", color: "Blue-white supergiant", temperature: "8,525 K", distanceFromEarth: "2,600 light-years", diameter: "≈ 203× the Sun"),
        "spica": StellarMetadata(age: "12 million years", color: "Blue-white", temperature: "22,400 K", distanceFromEarth: "250 light-years", diameter: "7.4× the Sun"),
        "pollux": StellarMetadata(age: "724 million years", color: "Orange giant", temperature: "4,865 K", distanceFromEarth: "34 light-years", diameter: "9× the Sun"),
        "fomalhaut": StellarMetadata(age: "440 million years", color: "White", temperature: "8,590 K", distanceFromEarth: "25 light-years", diameter: "1.8× the Sun"),
        "canopus": StellarMetadata(age: "25 million years", color: "Yellow-white supergiant", temperature: "7,350 K", distanceFromEarth: "310 light-years", diameter: "71× the Sun")
    ]

    private static func fallbackAge(for classification: StellarClassification) -> String {
        switch classification {
        case .blueSupergiant: return "10 million years"
        case .blueWhite: return "100 million years"
        case .redSupergiant: return "10 million years"
        case .redGiant: return "1-8 billion years"
        case .whiteDwarf: return "1+ billion years"
        case .whiteMainSequence: return "500 million years"
        case .yellowDwarf: return "4-10 billion years"
        }
    }

    private static func fallbackColor(for classification: StellarClassification) -> String {
        switch classification {
        case .yellowDwarf: return "Yellow-white"
        case .redGiant: return "Orange-red giant"
        case .redSupergiant: return "Red supergiant"
        case .blueWhite: return "Blue-white"
        case .blueSupergiant: return "Blue supergiant"
        case .whiteDwarf: return "White dwarf"
        case .whiteMainSequence: return "White"
        }
    }

    private static func fallbackTemperature(for classification: StellarClassification) -> String {
        switch classification {
        case .yellowDwarf: return "5,800 K"
        case .redGiant: return "4,000 K"
        case .redSupergiant: return "3,600 K"
        case .blueWhite: return "10,000 K"
        case .blueSupergiant: return "12,000 K"
        case .whiteDwarf: return "10,000 K"
        case .whiteMainSequence: return "8,000 K"
        }
    }

    private static func fallbackDiameter(for classification: StellarClassification) -> String {
        switch classification {
        case .yellowDwarf: return "≈ 1× the Sun"
        case .redGiant: return "≈ 25× the Sun"
        case .redSupergiant: return "≈ 500× the Sun"
        case .blueWhite: return "≈ 3× the Sun"
        case .blueSupergiant: return "≈ 50× the Sun"
        case .whiteDwarf: return "≈ 0.01× the Sun"
        case .whiteMainSequence: return "≈ 1.5× the Sun"
        }
    }

    private static func lightYearDistance(from object: CelestialObject) -> String? {
        let text = "\(object.summary) \(object.facts.joined(separator: " "))"
        let pattern = #"~?([0-9]+(?:\.[0-9]+)?)\s*(?:light-years|light years|ly)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return "\(text[valueRange]) light-years"
    }
}
