//
//  EventsCatalog.swift
//  Himmel
//
//  Static dataset that powers the "Featured Astronomy" panel.
//  Entries fall into two families:
//
//   1. Recurring date windows (meteor showers, equinoxes/solstices) — defined by
//      month/day and matched against the current date.
//   2. Computed events (currexrnt moon phase) — derived at runtime.
//
//  For MVP we use a static recurring dataset. A later milestone can fetch live
//  data (ISS passes, eclipses) from a remote service.
//

import Foundation

enum AstronomicalEventCategory: String, Hashable {
    case meteorShower
    case planetaryAlignment
    case moonPhase
    case eclipse
    case season
    case deepSky
    case other

    var displayName: String {
        switch self {
        case .meteorShower:       return "Meteor Shower"
        case .planetaryAlignment: return "Planetary Alignment"
        case .moonPhase:          return "Moon Phase"
        case .eclipse:            return "Eclipse"
        case .season:             return "Season Marker"
        case .deepSky:            return "Deep Sky"
        case .other:              return "Sky Event"
        }
    }

    var symbolName: String {
        switch self {
        case .meteorShower:       return "sparkles"
        case .planetaryAlignment: return "circle.hexagongrid.fill"
        case .moonPhase:          return "moon.stars.fill"
        case .eclipse:            return "circle.lefthalf.filled"
        case .season:             return "leaf.fill"
        case .deepSky:            return "hurricane"
        case .other:              return "sparkle"
        }
    }
}

struct AstronomicalEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let category: AstronomicalEventCategory
    let summary: String
    let visibility: String
    /// Human-readable time window, e.g. "Aug 11 – Aug 13, peak overnight Aug 12".
    let window: String
}

enum EventsCatalog {

    /// Build the list of events relevant to `date` (today by default).
    static func events(for date: Date = Date()) -> [AstronomicalEvent] {
        var result: [AstronomicalEvent] = []

        // ── Recurring meteor showers & celestial markers ─────────────────────
        for entry in recurringEntries {
            if entry.matches(date) {
                result.append(entry.event)
            }
        }

        // ── Dynamic: current moon phase ──────────────────────────────────────
        let phase = MoonPhase.phase(at: date)
        result.append(AstronomicalEvent(
            id: "moon-phase-\(phase.name.rawValue)",
            title: phase.name.rawValue,
            category: .moonPhase,
            summary: moonPhaseSummary(phase.name),
            visibility: moonPhaseVisibility(phase.name),
            window: String(format: "Illumination: %.0f%%", phase.illumination * 100)
        ))

        return result
    }

    // MARK: - Recurring entries

    /// Matches a calendar window in any year.
    private struct RecurringEntry {
        let startMonth: Int
        let startDay: Int
        let endMonth: Int
        let endDay: Int
        let event: AstronomicalEvent

        func matches(_ date: Date) -> Bool {
            let cal = Calendar(identifier: .gregorian)
            let comps = cal.dateComponents([.month, .day], from: date)
            guard let m = comps.month, let d = comps.day else { return false }
            let cur = m * 100 + d
            let start = startMonth * 100 + startDay
            let end = endMonth * 100 + endDay
            // Handle ranges that wrap across the new year
            if start <= end {
                return cur >= start && cur <= end
            } else {
                return cur >= start || cur <= end
            }
        }
    }

