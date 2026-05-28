//
//  StarCatalog.swift
//  Himmel
//
//  Curated catalog of ~120 bright stars (J2000) used by the AR sky.
//  Coordinates are simplified to two decimals and adequate for visual identification
//  in AR at human scale. Magnitudes are apparent visual magnitudes.
//

import Foundation

enum StarCatalog {

    static let stars: [CelestialObject] = [
        // ── Ursa Major / Big Dipper ───────────────────────────────────────────
        star("dubhe",   "Dubhe",   ra: 11.062, dec:  61.751, mag: 1.81, desig: "α UMa",
             subtitle: "Pointer star of the Big Dipper",
             summary: "Orange giant about 123 light-years away. Together with Merak it points toward Polaris."),
        star("merak",   "Merak",   ra: 11.031, dec:  56.382, mag: 2.34, desig: "β UMa",
             subtitle: "Second pointer to Polaris",
             summary: "A white main-sequence star about 79 light-years away, slightly hotter than the Sun."),
        star("phecda",  "Phecda",  ra: 11.897, dec:  53.694, mag: 2.41, desig: "γ UMa",
             subtitle: "Bowl of the Big Dipper",
             summary: "A blue-white star 83 light-years away forming the lower bowl of the asterism."),
        star("megrez",  "Megrez",  ra: 12.257, dec:  57.032, mag: 3.32, desig: "δ UMa",
             subtitle: "Faintest star of the Dipper",
             summary: "Marks the corner where the bowl meets the handle of the Big Dipper."),
        star("alioth",  "Alioth",  ra: 12.900, dec:  55.960, mag: 1.76, desig: "ε UMa",
             subtitle: "Brightest star of Ursa Major",
             summary: "An A-type peculiar star about 81 light-years away with strong magnetic field variability."),
        star("mizar",   "Mizar",   ra: 13.399, dec:  54.925, mag: 2.23, desig: "ζ UMa",
             subtitle: "Famous naked-eye double",
             summary: "Forms a wide visual pair with Alcor — the classic test of unaided eyesight in antiquity."),
        star("alkaid",  "Alkaid",  ra: 13.793, dec:  49.313, mag: 1.85, desig: "η UMa",
             subtitle: "Tip of the Dipper's handle",
             summary: "Hot, young blue main-sequence star about 104 light-years away."),

        // ── Ursa Minor / Little Dipper ────────────────────────────────────────
        star("polaris", "Polaris", ra:  2.530, dec:  89.264, mag: 1.98, desig: "α UMi",
             subtitle: "The North Star",
             summary: "Currently aligned within ~0.7° of the north celestial pole, making it appear nearly stationary."),
        star("kochab",  "Kochab",  ra: 14.845, dec:  74.156, mag: 2.07, desig: "β UMi",
             subtitle: "Guardian of the pole",
             summary: "An orange giant 130 light-years away that, together with Pherkad, traces the Little Dipper's bowl."),
        star("pherkad", "Pherkad", ra: 15.346, dec:  71.834, mag: 3.00, desig: "γ UMi",
             subtitle: "Companion guardian of the pole",
             summary: "A white giant about 487 light-years away."),

        // ── Orion ─────────────────────────────────────────────────────────────
        star("rigel",       "Rigel",       ra:  5.242, dec:  -8.202, mag: 0.13, desig: "β Ori",
             subtitle: "The blue-white giant of Orion",
             summary: "Blue supergiant some 860 light-years away — one of the most luminous stars known to the naked eye."),
        star("betelgeuse",  "Betelgeuse",  ra:  5.919, dec:   7.407, mag: 0.50, desig: "α Ori",
             subtitle: "The red shoulder of Orion",
             summary: "Red supergiant ~550 light-years away that varies noticeably in brightness over months."),
        star("bellatrix",   "Bellatrix",   ra:  5.418, dec:   6.350, mag: 1.64, desig: "γ Ori",
             subtitle: "The Amazon Star",
             summary: "Hot blue giant marking the western shoulder of Orion."),
        star("saiph",       "Saiph",       ra:  5.796, dec:  -9.670, mag: 2.09, desig: "κ Ori",
             subtitle: "Eastern foot of Orion",
             summary: "Blue supergiant whose light has been travelling about 650 years to reach us."),
        star("mintaka",     "Mintaka",     ra:  5.534, dec:  -0.299, mag: 2.25, desig: "δ Ori",
             subtitle: "Western star of Orion's Belt",
             summary: "A complex multiple star system lying almost exactly on the celestial equator."),
        star("alnilam",     "Alnilam",     ra:  5.604, dec:  -1.202, mag: 1.69, desig: "ε Ori",
             subtitle: "Central star of Orion's Belt",
             summary: "Bright blue supergiant about 2,000 light-years away — the most luminous of the three belt stars."),
        star("alnitak",     "Alnitak",     ra:  5.679, dec:  -1.943, mag: 1.79, desig: "ζ Ori",
             subtitle: "Eastern star of Orion's Belt",
             summary: "Triple star illuminating the famous Flame and Horsehead nebulae."),

        // ── Canis Major / Canis Minor ─────────────────────────────────────────
        star("sirius",  "Sirius",  ra:  6.752, dec: -16.716, mag: -1.46, desig: "α CMa",
             subtitle: "The brightest star in Earth's night sky",
             summary: "A nearby A-type main-sequence star only 8.6 light-years away — visible from almost every inhabited place on Earth."),
        star("adhara",  "Adhara",  ra:  6.977, dec: -28.972, mag: 1.50, desig: "ε CMa",
             subtitle: "Brightest source of UV in the local sky",
             summary: "A hot blue giant about 430 light-years away."),
        star("wezen",   "Wezen",   ra:  7.140, dec: -26.393, mag: 1.83, desig: "δ CMa",
             subtitle: "Yellow supergiant near Sirius",
             summary: "Far more luminous than Sirius but 200× more distant."),
        star("mirzam",  "Mirzam",  ra:  6.378, dec: -17.956, mag: 1.98, desig: "β CMa",
             subtitle: "The Announcer",
             summary: "Rises shortly before Sirius and gave its name to a class of variable stars."),
        star("procyon", "Procyon", ra:  7.655, dec:   5.225, mag: 0.34, desig: "α CMi",
             subtitle: "The eighth-brightest star in the sky",
             summary: "A nearby F-type subgiant 11.4 light-years away, hosting a white dwarf companion."),
        star("gomeisa", "Gomeisa", ra:  7.453, dec:   8.289, mag: 2.89, desig: "β CMi",
             subtitle: "Companion to Procyon",
             summary: "Blue-white main-sequence star spinning rapidly enough to be flattened at the poles."),

        // ── Taurus ────────────────────────────────────────────────────────────
        star("aldebaran", "Aldebaran", ra:  4.598, dec:  16.509, mag: 0.85, desig: "α Tau",
             subtitle: "The eye of the Bull",
             summary: "Orange giant 65 light-years away. It only appears to belong to the Hyades — it lies far in front of them."),
        star("elnath",    "Elnath",    ra:  5.438, dec:  28.608, mag: 1.65, desig: "β Tau",
             subtitle: "Northern horn of Taurus",
             summary: "Shared historically between Taurus and Auriga as their common boundary star."),

        // ── Gemini ────────────────────────────────────────────────────────────
        star("castor",  "Castor",  ra:  7.577, dec:  31.888, mag: 1.58, desig: "α Gem",
             subtitle: "The mortal twin",
             summary: "Actually a sextuple star system — three pairs of stars locked in a hierarchy."),
        star("pollux",  "Pollux",  ra:  7.755, dec:  28.026, mag: 1.14, desig: "β Gem",
             subtitle: "The immortal twin",
             summary: "Orange giant 34 light-years away, the closest giant star to the Sun and host of an exoplanet."),
        star("alhena",  "Alhena",  ra:  6.628, dec:  16.399, mag: 1.92, desig: "γ Gem",
             subtitle: "Foot of the southern twin",
             summary: "A subgiant about 109 light-years away."),

        // ── Leo ───────────────────────────────────────────────────────────────
        star("regulus",  "Regulus",  ra: 10.139, dec:  11.967, mag: 1.40, desig: "α Leo",
             subtitle: "Heart of the Lion",
             summary: "Hot blue-white main-sequence star spinning so fast its equator bulges visibly."),
        star("denebola", "Denebola", ra: 11.818, dec:  14.572, mag: 2.13, desig: "β Leo",
             subtitle: "Tail of the Lion",
             summary: "Young A-type star surrounded by a dusty debris disk."),
        star("algieba",  "Algieba",  ra: 10.333, dec:  19.842, mag: 2.08, desig: "γ Leo",
             subtitle: "A famous golden double",
             summary: "Two orange giants orbiting each other — one of the sky's most beautiful binary pairs."),
        star("zosma",    "Zosma",    ra: 11.235, dec:  20.524, mag: 2.56, desig: "δ Leo",
             subtitle: "Hip of the Lion",
             summary: "A white main-sequence star 58 light-years away."),

        // ── Boötes ────────────────────────────────────────────────────────────
        star("arcturus", "Arcturus", ra: 14.261, dec:  19.183, mag: -0.05, desig: "α Boo",
             subtitle: "The brightest star of the northern celestial hemisphere",
             summary: "An orange giant 37 light-years away, racing across the sky relative to other stars."),
        star("izar",     "Izar",     ra: 14.749, dec:  27.075, mag: 2.37, desig: "ε Boo",
             subtitle: "Beautiful color-contrast double",
             summary: "Often called 'Pulcherrima' — a striking orange-and-blue pair in a telescope."),

        // ── Virgo ─────────────────────────────────────────────────────────────
        star("spica", "Spica", ra: 13.420, dec: -11.161, mag: 0.97, desig: "α Vir",
             subtitle: "The ear of wheat",
             summary: "A close binary of two hot blue stars whose mutual gravity distorts each other into ellipsoids."),

        // ── Cassiopeia ────────────────────────────────────────────────────────
        star("schedar",   "Schedar",   ra:  0.675, dec:  56.537, mag: 2.24, desig: "α Cas",
             subtitle: "Breast of the Queen",
             summary: "Orange giant marking one corner of Cassiopeia's W-shape."),
        star("caph",      "Caph",      ra:  0.153, dec:  59.150, mag: 2.28, desig: "β Cas",
             subtitle: "Right edge of the W",
             summary: "A subgiant variable star and one of the navigational stars."),
        star("gamma_cas", "Gamma Cas", ra:  0.945, dec:  60.717, mag: 2.47, desig: "γ Cas",
             subtitle: "Center of the W",
             summary: "Eruptive variable star and the prototype of the 'Gamma Cas analogs' class."),
        star("ruchbah",   "Ruchbah",   ra:  1.430, dec:  60.236, mag: 2.66, desig: "δ Cas",
             subtitle: "Knee of the Queen",
             summary: "Eclipsing binary 99 light-years away."),
        star("segin",     "Segin",     ra:  1.907, dec:  63.670, mag: 3.35, desig: "ε Cas",
             subtitle: "Eastern tip of the W",
             summary: "Blue-white giant about 410 light-years away."),

        // ── Cygnus / Lyra / Aquila — Summer Triangle ──────────────────────────
        star("deneb",   "Deneb",   ra: 20.690, dec:  45.280, mag: 1.25, desig: "α Cyg",
             subtitle: "Tail of the Swan",
             summary: "One of the most luminous stars visible to the naked eye, about 2,600 light-years away."),
        star("sadr",    "Sadr",    ra: 20.371, dec:  40.257, mag: 2.23, desig: "γ Cyg",
             subtitle: "Heart of the Swan",
             summary: "Yellow-white supergiant embedded in a rich Milky Way star-forming region."),
        star("gienah_cyg","Gienah", ra: 20.770, dec:  33.970, mag: 2.48, desig: "ε Cyg",
             subtitle: "Wing of the Swan",
             summary: "Orange giant 72 light-years away."),
        star("delta_cyg","Delta Cyg", ra: 19.749, dec: 45.131, mag: 2.87, desig: "δ Cyg",
             subtitle: "Western wing of the Swan",
             summary: "Triple star system that will become a future pole star around the year 11,250."),
        star("albireo", "Albireo", ra: 19.512, dec:  27.960, mag: 3.05, desig: "β Cyg",
             subtitle: "Most beautiful double star",
             summary: "A striking gold-and-blue pair visible in small telescopes."),
        star("vega",    "Vega",    ra: 18.616, dec:  38.784, mag: 0.03, desig: "α Lyr",
             subtitle: "The harp star",
             summary: "Only 25 light-years away. Was the pole star ~12,000 BC and will be again ~13,700 AD."),
        star("sheliak", "Sheliak", ra: 18.835, dec:  33.363, mag: 3.45, desig: "β Lyr",
             subtitle: "Prototype eclipsing binary",
             summary: "Two close stars exchanging mass — they cause variable brightness over 13 days."),
        star("sulafat", "Sulafat", ra: 18.983, dec:  32.690, mag: 3.24, desig: "γ Lyr",
             subtitle: "Tortoise shell",
             summary: "Blue-white giant about 620 light-years distant."),
        star("altair",  "Altair",  ra: 19.846, dec:   8.868, mag: 0.77, desig: "α Aql",
             subtitle: "The flying eagle",
             summary: "One of the nearest naked-eye stars (17 light-years) and so rapidly spinning it is visibly oblate."),
        star("tarazed", "Tarazed", ra: 19.771, dec:  10.613, mag: 2.72, desig: "γ Aql",
             subtitle: "Companion of Altair",
             summary: "Orange giant about 460 light-years away."),
        star("alshain", "Alshain", ra: 19.922, dec:   6.407, mag: 3.71, desig: "β Aql",
             subtitle: "Lower wing of the Eagle",
             summary: "A subgiant about 45 light-years away."),

        // ── Scorpius / Sagittarius ────────────────────────────────────────────
        star("antares", "Antares", ra: 16.490, dec: -26.432, mag: 1.06, desig: "α Sco",
             subtitle: "Rival of Mars",
             summary: "Red supergiant ~550 light-years away — so large it would engulf Mars' orbit if placed at the Sun's location."),
        star("shaula",  "Shaula",  ra: 17.560, dec: -37.104, mag: 1.62, desig: "λ Sco",
             subtitle: "Stinger of the Scorpion",
             summary: "Triple star system at the curl of the Scorpion's tail."),
        star("sargas",  "Sargas",  ra: 17.622, dec: -42.998, mag: 1.86, desig: "θ Sco",
             subtitle: "Yellow giant near the stinger",
             summary: "About 300 light-years away."),
        star("kaus_australis","Kaus Australis", ra: 18.403, dec: -34.385, mag: 1.85, desig: "ε Sgr",
             subtitle: "Bottom of the Teapot",
             summary: "Brightest star of Sagittarius, marking the southern tip of the Archer's bow."),
        star("nunki",   "Nunki",   ra: 18.921, dec: -26.297, mag: 2.05, desig: "σ Sgr",
             subtitle: "Handle of the Teapot",
             summary: "Hot blue main-sequence star with one of the oldest recorded star names — Sumerian."),

        // ── Andromeda / Pegasus — Great Square ────────────────────────────────
        star("alpheratz", "Alpheratz", ra:  0.140, dec:  29.090, mag: 2.06, desig: "α And",
             subtitle: "Shared corner of the Great Square",
             summary: "Historically belonged to both Andromeda and Pegasus; now formally part of Andromeda."),
        star("mirach",    "Mirach",    ra:  1.162, dec:  35.621, mag: 2.05, desig: "β And",
             subtitle: "Belt of Andromeda",
             summary: "Red giant 197 light-years distant, sometimes used as a hop to find the Andromeda Galaxy."),
        star("almach",    "Almach",    ra:  2.065, dec:  42.330, mag: 2.10, desig: "γ And",
             subtitle: "Beautiful color-contrast double",
             summary: "Bright orange giant paired with a hotter blue companion."),
        star("markab",    "Markab",    ra: 23.080, dec:  15.205, mag: 2.49, desig: "α Peg",
             subtitle: "Saddle of Pegasus",
             summary: "One of the four corners of the Great Square of Pegasus."),
        star("scheat",    "Scheat",    ra: 23.063, dec:  28.083, mag: 2.42, desig: "β Peg",
             subtitle: "Shoulder of Pegasus",
             summary: "Red giant that varies subtly in brightness over weeks."),
        star("algenib",   "Algenib",   ra:  0.221, dec:  15.184, mag: 2.83, desig: "γ Peg",
             subtitle: "Wing of Pegasus",
             summary: "Hot blue subgiant about 390 light-years away."),
        star("enif",      "Enif",      ra: 21.736, dec:   9.875, mag: 2.39, desig: "ε Peg",
             subtitle: "Nose of Pegasus",
             summary: "Orange supergiant approximately 690 light-years from Earth."),

        // ── Auriga ────────────────────────────────────────────────────────────
        star("capella",   "Capella",   ra:  5.278, dec:  45.998, mag: 0.08, desig: "α Aur",
             subtitle: "The Goat Star",
             summary: "Actually a system of four stars — two pairs orbiting each other — 42 light-years away."),
        star("menkalinan","Menkalinan",ra:  5.992, dec:  44.948, mag: 1.90, desig: "β Aur",
             subtitle: "Shoulder of the Charioteer",
             summary: "Eclipsing binary varying by ~0.1 magnitudes every 3.96 days."),

        // ── Crux / Centaurus (visible south of ~25°N) ─────────────────────────
        star("acrux",     "Acrux",     ra: 12.443, dec: -63.099, mag: 0.77, desig: "α Cru",
             subtitle: "Foot of the Southern Cross",
             summary: "The southernmost first-magnitude star, a triple system 320 light-years away."),
        star("mimosa",    "Mimosa",    ra: 12.795, dec: -59.689, mag: 1.25, desig: "β Cru",
             subtitle: "Beta Crucis",
             summary: "Hot blue giant pulsating subtly every few hours."),
        star("gacrux",    "Gacrux",    ra: 12.520, dec: -57.113, mag: 1.63, desig: "γ Cru",
             subtitle: "Top of the Southern Cross",
             summary: "Nearby red giant — the closest red giant to the Sun (88 light-years)."),
        star("alpha_cen", "Rigil Kentaurus", ra: 14.660, dec: -60.835, mag: -0.27, desig: "α Cen",
             subtitle: "The closest star system",
             summary: "Triple star system 4.37 light-years away that includes Proxima Centauri."),
        star("hadar",     "Hadar",     ra: 14.064, dec: -60.373, mag: 0.61, desig: "β Cen",
             subtitle: "Pointer to the Southern Cross",
             summary: "Hot blue giant approximately 390 light-years away."),

        // ── Eridanus / Cetus / Piscis Austrinus ───────────────────────────────
        star("achernar",  "Achernar",  ra:  1.629, dec: -57.237, mag: 0.46, desig: "α Eri",
             subtitle: "End of the River",
             summary: "One of the flattest stars known — its equator bulges 50% wider than its poles due to rapid rotation."),
        star("fomalhaut", "Fomalhaut", ra: 22.961, dec: -29.622, mag: 1.16, desig: "α PsA",
             subtitle: "The Lonely Star of Autumn",
             summary: "Surrounded by a debris disk that hosts at least one directly imaged planet candidate."),

        // ── Carina (south) ────────────────────────────────────────────────────
        star("canopus",   "Canopus",   ra:  6.399, dec: -52.696, mag: -0.74, desig: "α Car",
             subtitle: "Second-brightest star in the sky",
             summary: "A yellow-white supergiant 310 light-years away, often used for spacecraft navigation."),

        // ── Hydra / Corvus ────────────────────────────────────────────────────
        star("alphard",   "Alphard",   ra:  9.460, dec:  -8.659, mag: 1.99, desig: "α Hya",
             subtitle: "The Solitary One",
             summary: "Orange giant that appears noticeably alone in its corner of the sky."),
    ]

    // MARK: - Lookup

    private static let byID: [String: CelestialObject] = {
        var dict: [String: CelestialObject] = [:]
        for star in stars { dict[star.id] = star }
        return dict
    }()

    static func star(id: String) -> CelestialObject? { byID[id] }

    // MARK: - Builder helper

    private static func star(
        _ id: String,
        _ name: String,
        ra: Double,
        dec: Double,
        mag: Double,
        desig: String,
        subtitle: String,
        summary: String
    ) -> CelestialObject {
        CelestialObject(
            id: id,
            name: name,
            type: .star,
            equatorial: EquatorialCoordinate(rightAscensionHours: ra, declinationDegrees: dec),
            magnitude: mag,
            designation: desig,
            subtitle: subtitle,
            summary: summary,
            facts: ["Magnitude: \(String(format: "%.2f", mag))", "Designation: \(desig)"]
        )
    }
}
