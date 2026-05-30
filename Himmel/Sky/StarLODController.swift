//
//  StarLODController.swift
//  Himmel
//
//  Dynamic magnitude-based level-of-detail for catalog stars (the "Sky Guide"
//  effect). Maps the virtual camera's current field of view to a maximum visible
//  magnitude, then drives each star sprite's opacity with a smoothstep fade so
//  fainter stars reveal / hide gradually as the user zooms — never popping.
//
//  Deliberately narrow in scope: this is an injected FILTERING layer only.
//    • The pure math (magnitudeLimit, visibility) is the testable core.
//    • apply() takes a per-star `[id: StarLOD]` metadata map supplied by the
//      coordinator — magnitude (raw catalog value) and baseIntensity (the star's
//      full-visibility opacity). We do NOT stash these on SCNNode via arbitrary
//      KVC keys: SCNNode does not guarantee storage for undefined keys.
//    • It writes ONLY node.opacity. It never touches node.isHidden (so it can't
//      fight SkySceneCoordinator.applyHorizonCulling) and never touches the
//      constellation / body / label layers.
//
//  Constellation lines are built from RA/Dec polylines (SkyPoint), not star-ID
//  vertices, so fading a star can never break an asterism — the decoupling the
//  spec asks for already holds by construction.
//

import SceneKit

@MainActor
struct StarLODController {

    /// FOV ↔ magnitude calibration. Tune these, not the algorithm.
    struct Config {
        /// Widest FOV (fully zoomed out) in degrees.
        var wideFOV: Double = 75
        /// Narrowest FOV (fully zoomed in) in degrees.
        var narrowFOV: Double = 12
        /// Magnitude cutoff when zoomed all the way out — only bright anchor stars.
        var magAtWide: Double = 4.5
        /// Magnitude cutoff when zoomed all the way in — faint background revealed.
        var magAtNarrow: Double = 6.5
        /// Half-width, in magnitudes, of the soft fade band around the cutoff.
        /// Larger = gentler reveal, smaller = snappier.
        var fadeBand: Double = 0.8
    }

    var config = Config()

    /// Per-star inputs the fade needs. Built once when a star node is created.
    struct StarLOD {
        /// Raw apparent visual magnitude (lower = brighter).
        let magnitude: Double
        /// Opacity the star should have when fully visible (before the LOD fade).
        /// Lets bright anchors read solid while faint stars stay dimmer even when
        /// shown — independent of the zoom cutoff.
        let baseIntensity: Double
    }

    /// Maps a magnitude to a sensible full-visibility opacity: the naked-eye span
    /// [-1.5, 6.5] → [1.0, 0.45]. Brightest stars are solid; the faintest visible
    /// ones never drop below 0.45 (the zoom cutoff, not this, decides vanishing).
    static func baseIntensity(forMagnitude mag: Double) -> Double {
        let t = (mag + 1.5) / 8.0
        return 1.0 - min(max(t, 0), 1) * 0.55
    }

    // MARK: - Pure math (independently testable, no SceneKit state)

    /// Maximum visible magnitude for a given FOV. Narrower FOV → deeper (higher)
    /// limit. Linear in FOV, clamped to the calibrated endpoints.
    func magnitudeLimit(forFOV fov: Double) -> Double {
        let span = config.wideFOV - config.narrowFOV
        guard span > 0 else { return config.magAtWide }
        let f = min(max(fov, config.narrowFOV), config.wideFOV)
        let t = (f - config.narrowFOV) / span          // 0 at narrow, 1 at wide
        return config.magAtNarrow + t * (config.magAtWide - config.magAtNarrow)
    }

    /// Visibility weight in [0, 1] for a star of `magnitude` under `limit`.
    /// Smoothstep across [limit−band, limit+band] so reveal/hide is gradual.
    func visibility(magnitude: Double, limit: Double) -> Double {
        let lower = limit - config.fadeBand    // brighter edge → fully visible
        let upper = limit + config.fadeBand    // fainter edge  → fully hidden
        if magnitude <= lower { return 1 }
        if magnitude >= upper { return 0 }
        let x = (magnitude - lower) / (upper - lower)   // 0…1 across the band
        let s = x * x * (3 - 2 * x)                      // smoothstep
        return 1 - s
    }

    // MARK: - Application (CPU-side — Approach A)

    /// Re-evaluate opacities for every star node at the current FOV.
    ///
    /// O(n) over the star dictionary; for Himmel's few-hundred sprites this is
    /// well under a millisecond and only runs when the zoom changes or stars
    /// rebuild (gated by the caller), so it never costs a frame.
    func apply(toStarNodes nodes: [String: SCNNode],
               metadata: [String: StarLOD],
               fov: Double) {
        let limit = magnitudeLimit(forFOV: fov)
        for (id, node) in nodes {
            guard let m = metadata[id] else { continue }
            let v = visibility(magnitude: m.magnitude, limit: limit)
            node.opacity = CGFloat(m.baseIntensity * v)   // opacity only — see file header
        }
    }
}
