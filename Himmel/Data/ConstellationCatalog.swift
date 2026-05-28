//
//  ConstellationCatalog.swift
//  Himmel
//
//  Constellation asterism definitions referencing star IDs in `StarCatalog`.
//

import Foundation

enum ConstellationCatalog {

    static let all: [Constellation] = [
        Constellation(
            id: "ursa-major",
            name: "Ursa Major",
            summary: "The Great Bear, containing the iconic Big Dipper asterism — visible all year from mid-northern latitudes.",
            lines: line(
                ("alkaid", "mizar"),
                ("mizar", "alioth"),
                ("alioth", "megrez"),
                ("megrez", "phecda"),
                ("phecda", "dubhe"),
                ("dubhe", "merak"),
                ("merak", "phecda"),
                ("megrez", "dubhe")
            ),
            anchorStarIds: ["alioth", "dubhe"]
        ),
        Constellation(
            id: "ursa-minor",
            name: "Ursa Minor",
            summary: "The Little Bear, anchored by Polaris at the tip of its tail and home to the Little Dipper.",
            lines: line(
                ("polaris", "kochab"),
                ("kochab", "pherkad")
            ),
            anchorStarIds: ["polaris"]
        ),
        Constellation(
            id: "orion",
            name: "Orion",
            summary: "The Hunter — one of the most recognizable constellations, visible to nearly every observer on Earth.",
            lines: line(
                ("betelgeuse", "bellatrix"),
                ("betelgeuse", "alnitak"),
                ("bellatrix", "mintaka"),
                ("mintaka", "alnilam"),
                ("alnilam", "alnitak"),
                ("alnitak", "saiph"),
                ("mintaka", "rigel"),
                ("saiph", "rigel")
            ),
            anchorStarIds: ["betelgeuse", "rigel"]
        ),
        Constellation(
            id: "cassiopeia",
            name: "Cassiopeia",
            summary: "The Queen — a circumpolar constellation forming a distinctive W in the northern sky.",
            lines: line(
                ("caph", "schedar"),
                ("schedar", "gamma_cas"),
                ("gamma_cas", "ruchbah"),
                ("ruchbah", "segin")
            ),
            anchorStarIds: ["gamma_cas"]
        ),
        Constellation(
            id: "leo",
            name: "Leo",
            summary: "The Lion — its head and chest form the Sickle, a backwards question mark visible in spring.",
            lines: line(
                ("regulus", "algieba"),
                ("algieba", "zosma"),
                ("zosma", "denebola"),
                ("denebola", "regulus")
            ),
            anchorStarIds: ["regulus", "denebola"]
        ),
        Constellation(
            id: "cygnus",
            name: "Cygnus",
            summary: "The Swan — also called the Northern Cross, flying along the Milky Way in summer skies.",
            lines: line(
                ("deneb", "sadr"),
                ("sadr", "albireo"),
                ("sadr", "gienah_cyg"),
                ("sadr", "delta_cyg")
            ),
            anchorStarIds: ["deneb"]
        ),
        Constellation(
            id: "lyra",
            name: "Lyra",
            summary: "The Lyre — anchored by Vega, one of the corners of the Summer Triangle.",
            lines: line(
                ("vega", "sheliak"),
                ("sheliak", "sulafat"),
                ("sulafat", "vega")
            ),
            anchorStarIds: ["vega"]
        ),
        Constellation(
            id: "aquila",
            name: "Aquila",
            summary: "The Eagle — flying along the Milky Way with Altair at its heart.",
            lines: line(
                ("tarazed", "altair"),
                ("altair", "alshain")
            ),
            anchorStarIds: ["altair"]
        ),
        Constellation(
            id: "scorpius",
            name: "Scorpius",
            summary: "The Scorpion — a striking summer constellation with the red supergiant Antares at its heart.",
            lines: line(
                ("antares", "shaula"),
                ("shaula", "sargas")
            ),
            anchorStarIds: ["antares"]
        ),
        Constellation(
            id: "taurus",
            name: "Taurus",
            summary: "The Bull — featuring Aldebaran's red eye and the Pleiades star cluster nearby.",
            lines: line(
                ("aldebaran", "elnath")
            ),
            anchorStarIds: ["aldebaran"]
        ),
        Constellation(
            id: "gemini",
            name: "Gemini",
            summary: "The Twins — Castor and Pollux mark the heads of the two brothers of Greek myth.",
            lines: line(
                ("castor", "pollux"),
                ("pollux", "alhena")
            ),
            anchorStarIds: ["pollux"]
        ),
        Constellation(
            id: "canis-major",
            name: "Canis Major",
            summary: "The Greater Dog — anchored by Sirius, the brightest star in the night sky.",
            lines: line(
                ("sirius", "mirzam"),
                ("sirius", "adhara"),
                ("adhara", "wezen")
            ),
            anchorStarIds: ["sirius"]
        ),
        Constellation(
            id: "crux",
            name: "Crux",
            summary: "The Southern Cross — a compact, iconic constellation of the southern sky.",
            lines: line(
                ("acrux", "gacrux"),
                ("mimosa", "acrux")
            ),
            anchorStarIds: ["acrux"]
        )
    ]

    // MARK: - Helpers

    private static func line(_ pairs: (String, String)...) -> [ConstellationLine] {
        pairs.map { ConstellationLine(starA: $0.0, starB: $0.1) }
    }
}