    private static let recurringEntries: [RecurringEntry] = [
        RecurringEntry(
            startMonth: 1, startDay: 1, endMonth: 1, endDay: 5,
            event: AstronomicalEvent(
                id: "quadrantids",
                title: "Quadrantids Meteor Shower",
                category: .meteorShower,
                summary: "A short, intense shower with up to 110 meteors per hour at peak — radiating from the now-defunct constellation Quadrans Muralis, near the handle of the Big Dipper.",
                visibility: "Best seen from the Northern Hemisphere in the pre-dawn hours, with the radiant high in the northeast.",
                window: "Jan 1 – Jan 5, peak overnight Jan 3–4."
            )
        ),
        RecurringEntry(
            startMonth: 4, startDay: 16, endMonth: 4, endDay: 25,
            event: AstronomicalEvent(
                id: "lyrids",
                title: "Lyrids Meteor Shower",
                category: .meteorShower,
                summary: "A reliable spring shower producing roughly 15–20 meteors per hour, with occasional bright fireballs.",
                visibility: "Look toward the radiant near Vega in Lyra, highest overhead after midnight.",
                window: "Apr 16 – Apr 25, peak overnight Apr 22."
            )
        ),
        RecurringEntry(
            startMonth: 4, startDay: 19, endMonth: 5, endDay: 28,
            event: AstronomicalEvent(
                id: "eta-aquariids",
                title: "Eta Aquariid Meteor Shower",
                category: .meteorShower,
                summary: "Debris from Halley's Comet producing fast meteors with long trains — up to 30 per hour at peak.",
                visibility: "Best in the Southern Hemisphere, in the hours before dawn looking east.",
                window: "Apr 19 – May 28, peak overnight May 5–6."
            )
        ),
        RecurringEntry(
            startMonth: 6, startDay: 19, endMonth: 6, endDay: 22,
            event: AstronomicalEvent(
                id: "june-solstice",
                title: "June Solstice",
                category: .season,
                summary: "The Sun reaches its northernmost point in the sky — longest day in the Northern Hemisphere and shortest in the Southern.",
                visibility: "A symbolic event, observable as the longest (or shortest) daylight period of the year.",
                window: "Around June 20–21."
            )
        ),
        RecurringEntry(
            startMonth: 7, startDay: 17, endMonth: 8, endDay: 24,
            event: AstronomicalEvent(
                id: "perseids",
                title: "Perseids Meteor Shower",
                category: .meteorShower,
                summary: "One of the year's most reliable showers, producing up to 100 meteors per hour at peak from the dust of comet 109P/Swift-Tuttle.",
                visibility: "Best in the Northern Hemisphere overnight, with the radiant in Perseus rising in the northeast after sunset.",
                window: "Jul 17 – Aug 24, peak overnight Aug 12–13."
            )
        ),
        RecurringEntry(
            startMonth: 9, startDay: 21, endMonth: 9, endDay: 24,
            event: AstronomicalEvent(
                id: "september-equinox",
                title: "September Equinox",
                category: .season,
                summary: "Day and night are nearly equal in length across the globe as the Sun crosses the celestial equator heading south.",
                visibility: "Sun rises due east and sets due west on the day of the equinox.",
                window: "Around September 22–23."
            )
        ),
        RecurringEntry(
            startMonth: 10, startDay: 2, endMonth: 11, endDay: 7,
            event: AstronomicalEvent(
                id: "orionids",
                title: "Orionid Meteor Shower",
                category: .meteorShower,
                summary: "Fast meteors and persistent trains from the second debris stream of Halley's Comet — about 20 meteors per hour at peak.",
                visibility: "Visible from both hemispheres, with the radiant near Betelgeuse rising before midnight.",
                window: "Oct 2 – Nov 7, peak overnight Oct 21–22."
            )
        ),
        RecurringEntry(
            startMonth: 11, startDay: 6, endMonth: 11, endDay: 30,
            event: AstronomicalEvent(
                id: "leonids",
                title: "Leonid Meteor Shower",
                category: .meteorShower,
                summary: "Famously produces meteor storms every ~33 years; in normal years expect ~15 fast meteors per hour.",
                visibility: "Radiant in Leo, rising after midnight. Visible globally where Leo is above the horizon.",
                window: "Nov 6 – Nov 30, peak overnight Nov 17–18."
            )
        ),
        RecurringEntry(
            startMonth: 12, startDay: 4, endMonth: 12, endDay: 17,
            event: AstronomicalEvent(
                id: "geminids",
                title: "Geminids Meteor Shower",
                category: .meteorShower,
                summary: "Often the year's best shower — up to 120 colorful, slow meteors per hour, originating from asteroid 3200 Phaethon.",
                visibility: "Visible worldwide. Radiant rises in the early evening near Castor in Gemini.",
                window: "Dec 4 – Dec 17, peak overnight Dec 13–14."
            )
        ),
        RecurringEntry(
            startMonth: 12, startDay: 20, endMonth: 12, endDay: 23,
            event: AstronomicalEvent(
                id: "december-solstice",
                title: "December Solstice",
                category: .season,
                summary: "Sun reaches its southernmost point — shortest day in the Northern Hemisphere and longest in the Southern.",
                visibility: "Marks the start of astronomical winter or summer depending on hemisphere.",
                window: "Around December 21–22."
            )
        ),

        // ── Seasonal deep-sky highlights (nebulae, galaxies, clusters) ───────
        // Overlapping windows so most nights surface at least one target.
        RecurringEntry(
            startMonth: 11, startDay: 15, endMonth: 3, endDay: 20,
            event: AstronomicalEvent(
                id: "orion-nebula",
                title: "Orion Nebula (M42)",
                category: .deepSky,
                summary: "A vast stellar nursery 1,344 light-years away, glowing in Orion's Sword. Visible to the naked eye as a fuzzy patch and stunning through binoculars.",
                visibility: "High in the southern evening sky through winter. Look just below Orion's Belt.",
                window: "Best Nov–Mar, evening."
            )
        ),
        RecurringEntry(
            startMonth: 10, startDay: 15, endMonth: 3, endDay: 1,
            event: AstronomicalEvent(
                id: "pleiades",
                title: "Pleiades (M45)",
                category: .deepSky,
                summary: "The 'Seven Sisters' — a brilliant young open star cluster ~440 light-years away, unmistakable as a tiny dipper of blue-white stars.",
                visibility: "Rises in the east after sunset and climbs high overhead in winter. Naked-eye from dark skies.",
                window: "Best Oct–Feb, evening."
            )
        ),
        RecurringEntry(
            startMonth: 8, startDay: 15, endMonth: 12, endDay: 20,
            event: AstronomicalEvent(
                id: "andromeda-galaxy",
                title: "Andromeda Galaxy (M31)",
                category: .deepSky,
                summary: "The nearest large spiral galaxy, 2.5 million light-years away — the most distant object visible to the unaided eye, spanning several Moon-widths.",
                visibility: "High in the autumn sky. Find it off the corner of the Great Square of Pegasus on a moonless night.",
                window: "Best Sep–Dec, evening."
            )
        ),
        RecurringEntry(
            startMonth: 2, startDay: 1, endMonth: 5, endDay: 10,
            event: AstronomicalEvent(
                id: "beehive-cluster",
                title: "Beehive Cluster (M44)",
                category: .deepSky,
                summary: "A swarm of around a thousand stars in Cancer, ~580 light-years away. A faint glow to the eye that resolves into dozens of stars in binoculars.",
                visibility: "Well placed high in the south on spring evenings, between Gemini and Leo.",
                window: "Best Feb–Apr, evening."
            )
        ),
        RecurringEntry(
            startMonth: 4, startDay: 20, endMonth: 9, endDay: 1,
            event: AstronomicalEvent(
                id: "hercules-cluster",
                title: "Hercules Cluster (M13)",
                category: .deepSky,
                summary: "The finest globular cluster of the northern sky — several hundred thousand ancient stars packed into a glowing ball ~25,000 light-years away.",
                visibility: "Rises in the east in late spring and rides high overhead in summer, in the Keystone of Hercules.",
                window: "Best May–Aug, late evening."
            )
        ),
        RecurringEntry(
            startMonth: 6, startDay: 1, endMonth: 9, endDay: 20,
            event: AstronomicalEvent(
                id: "lagoon-nebula",
                title: "Lagoon Nebula (M8)",
                category: .deepSky,
                summary: "A bright emission nebula and star-forming region in Sagittarius, ~4,000 light-years away, set against the rich star clouds of the Milky Way's core.",
                visibility: "Low in the south on summer nights, toward the heart of the Milky Way. Best from dark skies.",
                window: "Best Jun–Sep, late evening."
            )
        ),
        RecurringEntry(
            startMonth: 7, startDay: 1, endMonth: 10, endDay: 25,
            event: AstronomicalEvent(
                id: "ring-nebula",
                title: "Ring Nebula (M57)",
                category: .deepSky,
                summary: "A dying star's exhaled shell of gas — a tiny smoke-ring of light ~2,600 light-years away in Lyra. A telescope target near brilliant Vega.",
                visibility: "High overhead on summer and autumn evenings, between the two southern stars of Lyra.",
                window: "Best Jul–Oct, evening."
            )
        )
    ]

