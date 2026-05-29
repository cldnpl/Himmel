//
//  ConstellationCatalog.swift
//  Himmel
//
//  All 88 IAU constellations as stick-figures expressed directly in J2000
//  equatorial coordinates (RA in hours, Dec in degrees). Coordinate-based lines
//  (rather than references into `StarCatalog`) let us draw every constellation
//  in real time without needing each asterism star to also be a tappable catalog
//  entry. The view-model resolves these to the observer's horizon each tick.
//
//  Figures follow the conventional "Western / Sky & Telescope" stick patterns.
//  Coordinates are bright-star positions rounded to ~arc-minute precision —
//  ample for naked-eye visual identification.
//

import Foundation

enum ConstellationCatalog {

    // MARK: - Builders

    /// One vertex (RA hours, Dec degrees).
    private static func p(_ ra: Double, _ dec: Double) -> SkyPoint {
        SkyPoint(raHours: ra, decDegrees: dec)
    }

    /// Convenience for a single polyline.
    private static func path(_ pts: SkyPoint...) -> [SkyPoint] { pts }

    static let all: [Constellation] = [

        // ── Andromeda ─────────────────────────────────────────────────────────
        Constellation(
            id: "andromeda", name: "Andromeda",
            summary: "The Chained Princess — a chain of stars stretching from the Great Square of Pegasus, home to the Andromeda Galaxy.",
            paths: [
                path(p(0.139, 29.09), p(0.655, 30.86), p(1.162, 35.62), p(0.946, 38.50), p(0.831, 41.08)),
                path(p(1.162, 35.62), p(2.065, 42.33))
            ]),

        // ── Antlia ──────────────────────────────────────────────────────────────
        Constellation(
            id: "antlia", name: "Antlia",
            summary: "The Air Pump — a faint southern constellation introduced in the 18th century.",
            paths: [path(p(9.487, -35.95), p(10.452, -31.07), p(10.945, -37.14))]),

        // ── Apus ──────────────────────────────────────────────────────────────
        Constellation(
            id: "apus", name: "Apus",
            summary: "The Bird of Paradise — a small, dim constellation near the southern celestial pole.",
            paths: [path(p(14.798, -79.04), p(16.340, -78.70), p(16.718, -77.52), p(16.558, -78.90))]),

        // ── Aquarius ────────────────────────────────────────────────────────────
        Constellation(
            id: "aquarius", name: "Aquarius",
            summary: "The Water Bearer — an ancient zodiac constellation pouring a stream of stars toward the southern fish.",
            paths: [
                path(p(21.526, -5.57), p(22.096, -0.32), p(22.361, -1.39), p(22.481, -0.02), p(22.591, -0.12)),
                path(p(22.096, -0.32), p(22.876, -7.58), p(22.911, -15.82))
            ]),

        // ── Aquila ────────────────────────────────────────────────────────────
        Constellation(
            id: "aquila", name: "Aquila",
            summary: "The Eagle — flying along the Milky Way, marked by brilliant Altair in the Summer Triangle.",
            paths: [
                path(p(19.090, 13.86), p(19.771, 10.61), p(19.846, 8.87), p(19.922, 6.41)),
                path(p(19.771, 10.61), p(19.425, 3.12), p(19.100, -4.88)),
                path(p(19.846, 8.87), p(20.188, -0.82))
            ]),

        // ── Ara ─────────────────────────────────────────────────────────────────
        Constellation(
            id: "ara", name: "Ara",
            summary: "The Altar — a southern constellation set among the rich star clouds below Scorpius.",
            paths: [
                path(p(17.531, -49.88), p(17.421, -55.53), p(17.420, -56.38), p(17.510, -60.68)),
                path(p(17.421, -55.53), p(16.977, -55.99), p(16.990, -53.16))
            ]),

        // ── Aries ───────────────────────────────────────────────────────────────
        Constellation(
            id: "aries", name: "Aries",
            summary: "The Ram — first constellation of the zodiac, a simple bent line of stars.",
            paths: [path(p(1.892, 19.29), p(1.911, 20.81), p(2.119, 23.46), p(2.832, 27.26))]),

        // ── Auriga ────────────────────────────────────────────────────────────
        Constellation(
            id: "auriga", name: "Auriga",
            summary: "The Charioteer — a bright pentagon high in winter skies, anchored by golden Capella.",
            paths: [path(
                p(5.278, 46.00), p(5.992, 44.95), p(5.995, 37.21),
                p(5.438, 28.61), p(4.950, 33.17), p(5.033, 43.82), p(5.278, 46.00))]),

        // ── Boötes ────────────────────────────────────────────────────────────
        Constellation(
            id: "bootes", name: "Boötes",
            summary: "The Herdsman — a kite-shaped figure crowned by Arcturus, the brightest star of the northern sky.",
            paths: [
                path(p(13.911, 18.40), p(14.261, 19.18), p(14.749, 27.07), p(15.032, 40.39), p(14.531, 38.31), p(14.687, 30.37), p(14.261, 19.18))
            ]),

        // ── Caelum ──────────────────────────────────────────────────────────────
        Constellation(
            id: "caelum", name: "Caelum",
            summary: "The Chisel — one of the faintest constellations, a short thread of dim southern stars.",
            paths: [path(p(4.510, -44.95), p(4.676, -41.86), p(4.700, -37.14), p(5.070, -35.48))]),

        // ── Camelopardalis ──────────────────────────────────────────────────────
        Constellation(
            id: "camelopardalis", name: "Camelopardalis",
            summary: "The Giraffe — a large but faint circumpolar constellation between the bears and Perseus.",
            paths: [path(p(3.839, 71.33), p(4.901, 66.34), p(5.057, 60.44))]),

        // ── Cancer ────────────────────────────────────────────────────────────
        Constellation(
            id: "cancer", name: "Cancer",
            summary: "The Crab — a dim zodiac constellation holding the Beehive star cluster at its heart.",
            paths: [
                path(p(8.275, 9.19), p(8.745, 18.15), p(8.721, 21.47), p(8.778, 28.76)),
                path(p(8.745, 18.15), p(8.974, 11.86))
            ]),

        // ── Canes Venatici ──────────────────────────────────────────────────────
        Constellation(
            id: "canes-venatici", name: "Canes Venatici",
            summary: "The Hunting Dogs — two stars below the Big Dipper's handle, led by Cor Caroli.",
            paths: [path(p(12.934, 38.32), p(12.563, 41.36))]),

        // ── Canis Major ─────────────────────────────────────────────────────────
        Constellation(
            id: "canis-major", name: "Canis Major",
            summary: "The Greater Dog — anchored by Sirius, the brightest star in the night sky.",
            paths: [
                path(p(6.378, -17.96), p(6.752, -16.72)),
                path(p(6.752, -16.72), p(7.140, -26.39), p(6.977, -28.97), p(6.339, -30.06)),
                path(p(7.140, -26.39), p(7.402, -29.30))
            ]),

        // ── Canis Minor ─────────────────────────────────────────────────────────
        Constellation(
            id: "canis-minor", name: "Canis Minor",
            summary: "The Lesser Dog — just two stars, dominated by brilliant Procyon.",
            paths: [path(p(7.453, 8.29), p(7.655, 5.22))]),

        // ── Capricornus ─────────────────────────────────────────────────────────
        Constellation(
            id: "capricornus", name: "Capricornus",
            summary: "The Sea Goat — a wide triangular zodiac constellation of autumn evenings.",
            paths: [path(
                p(20.301, -12.51), p(20.351, -14.78), p(20.864, -26.92),
                p(21.444, -22.41), p(21.784, -16.13), p(21.668, -16.66), p(20.301, -12.51))]),

        // ── Carina ────────────────────────────────────────────────────────────
        Constellation(
            id: "carina", name: "Carina",
            summary: "The Keel of the ship Argo — home to Canopus, the second-brightest star in the sky.",
            paths: [
                path(p(6.399, -52.70), p(8.375, -59.51), p(9.285, -59.28)),
                path(p(8.375, -59.51), p(9.220, -69.72), p(10.715, -64.39), p(9.285, -59.28))
            ]),

        // ── Cassiopeia ──────────────────────────────────────────────────────────
        Constellation(
            id: "cassiopeia", name: "Cassiopeia",
            summary: "The Queen — a circumpolar constellation forming a distinctive W in the northern sky.",
            paths: [path(p(0.153, 59.15), p(0.675, 56.54), p(0.945, 60.72), p(1.430, 60.24), p(1.907, 63.67))]),

        // ── Centaurus ───────────────────────────────────────────────────────────
        Constellation(
            id: "centaurus", name: "Centaurus",
            summary: "The Centaur — a grand southern constellation whose feet point toward the Southern Cross.",
            paths: [
                path(p(14.660, -60.84), p(14.064, -60.37), p(13.665, -53.47), p(13.926, -47.29), p(14.111, -36.37)),
                path(p(13.665, -53.47), p(12.692, -48.96), p(12.139, -50.72)),
                path(p(13.926, -47.29), p(14.590, -42.16))
            ]),

        // ── Cepheus ───────────────────────────────────────────────────────────
        Constellation(
            id: "cepheus", name: "Cepheus",
            summary: "The King — a circumpolar house-shaped figure beside Cassiopeia.",
            paths: [
                path(p(21.309, 62.59), p(21.477, 70.56), p(23.656, 77.63), p(22.828, 66.20), p(21.309, 62.59)),
                path(p(22.828, 66.20), p(22.181, 58.20), p(22.476, 58.42))
            ]),

        // ── Cetus ─────────────────────────────────────────────────────────────
        Constellation(
            id: "cetus", name: "Cetus",
            summary: "The Whale (or Sea Monster) — a sprawling constellation hosting the famous variable star Mira.",
            paths: [
                path(p(3.038, 4.09), p(2.722, 3.24), p(2.657, 0.33), p(2.322, -2.98), p(1.857, -10.34)),
                path(p(1.857, -10.34), p(1.734, -15.94), p(1.400, -8.18), p(1.143, -10.18), p(0.323, -8.82), p(0.726, -17.99), p(1.734, -15.94))
            ]),

        // ── Chamaeleon ──────────────────────────────────────────────────────────
        Constellation(
            id: "chamaeleon", name: "Chamaeleon",
            summary: "The Chameleon — a small, faint constellation hugging the south celestial pole.",
            paths: [
                path(p(8.308, -76.92), p(10.590, -78.61), p(12.305, -79.31)),
                path(p(10.590, -78.61), p(10.760, -80.54))
            ]),

        // ── Circinus ────────────────────────────────────────────────────────────
        Constellation(
            id: "circinus", name: "Circinus",
            summary: "The Compasses — a tiny southern constellation beside Alpha Centauri.",
            paths: [path(p(15.290, -58.80), p(14.708, -64.97), p(15.390, -59.32))]),

        // ── Columba ───────────────────────────────────────────────────────────
        Constellation(
            id: "columba", name: "Columba",
            summary: "The Dove — a modest constellation just south of Lepus and Canis Major.",
            paths: [path(p(5.515, -35.47), p(5.661, -34.07), p(5.849, -35.77), p(5.960, -35.28), p(6.370, -33.44))]),

        // ── Coma Berenices ────────────────────────────────────────────────────
        Constellation(
            id: "coma-berenices", name: "Coma Berenices",
            summary: "Berenice's Hair — a faint scattering of stars and galaxies between Leo and Boötes.",
            paths: [path(p(13.166, 17.53), p(13.198, 27.88), p(12.450, 28.27))]),

        // ── Corona Australis ──────────────────────────────────────────────────
        Constellation(
            id: "corona-australis", name: "Corona Australis",
            summary: "The Southern Crown — a graceful arc of stars below Sagittarius.",
            paths: [path(p(19.110, -37.06), p(19.158, -37.90), p(19.167, -39.34), p(19.270, -40.50))]),

        // ── Corona Borealis ───────────────────────────────────────────────────
        Constellation(
            id: "corona-borealis", name: "Corona Borealis",
            summary: "The Northern Crown — a delicate semicircle of stars set with the jewel Alphecca.",
            paths: [path(p(15.550, 31.36), p(15.464, 29.11), p(15.578, 26.71), p(15.710, 26.30), p(15.820, 26.07), p(15.960, 26.88), p(16.020, 29.85))]),

        // ── Corvus ────────────────────────────────────────────────────────────
        Constellation(
            id: "corvus", name: "Corvus",
            summary: "The Crow — a compact quadrilateral riding on the back of Hydra.",
            paths: [
                path(p(12.263, -17.54), p(12.498, -16.52), p(12.574, -23.40), p(12.168, -22.62), p(12.263, -17.54)),
                path(p(12.168, -22.62), p(12.139, -24.73))
            ]),

        // ── Crater ────────────────────────────────────────────────────────────
        Constellation(
            id: "crater", name: "Crater",
            summary: "The Cup — a faint goblet of stars resting on Hydra's coils.",
            paths: [
                path(p(10.996, -18.30), p(11.413, -17.68), p(11.322, -14.78), p(11.450, -10.86), p(11.620, -9.80)),
                path(p(10.996, -18.30), p(11.196, -22.83))
            ]),

        // ── Crux ──────────────────────────────────────────────────────────────
        Constellation(
            id: "crux", name: "Crux",
            summary: "The Southern Cross — the smallest constellation, an iconic emblem of the southern sky.",
            paths: [
                path(p(12.443, -63.10), p(12.520, -57.11)),
                path(p(12.795, -59.69), p(12.252, -58.75))
            ]),

        // ── Cygnus ────────────────────────────────────────────────────────────
        Constellation(
            id: "cygnus", name: "Cygnus",
            summary: "The Swan — also the Northern Cross, gliding down the Milky Way led by Deneb.",
            paths: [
                path(p(20.690, 45.28), p(20.371, 40.26), p(19.512, 27.96)),
                path(p(20.770, 33.97), p(20.371, 40.26), p(19.749, 45.13))
            ]),

        // ── Delphinus ───────────────────────────────────────────────────────────
        Constellation(
            id: "delphinus", name: "Delphinus",
            summary: "The Dolphin — a charming little diamond of stars leaping near Aquila.",
            paths: [
                path(p(20.661, 15.91), p(20.776, 16.12), p(20.726, 15.07), p(20.625, 14.60), p(20.661, 15.91)),
                path(p(20.625, 14.60), p(20.553, 11.30))
            ]),

        // ── Dorado ────────────────────────────────────────────────────────────
        Constellation(
            id: "dorado", name: "Dorado",
            summary: "The Swordfish — a southern constellation holding most of the Large Magellanic Cloud.",
            paths: [path(p(4.270, -51.49), p(4.567, -55.04), p(5.575, -62.49), p(5.745, -65.74))]),

        // ── Draco ─────────────────────────────────────────────────────────────
        Constellation(
            id: "draco", name: "Draco",
            summary: "The Dragon — a long winding constellation coiling between the Big and Little Dippers.",
            paths: [
                path(p(17.943, 51.49), p(17.507, 52.30), p(17.689, 55.18), p(17.892, 56.87), p(17.943, 51.49)),
                path(p(17.892, 56.87), p(19.209, 67.66), p(19.799, 70.27)),
                path(p(17.943, 51.49), p(17.146, 65.71), p(16.400, 61.51), p(16.036, 58.57), p(15.415, 58.97), p(14.073, 64.38), p(12.558, 69.79), p(11.236, 69.33))
            ]),

        // ── Equuleus ────────────────────────────────────────────────────────────
        Constellation(
            id: "equuleus", name: "Equuleus",
            summary: "The Little Horse — the second-smallest constellation, a faint trio beside Pegasus.",
            paths: [path(p(21.370, 6.81), p(21.264, 5.25), p(21.240, 10.01), p(21.170, 10.13))]),

        // ── Eridanus ────────────────────────────────────────────────────────────
        Constellation(
            id: "eridanus", name: "Eridanus",
            summary: "The River — a long meandering stream of stars flowing from Orion's foot to brilliant Achernar.",
            paths: [path(
                p(5.131, -5.09), p(4.598, -5.45), p(4.254, -7.65), p(3.967, -13.51),
                p(3.721, -9.76), p(3.549, -9.46), p(2.940, -8.90), p(3.345, -21.76),
                p(2.971, -40.30), p(1.629, -57.24))]),

        // ── Fornax ────────────────────────────────────────────────────────────
        Constellation(
            id: "fornax", name: "Fornax",
            summary: "The Furnace — a faint southern constellation enclosed by the bends of Eridanus.",
            paths: [path(p(2.070, -29.30), p(3.201, -28.99), p(2.820, -32.41))]),

        // ── Gemini ────────────────────────────────────────────────────────────
        Constellation(
            id: "gemini", name: "Gemini",
            summary: "The Twins — Castor and Pollux mark the heads of two figures striding the winter Milky Way.",
            paths: [
                path(p(7.577, 31.89), p(7.187, 30.25), p(6.732, 25.13), p(6.383, 22.51), p(6.249, 22.51)),
                path(p(7.755, 28.03), p(7.601, 26.90), p(7.335, 21.98), p(7.068, 20.57), p(6.628, 16.40)),
                path(p(7.335, 21.98), p(7.301, 16.54), p(6.755, 12.90)),
                path(p(7.577, 31.89), p(7.755, 28.03))
            ]),

        // ── Grus ──────────────────────────────────────────────────────────────
        Constellation(
            id: "grus", name: "Grus",
            summary: "The Crane — a graceful southern bird flying below Piscis Austrinus.",
            paths: [
                path(p(21.899, -37.36), p(22.487, -43.50), p(22.711, -46.88), p(22.806, -51.32), p(23.170, -52.75)),
                path(p(22.137, -46.96), p(22.711, -46.88)),
                path(p(22.137, -46.96), p(22.487, -43.50))
            ]),

        // ── Hercules ────────────────────────────────────────────────────────────
        Constellation(
            id: "hercules", name: "Hercules",
            summary: "The Strongman — a large constellation whose central Keystone hosts the brilliant globular cluster M13.",
            paths: [
                path(p(16.688, 31.60), p(16.715, 38.92), p(17.251, 36.81), p(17.005, 30.93), p(16.688, 31.60)),
                path(p(17.005, 30.93), p(17.250, 24.84), p(17.244, 14.39)),
                path(p(16.688, 31.60), p(16.504, 21.49), p(16.366, 19.15)),
                path(p(16.715, 38.92), p(16.340, 42.44), p(16.327, 46.31))
            ]),

        // ── Horologium ──────────────────────────────────────────────────────────
        Constellation(
            id: "horologium", name: "Horologium",
            summary: "The Pendulum Clock — a long, faint southern constellation beside Eridanus.",
            paths: [path(p(2.710, -50.80), p(4.234, -42.29))]),

        // ── Hydra ─────────────────────────────────────────────────────────────
        Constellation(
            id: "hydra", name: "Hydra",
            summary: "The Water Snake — the largest constellation of all, winding a quarter of the way around the sky.",
            paths: [
                path(p(8.622, 5.70), p(8.778, 6.42), p(8.920, 5.95), p(8.720, 3.40), p(8.644, 3.34), p(8.622, 5.70)),
                path(p(8.920, 5.95), p(9.460, -8.66), p(10.180, -12.35), p(10.430, -16.84), p(10.826, -16.19), p(13.315, -23.17), p(14.057, -26.68))
            ]),

        // ── Hydrus ────────────────────────────────────────────────────────────
        Constellation(
            id: "hydrus", name: "Hydrus",
            summary: "The Lesser Water Snake — a southern triangle threaded between the Magellanic Clouds.",
            paths: [path(p(0.430, -77.25), p(1.980, -61.57), p(3.790, -74.24), p(0.430, -77.25))]),

        // ── Indus ─────────────────────────────────────────────────────────────
        Constellation(
            id: "indus", name: "Indus",
            summary: "The Indian — a faint far-southern constellation introduced by 16th-century navigators.",
            paths: [path(p(20.626, -47.29), p(21.330, -53.45), p(20.910, -58.45))]),

        // ── Lacerta ───────────────────────────────────────────────────────────
        Constellation(
            id: "lacerta", name: "Lacerta",
            summary: "The Lizard — a small zigzag of faint stars wedged between Cygnus and Andromeda.",
            paths: [path(p(22.391, 52.23), p(22.521, 50.28), p(22.400, 49.48))]),

        // ── Leo ───────────────────────────────────────────────────────────────
        Constellation(
            id: "leo", name: "Leo",
            summary: "The Lion — its head forms the Sickle, a backwards question mark led by bright Regulus.",
            paths: [
                path(p(9.764, 23.77), p(9.879, 26.01), p(10.278, 23.42), p(10.333, 19.84), p(10.122, 16.76), p(10.139, 11.97)),
                path(p(10.139, 11.97), p(11.237, 15.43), p(11.235, 20.52), p(10.333, 19.84)),
                path(p(11.237, 15.43), p(11.818, 14.57), p(11.235, 20.52))
            ]),

        // ── Leo Minor ─────────────────────────────────────────────────────────
        Constellation(
            id: "leo-minor", name: "Leo Minor",
            summary: "The Lesser Lion — a small, dim constellation tucked above Leo's back.",
            paths: [path(p(10.120, 35.24), p(10.460, 36.71), p(10.880, 34.22))]),

        // ── Lepus ─────────────────────────────────────────────────────────────
        Constellation(
            id: "lepus", name: "Lepus",
            summary: "The Hare — crouching beneath the feet of Orion the Hunter.",
            paths: [
                path(p(5.092, -22.37), p(5.471, -20.76), p(5.545, -17.82), p(5.213, -16.21)),
                path(p(5.471, -20.76), p(5.744, -22.45), p(5.856, -20.88)),
                path(p(5.545, -17.82), p(5.783, -14.82), p(5.943, -14.17))
            ]),

        // ── Libra ─────────────────────────────────────────────────────────────
        Constellation(
            id: "libra", name: "Libra",
            summary: "The Scales — the only zodiac constellation representing an object, once the claws of Scorpius.",
            paths: [
                path(p(14.848, -16.04), p(15.283, -9.38), p(15.586, -14.79), p(14.848, -16.04)),
                path(p(14.848, -16.04), p(15.067, -25.28))
            ]),

        // ── Lupus ─────────────────────────────────────────────────────────────
        Constellation(
            id: "lupus", name: "Lupus",
            summary: "The Wolf — a rich southern constellation set in the Milky Way beside Centaurus.",
            paths: [
                path(p(14.699, -47.39), p(14.973, -43.13), p(15.356, -40.65), p(15.585, -41.17), p(16.000, -38.40)),
                path(p(14.973, -43.13), p(15.380, -44.69), p(15.197, -52.10))
            ]),

        // ── Lynx ──────────────────────────────────────────────────────────────
        Constellation(
            id: "lynx", name: "Lynx",
            summary: "The Lynx — a faint zigzag said to require the eyes of a lynx to trace.",
            paths: [path(p(9.351, 34.39), p(9.310, 36.80), p(8.390, 43.19), p(7.440, 49.21), p(6.950, 58.42), p(6.320, 59.01))]),

        // ── Lyra ──────────────────────────────────────────────────────────────
        Constellation(
            id: "lyra", name: "Lyra",
            summary: "The Lyre — a small constellation crowned by Vega, a corner of the Summer Triangle.",
            paths: [
                path(p(18.616, 38.78), p(18.745, 39.61)),
                path(p(18.616, 38.78), p(18.746, 37.60), p(18.835, 33.36), p(18.983, 32.69), p(18.909, 36.90), p(18.746, 37.60))
            ]),

        // ── Mensa ─────────────────────────────────────────────────────────────
        Constellation(
            id: "mensa", name: "Mensa",
            summary: "Table Mountain — the faintest constellation, lying beneath the Large Magellanic Cloud.",
            paths: [path(p(5.530, -76.34), p(6.170, -74.75))]),

        // ── Microscopium ──────────────────────────────────────────────────────
        Constellation(
            id: "microscopium", name: "Microscopium",
            summary: "The Microscope — a dim southern constellation below Capricornus.",
            paths: [
                path(p(20.830, -33.78), p(21.020, -32.26), p(21.290, -32.18))
            ]),

        // ── Monoceros ───────────────────────────────────────────────────────────
        Constellation(
            id: "monoceros", name: "Monoceros",
            summary: "The Unicorn — a faint constellation crossing the Milky Way inside the Winter Triangle.",
            paths: [
                path(p(6.248, -6.27), p(6.483, -7.03), p(7.198, -0.49), p(7.685, -9.55), p(8.058, -2.98)),
                path(p(7.198, -0.49), p(6.398, 4.59))
            ]),

        // ── Musca ─────────────────────────────────────────────────────────────
        Constellation(
            id: "musca", name: "Musca",
            summary: "The Fly — a small southern constellation just below the Southern Cross.",
            paths: [
                path(p(11.762, -66.73), p(12.292, -67.96), p(12.620, -69.14), p(12.543, -72.13)),
                path(p(12.620, -69.14), p(12.771, -68.11), p(13.029, -71.55))
            ]),

        // ── Norma ─────────────────────────────────────────────────────────────
        Constellation(
            id: "norma", name: "Norma",
            summary: "The Carpenter's Square — a faint constellation buried in rich Milky Way star clouds.",
            paths: [path(p(16.060, -49.23), p(16.320, -50.16), p(16.450, -47.55), p(16.100, -45.17))]),

        // ── Octans ────────────────────────────────────────────────────────────
        Constellation(
            id: "octans", name: "Octans",
            summary: "The Octant — the constellation containing the faint south celestial pole star.",
            paths: [path(p(21.690, -77.39), p(22.770, -81.40), p(14.450, -83.67), p(21.690, -77.39))]),

        // ── Ophiuchus ───────────────────────────────────────────────────────────
        Constellation(
            id: "ophiuchus", name: "Ophiuchus",
            summary: "The Serpent Bearer — a huge constellation straddling the celestial equator, the 'thirteenth' zodiac sign.",
            paths: [
                path(p(17.582, 12.56), p(16.961, 9.38), p(16.239, -3.69), p(16.304, -4.69), p(16.620, -10.57), p(17.173, -15.72)),
                path(p(17.582, 12.56), p(17.724, 4.57), p(17.795, 2.71), p(17.173, -15.72)),
                path(p(16.620, -10.57), p(17.363, -25.00))
            ]),

        // ── Orion ─────────────────────────────────────────────────────────────
        Constellation(
            id: "orion", name: "Orion",
            summary: "The Hunter — one of the most recognizable constellations, visible to nearly every observer on Earth.",
            paths: [
                path(p(5.418, 6.35), p(5.919, 7.41)),
                path(p(5.919, 7.41), p(5.679, -1.94)),
                path(p(5.418, 6.35), p(5.534, -0.30)),
                path(p(5.534, -0.30), p(5.604, -1.20), p(5.679, -1.94)),
                path(p(5.679, -1.94), p(5.796, -9.67), p(5.242, -8.20), p(5.534, -0.30)),
                path(p(5.919, 7.41), p(5.585, 9.93), p(5.418, 6.35))
            ]),

        // ── Pavo ──────────────────────────────────────────────────────────────
        Constellation(
            id: "pavo", name: "Pavo",
            summary: "The Peacock — a southern constellation whose brightest star bears the bird's own name.",
            paths: [path(p(20.427, -56.74), p(21.441, -65.37), p(20.749, -66.20), p(20.144, -66.18), p(17.762, -64.72))]),

        // ── Pegasus ───────────────────────────────────────────────────────────
        Constellation(
            id: "pegasus", name: "Pegasus",
            summary: "The Winged Horse — anchored by the Great Square, a signpost of the autumn sky.",
            paths: [
                path(p(23.080, 15.21), p(23.063, 28.08), p(0.139, 29.09), p(0.221, 15.18), p(23.080, 15.21)),
                path(p(23.080, 15.21), p(22.691, 10.83), p(22.173, 6.20), p(21.736, 9.88)),
                path(p(23.063, 28.08), p(22.717, 30.22))
            ]),

        // ── Perseus ───────────────────────────────────────────────────────────
        Constellation(
            id: "perseus", name: "Perseus",
            summary: "The Hero — a Milky Way constellation holding the Double Cluster and the demon star Algol.",
            paths: [
                path(p(2.845, 55.90), p(3.080, 53.51), p(3.405, 49.86), p(3.715, 47.79), p(3.964, 40.01), p(3.902, 31.88)),
                path(p(3.405, 49.86), p(3.136, 40.96), p(3.085, 38.84)),
                path(p(3.136, 40.96), p(3.964, 40.01))
            ]),

        // ── Phoenix ───────────────────────────────────────────────────────────
        Constellation(
            id: "phoenix", name: "Phoenix",
            summary: "The Phoenix — a southern constellation of the rising firebird, near Achernar.",
            paths: [
                path(p(0.157, -45.75), p(0.438, -42.31), p(1.101, -46.72), p(1.473, -43.32)),
                path(p(1.101, -46.72), p(1.410, -49.07), p(1.139, -55.25))
            ]),

        // ── Pictor ────────────────────────────────────────────────────────────
        Constellation(
            id: "pictor", name: "Pictor",
            summary: "The Painter's Easel — a faint southern constellation beside brilliant Canopus.",
            paths: [path(p(5.788, -51.07), p(5.831, -56.17), p(6.803, -61.94))]),

        // ── Pisces ────────────────────────────────────────────────────────────
        Constellation(
            id: "pisces", name: "Pisces",
            summary: "The Fishes — two fish tied by a cord meeting at the star Alrescha.",
            paths: [
                path(p(2.034, 2.76), p(1.756, 9.16), p(1.524, 15.35)),
                path(p(2.034, 2.76), p(1.683, 5.49), p(1.504, 6.14), p(0.978, 7.89), p(0.811, 7.59), p(23.984, 6.86), p(23.286, 3.28)),
                path(p(23.286, 3.28), p(23.466, 6.38), p(23.661, 5.63), p(23.687, 1.78), p(23.444, 1.25), p(23.286, 3.28))
            ]),

        // ── Piscis Austrinus ──────────────────────────────────────────────────
        Constellation(
            id: "piscis-austrinus", name: "Piscis Austrinus",
            summary: "The Southern Fish — drinking the stream from Aquarius, marked by lonely Fomalhaut.",
            paths: [path(
                p(22.961, -29.62), p(22.677, -27.04), p(22.139, -32.99), p(21.745, -33.03),
                p(22.526, -32.35), p(22.879, -32.88), p(22.934, -32.54), p(22.961, -29.62))]),

        // ── Puppis ────────────────────────────────────────────────────────────
        Constellation(
            id: "puppis", name: "Puppis",
            summary: "The Stern of the ship Argo — a rich Milky Way constellation south of Canis Major.",
            paths: [path(
                p(6.808, -50.61), p(7.487, -43.30), p(8.060, -40.00), p(8.126, -24.30),
                p(7.817, -24.86), p(7.286, -37.10), p(7.487, -43.30))]),

        // ── Pyxis ─────────────────────────────────────────────────────────────
        Constellation(
            id: "pyxis", name: "Pyxis",
            summary: "The Mariner's Compass — a small faint constellation along the old ship Argo.",
            paths: [path(p(8.670, -35.31), p(8.726, -33.19), p(8.840, -27.71))]),

        // ── Reticulum ───────────────────────────────────────────────────────────
        Constellation(
            id: "reticulum", name: "Reticulum",
            summary: "The Reticle — a small southern diamond named for an eyepiece crosshair.",
            paths: [path(p(3.740, -64.81), p(4.240, -62.47), p(4.270, -59.30), p(3.970, -61.40), p(3.740, -64.81))]),

        // ── Sagitta ─────────────────────────────────────────────────────────────
        Constellation(
            id: "sagitta", name: "Sagitta",
            summary: "The Arrow — the third-smallest constellation, flying through the Summer Triangle.",
            paths: [
                path(p(19.668, 18.01), p(19.790, 18.53), p(19.979, 19.49)),
                path(p(19.685, 17.48), p(19.790, 18.53))
            ]),

        // ── Sagittarius ─────────────────────────────────────────────────────────
        Constellation(
            id: "sagittarius", name: "Sagittarius",
            summary: "The Archer — its bright stars form the Teapot, aimed at the heart of the Milky Way.",
            paths: [
                path(p(18.097, -30.42), p(18.350, -29.83), p(18.403, -34.38)),
                path(p(18.350, -29.83), p(18.466, -25.42), p(18.741, -26.99), p(19.044, -29.88)),
                path(p(18.466, -25.42), p(18.921, -26.30), p(19.115, -27.67), p(19.044, -29.88), p(18.741, -26.99))
            ]),

        // ── Scorpius ────────────────────────────────────────────────────────────
        Constellation(
            id: "scorpius", name: "Scorpius",
            summary: "The Scorpion — a brilliant summer constellation with red Antares at its heart and a long curving tail.",
            paths: [
                path(p(16.198, -19.46), p(16.090, -19.81), p(16.005, -22.62), p(15.981, -26.11)),
                path(p(16.090, -19.81), p(16.005, -22.62), p(16.353, -25.59), p(16.490, -26.43), p(16.598, -28.22), p(16.836, -34.29), p(16.864, -38.05), p(16.909, -42.36), p(17.204, -43.24), p(17.622, -43.00), p(17.793, -40.13), p(17.708, -39.03), p(17.560, -37.10), p(17.512, -37.30))
            ]),

        // ── Sculptor ──────────────────────────────────────────────────────────
        Constellation(
            id: "sculptor", name: "Sculptor",
            summary: "The Sculptor's Studio — a faint constellation hosting the south galactic pole.",
            paths: [path(p(0.977, -29.36), p(23.810, -28.13), p(23.310, -32.53), p(23.820, -37.82))]),

        // ── Scutum ────────────────────────────────────────────────────────────
        Constellation(
            id: "scutum", name: "Scutum",
            summary: "The Shield — a small constellation set in one of the Milky Way's brightest star clouds.",
            paths: [
                path(p(18.790, -4.75), p(18.586, -8.24), p(18.710, -9.05)),
                path(p(18.586, -8.24), p(18.480, -14.57))
            ]),

        // ── Serpens ───────────────────────────────────────────────────────────
        Constellation(
            id: "serpens", name: "Serpens",
            summary: "The Serpent — the only constellation split in two, held by Ophiuchus across the sky.",
            paths: [
                path(p(15.857, 19.67), p(15.810, 18.14), p(15.770, 15.42), p(15.580, 10.54), p(15.738, 6.43), p(15.845, 4.48), p(15.827, -3.43)),
                path(p(17.348, -12.85), p(17.625, -15.40), p(18.355, -2.90), p(18.939, 4.20))
            ]),

        // ── Sextans ───────────────────────────────────────────────────────────
        Constellation(
            id: "sextans", name: "Sextans",
            summary: "The Sextant — a faint equatorial constellation just south of Leo's Regulus.",
            paths: [path(p(9.870, -8.10), p(10.132, -0.37), p(10.490, -2.74), p(10.500, -0.64))]),

        // ── Taurus ────────────────────────────────────────────────────────────
        Constellation(
            id: "taurus", name: "Taurus",
            summary: "The Bull — featuring the red eye Aldebaran, the V-shaped Hyades and the Pleiades cluster.",
            paths: [
                path(p(5.627, 21.14), p(4.598, 16.51), p(4.477, 19.18), p(5.438, 28.61)),
                path(p(4.598, 16.51), p(4.330, 15.63), p(4.382, 17.54), p(4.477, 19.18))
            ]),

        // ── Telescopium ─────────────────────────────────────────────────────────
        Constellation(
            id: "telescopium", name: "Telescopium",
            summary: "The Telescope — a faint southern constellation below Corona Australis.",
            paths: [path(p(18.180, -45.95), p(18.449, -45.97), p(18.500, -49.07))]),

        // ── Triangulum ──────────────────────────────────────────────────────────
        Constellation(
            id: "triangulum", name: "Triangulum",
            summary: "The Triangle — a slim northern triangle near Andromeda, home to the Triangulum Galaxy.",
            paths: [path(p(1.885, 29.58), p(2.159, 34.99), p(2.289, 33.85), p(1.885, 29.58))]),

        // ── Triangulum Australe ──────────────────────────────────────────────────
        Constellation(
            id: "triangulum-australe", name: "Triangulum Australe",
            summary: "The Southern Triangle — a bright, near-equilateral triangle below Alpha Centauri.",
            paths: [path(p(16.811, -69.03), p(15.920, -63.43), p(15.315, -68.68), p(16.811, -69.03))]),

        // ── Tucana ────────────────────────────────────────────────────────────
        Constellation(
            id: "tucana", name: "Tucana",
            summary: "The Toucan — a southern constellation containing the Small Magellanic Cloud and cluster 47 Tucanae.",
            paths: [path(p(22.308, -60.26), p(23.288, -58.24), p(0.525, -62.96), p(0.330, -64.88))]),

        // ── Ursa Major ──────────────────────────────────────────────────────────
        Constellation(
            id: "ursa-major", name: "Ursa Major",
            summary: "The Great Bear, containing the iconic Big Dipper — visible all year from mid-northern latitudes.",
            paths: [path(
                p(13.793, 49.31), p(13.399, 54.93), p(12.900, 55.96), p(12.257, 57.03),
                p(11.897, 53.69), p(11.031, 56.38), p(11.062, 61.75), p(12.257, 57.03))]),

        // ── Ursa Minor ──────────────────────────────────────────────────────────
        Constellation(
            id: "ursa-minor", name: "Ursa Minor",
            summary: "The Little Bear, anchored by Polaris at the tip of the Little Dipper's handle.",
            paths: [path(
                p(2.530, 89.26), p(17.537, 86.59), p(16.766, 82.04), p(15.734, 77.79),
                p(16.292, 75.76), p(14.845, 74.16), p(15.346, 71.83), p(15.734, 77.79))]),

        // ── Vela ──────────────────────────────────────────────────────────────
        Constellation(
            id: "vela", name: "Vela",
            summary: "The Sails of the ship Argo — a bright southern constellation forming half of the False Cross.",
            paths: [
                path(p(8.158, -47.34), p(8.745, -54.71), p(9.368, -55.01), p(9.133, -43.43), p(8.158, -47.34)),
                path(p(9.368, -55.01), p(10.778, -49.42)),
                path(p(8.745, -54.71), p(8.671, -52.92))
            ]),

        // ── Virgo ─────────────────────────────────────────────────────────────
        Constellation(
            id: "virgo", name: "Virgo",
            summary: "The Maiden — the second-largest constellation, marked by Spica and rich in galaxies.",
            paths: [
                path(p(13.036, 10.96), p(12.926, 3.40), p(12.694, -1.45), p(12.333, -0.67), p(11.845, 1.76)),
                path(p(12.694, -1.45), p(13.578, -0.60), p(13.420, -11.16))
            ]),

        // ── Volans ────────────────────────────────────────────────────────────
        Constellation(
            id: "volans", name: "Volans",
            summary: "The Flying Fish — a small southern constellation tucked beneath Carina.",
            paths: [
                path(p(7.145, -70.50), p(7.270, -67.96), p(8.130, -68.62), p(9.040, -66.40), p(8.420, -66.13)),
                path(p(8.130, -68.62), p(7.700, -72.61))
            ]),

        // ── Vulpecula ───────────────────────────────────────────────────────────
        Constellation(
            id: "vulpecula", name: "Vulpecula",
            summary: "The Little Fox — a faint constellation in the Summer Triangle, home to the Dumbbell Nebula.",
            paths: [path(p(19.478, 24.66), p(19.881, 24.07))])
    ]
}