    // MARK: - Moon phase copy

    static func moonPhaseSummary(_ name: MoonPhase.Name) -> String {
        switch name {
        case .newMoon:        return "The Moon is between the Earth and the Sun, with its illuminated side facing away from us. This is the darkest time of the lunar month — perfect for observing faint stars and the Milky Way."
        case .waxingCrescent: return "A thin crescent grows on the right (in the Northern Hemisphere), visible in the western sky after sunset."
        case .firstQuarter:   return "Half of the Moon is illuminated — a great time to observe craters along the terminator with binoculars or a telescope."
        case .waxingGibbous:  return "More than half of the Moon is lit. It rises in the afternoon and sets well after midnight."
        case .fullMoon:       return "The Moon is opposite the Sun — fully illuminated and visible all night. Bright skies make this the worst time for deep-sky observing but the best time for lunar photography."
        case .waningGibbous:  return "The illuminated portion shrinks. The Moon rises in the evening and stays up through the morning."
        case .lastQuarter:    return "Half-illuminated on the opposite side from the First Quarter. Best observed in the early morning hours."
        case .waningCrescent: return "A thin sliver in the eastern sky before sunrise — heralding the return of the new moon."
        }
    }

    static func moonPhaseVisibility(_ name: MoonPhase.Name) -> String {
        switch name {
        case .newMoon, .waxingCrescent:  return "Best observed shortly after sunset, low in the western sky."
        case .firstQuarter:              return "Visible from afternoon through midnight, high in the south at sunset."
        case .waxingGibbous, .fullMoon:  return "Visible most of the night, rising around sunset."
        case .waningGibbous:             return "Rises after dark; well placed in the early morning hours."
        case .lastQuarter, .waningCrescent: return "Best observed in the pre-dawn sky."
        }
    }
}
