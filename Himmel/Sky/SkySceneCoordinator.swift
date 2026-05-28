//
//  SkySceneCoordinator.swift
//  Himmel
//
//  Owns the SceneKit scene that renders the virtual celestial sphere.
//  Uses CoreMotion (not ARKit) so the user sees a clean dark sky instead of
//  the camera passthrough. The phone's orientation drives the SCNCamera.
//

import SceneKit
import UIKit
import CoreMotion
import simd

@MainActor
final class SkySceneCoordinator: NSObject, SCNSceneRendererDelegate {

    let scnView: SCNView

    private let scene = SCNScene()

    // ── Scene-graph hierarchy ───────────────────────────────────────────────
    // scene.rootNode
    //   ├─ cameraNode          (carries the global AR rotation from CoreMotion)
    //   ├─ skyDome             (8K Stars+Milky Way background, static)
    //   └─ skyRoot             (static celestial sphere container)
    //        ├─ starsContainer          ← procedural sprite stars (UNCHANGED)
    //        ├─ bodiesContainer         ← Sun (sprite) + planets/Moon (3D models)
    //        └─ constellationsContainer ← asterism lines + names
    //
    // NB: the global "AR rotation" lives on the CAMERA, not the dome — the camera
    // turns while the sphere stays put. This is equivalent to rotating the dome
    // but avoids re-transforming the huge 8K mesh every frame.
    private let skyRoot = SCNNode()
    private let starsContainer = SCNNode()
    private let bodiesContainer = SCNNode()
    private let constellationsContainer = SCNNode()

    /// Accessed from SceneKit's render thread inside `renderer(_:updateAtTime:)`.
    /// Created once in `init` and never reassigned, so unchecked access is safe.
    nonisolated(unsafe) private let cameraNode = SCNNode()
    /// Exposed so the label overlay can project through the exact same camera.
    var cameraNodeForProjection: SCNNode { cameraNode }
    private let motion = MotionService()

    private weak var viewModel: SkyViewModel?
    private var onSelect: ((String) -> Void)?

    private var starNodes: [String: SCNNode] = [:]
    private var bodyNodes: [String: SCNNode] = [:]
    private var constellationNodes: [String: SCNNode] = [:]
    private var selectionHaloNode: SCNNode?
    private let navigationSolver = SkyNavigationSolver()
    private var navigationTargetPositions: [String: SIMD3<Float>] = [:]
    private var lastNavigationGuidance: SkyNavigationGuidance = .inactive
    private var lastNavigationPublishTime: TimeInterval = 0

    /// Screen-space label layer (names projected from 3D, collision-resolved).
    let labelOverlay = SkyLabelOverlayView()

    /// Directional light representing the real Sun; drives planet/Moon phases.
    private var sunLightNode: SCNNode?
    /// Bodies for which an async hero-model load has already been kicked off.
    private var heroModelRequested: Set<String> = []

    private var lastRenderSignature: Int = 0

    override init() {
        self.scnView = SCNView(frame: .zero)
        super.init()
        configureScene()
    }

    // MARK: - Setup

    private func configureScene() {
        // Flat far-clear colour. The real starfield is the inverted SkyDome
        // sphere added below — NOT scene.background.contents, which tunnels a
        // single image. This is only what shows through any unlikely sliver.
        scene.background.contents = UIColor(red: 0.0, green: 0.005, blue: 0.02, alpha: 1.0)

        scnView.scene = scene
        scnView.backgroundColor = UIColor(red: 0.0, green: 0.005, blue: 0.02, alpha: 1.0)
        scnView.isOpaque = true
        scnView.antialiasingMode = .none
        scnView.preferredFramesPerSecond = 60
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = true   // redraw every vsync with the latest camera
        scnView.delegate = self
        scnView.isPlaying = true

        // Camera — wide field of view like Sky Guide's default.
        // zFar must exceed the SkyDome radius (140) so the dome isn't clipped.
        let cam = SCNCamera()
        cam.fieldOfView = 75
        cam.zNear = 0.1
        cam.zFar = 400
        ProceduralStarRenderer.configureBloom(on: cam, profile: .sky)
        cameraNode.camera = cam
        cameraNode.position = SCNVector3Zero
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // Immersive star background as a properly-mapped inverted sphere.
        // Rotation is applied to the dome NODE inside `SkyDome.make` (cheap +
        // distortion-free), so the 8K texture is never re-rasterised. Pass 0 to
        // keep the map astronomically aligned.
        scene.rootNode.addChildNode(SkyDome.make(texture: domeTexture(), rotationCCW: .pi / 2))

        scene.rootNode.addChildNode(skyRoot)
        // Group children by kind so each layer is independently manageable.
        skyRoot.addChildNode(constellationsContainer)
        skyRoot.addChildNode(starsContainer)
        skyRoot.addChildNode(bodiesContainer)

        // Lighting. Only the textured 3D bodies / loaded models react to this; the
        // additive sprites and starfield are unlit (.constant), so it's harmless
        // for the procedural fallbacks.
        //  • Directional "sunlight" — aimed at the Sun's real direction each
        //    update, giving planets and the Moon physically correct phases.
        //  • A faint ambient so the night side isn't pure black.
        let sun = SCNNode()
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.intensity = 600          // softer key light — planets were over-lit / washed out
        sunLight.color = UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1.0)
        sun.light = sunLight
        scene.rootNode.addChildNode(sun)
        sunLightNode = sun

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 22       // dim fill so the night side reads without flattening
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)

        // Cardinal markers (N/E/S/W) are rendered as screen-space labels by the
        // overlay (see buildLabels). No 3D ground silhouette: sky fills the view.

        // Tap recognizer
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tap)
    }

    // MARK: - Lifecycle

    func attach(viewModel: SkyViewModel, onSelect: @escaping (String) -> Void) {
        self.viewModel = viewModel
        self.onSelect = onSelect
    }

    func start() {
        motion.start()
    }

    func stop() {
        scnView.isPlaying = false
        motion.stop()
    }

    // MARK: - Renderer-frame update (camera + labels, locked together)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateCameraAndLabelsForCurrentFrame(time: time)
    }

    private func updateCameraAndLabelsForCurrentFrame(time: TimeInterval) {
        // 1. Exact device attitude → camera orientation. NO slerp: smoothing only
        //    added latency and made the camera trail the sensor. CMDeviceMotion is
        //    already filtered, so the raw attitude is stable on its own.
        let attitude = simd_quatf(motion.currentTransform)
        cameraNode.simdOrientation = SkyCameraMotion.cameraOrientation(for: attitude)

        updateNavigationGuidanceForCurrentFrame(time: time)

        // 2. Re-project every label THROUGH THE CAMERA WE JUST SET, this same
        //    instant. Labels are now rigidly bound to their 3D anchor points.
        labelOverlay.refresh()
    }

    private func updateNavigationGuidanceForCurrentFrame(time: TimeInterval) {
        guard let viewModel,
              let target = viewModel.navigationTarget,
              let targetWorldPosition = navigationTargetPositions[target.id] else {
            labelOverlay.highlightedLabelID = nil
            if lastNavigationGuidance.isActive {
                publishNavigationGuidanceIfNeeded(.inactive, time: time, force: true)
            }
            return
        }

        let guidance = navigationSolver.evaluate(
            targetID: target.id,
            targetName: target.name,
            targetWorldPosition: targetWorldPosition,
            cameraNode: cameraNode,
            sceneView: scnView
        )
        labelOverlay.highlightedLabelID = guidance.isTargetVisible ? "L-\(target.id)" : nil
        publishNavigationGuidanceIfNeeded(guidance, time: time)
    }

    private func publishNavigationGuidanceIfNeeded(
        _ guidance: SkyNavigationGuidance,
        time: TimeInterval,
        force: Bool = false
    ) {
        guard force
                || guidance.direction != lastNavigationGuidance.direction
                || guidance.isTargetVisible != lastNavigationGuidance.isTargetVisible
                || time - lastNavigationPublishTime >= 1.0 / 30.0 else { return }

        lastNavigationGuidance = guidance
        lastNavigationPublishTime = time
        viewModel?.updateNavigationGuidance(guidance)
    }

    // MARK: - Tap

    // Touch-target cones (the "padding" that makes point-like bodies easy to tap).
    // Planets/Sun/Moon get a wider cone than stars, and are tested FIRST so they
    // always win when overlapping a star or constellation area.
    private let bodyTapToleranceDegrees: Float = 7.0
    private let starTapToleranceDegrees: Float = 4.0

    /// Priority-ordered angular hit test. For objects that live on the celestial
    /// sphere (effectively at infinity) a geometric bounding-box `hitTest` is the
    /// wrong tool — a planet's mesh box is tiny and a constellation's line box is
    /// huge, so the ray "misses" the planet and the chart feels unclickable.
    /// Instead we measure the ANGLE between the tap ray and each body's direction
    /// and pick the closest within a per-layer tolerance cone:
    ///
    ///   LAYER 1 — planets / Sun / Moon   (tested first, widest cone) → returns immediately
    ///   LAYER 2 — individual stars       (tested only if no body matched)
    ///   LAYER 3 — constellations         (never selectable — fully ignored)
    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: scnView)
        let ray = simd_normalize(rayDirection(at: point))
        let cameraPos = cameraNode.simdWorldPosition

        // LAYER 1 — planets / Sun / Moon. If the ray lands inside a body's cone,
        // select it and STOP: lower layers are never consulted.
        if let id = closestNodeID(in: bodyNodes, toRay: ray, from: cameraPos,
                                  toleranceDegrees: bodyTapToleranceDegrees) {
            onSelect?(id)
            return
        }

        // LAYER 2 — individual stars (tighter cone).
        if let id = closestNodeID(in: starNodes, toRay: ray, from: cameraPos,
                                  toleranceDegrees: starTapToleranceDegrees) {
            onSelect?(id)
            return
        }

        // LAYER 3 — constellation lines/labels: intentionally NOT hit-tested.
    }

    /// Returns the id of the node whose world direction is closest to `ray`,
    /// provided it lies within `toleranceDegrees` of it. Camera is at the sphere
    /// centre, so each node's direction is `worldPosition − cameraPos`.
    private func closestNodeID(
        in nodes: [String: SCNNode],
        toRay ray: SIMD3<Float>,
        from cameraPos: SIMD3<Float>,
        toleranceDegrees: Float
    ) -> String? {
        let tolerance = toleranceDegrees * .pi / 180
        var best: (id: String, angle: Float)?
        for (id, node) in nodes {
            let delta = node.simdWorldPosition - cameraPos
            guard simd_length(delta) > 0.0001 else { continue }
            let toNode = simd_normalize(delta)
            let cosA = simd_dot(ray, toNode)
            // Must be in FRONT of the camera and inside the tolerance cone.
            guard cosA > 0 else { continue }
            let angle = acos(max(-1, min(1, cosA)))
            guard angle <= tolerance else { continue }
            if best == nil || angle < best!.angle { best = (id, angle) }
        }
        return best?.id
    }

    private func rayDirection(at point: CGPoint) -> SIMD3<Float> {
        let near = scnView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
        let far  = scnView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
        let n = SIMD3<Float>(Float(near.x), Float(near.y), Float(near.z))
        let f = SIMD3<Float>(Float(far.x),  Float(far.y),  Float(far.z))
        return simd_normalize(f - n)
    }

    // MARK: - Render state

    func render(state: SkyViewModel) {
        let signature = renderSignature(state: state)
        if signature == lastRenderSignature { return }
        lastRenderSignature = signature

        renderStars(state.resolvedObjects)
        renderBodies(state.resolvedObjects, moonPhase: state.moonSnapshot)
        renderConstellations(state.resolvedConstellations,
                             starPositions: state.starPositions,
                             enabled: state.showConstellations)
        renderSelectionHalo(for: state.selectedObject, in: state.resolvedObjects)
        rebuildNavigationTargetPositions(state: state)
        labelOverlay.labels = buildLabels(state: state)

        // State-driven highlight reset: the moment the navigation target is gone
        // (the 'X' was tapped / search cleared), drop the highlight so a previous
        // target's ring can't linger. `render(state:)` runs on this @Observable
        // change, so the cleanup is bound directly to the search state.
        if state.navigationTarget == nil {
            labelOverlay.highlightedLabelID = nil
        }
    }

    /// Collect everything that should carry a screen-space label. Star labels are
    /// limited to brighter stars so the chart doesn't become a wall of text.
    private func buildLabels(state: SkyViewModel) -> [SkyLabel] {
        var out: [SkyLabel] = []

        for obj in state.resolvedObjects {
            let world = obj.horizontal.worldDirection * SkyNodeFactory.sphereRadius
            switch obj.object.type {
            case .star:
                guard (obj.object.magnitude ?? 3.0) < 3.6 else { continue }
                out.append(SkyLabel(id: "L-\(obj.id)", world: world, text: obj.object.name, kind: .star))
            case .planet:
                out.append(SkyLabel(id: "L-\(obj.id)", world: world, text: obj.object.name, kind: .planet))
            case .sun, .moon:
                out.append(SkyLabel(id: "L-\(obj.id)", world: world, text: obj.object.name, kind: .body))
            default:
                break
            }
        }

        if state.showConstellations {
            for c in state.resolvedConstellations {
                if let centroid = SkyNodeFactory.constellationCentroid(c, starPositions: state.starPositions) {
                    out.append(SkyLabel(id: "L-con-\(c.id)", world: centroid, text: c.name, kind: .constellation))
                }
            }
        }

        // Cardinal markers at the horizon.
        for (name, az) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
            let coord = HorizontalCoordinate(azimuthDegrees: az, altitudeDegrees: 2.0)
            out.append(SkyLabel(id: "L-card-\(name)",
                                world: coord.worldDirection * SkyNodeFactory.sphereRadius,
                                text: name, kind: .cardinal))
        }
        return out
    }

    private func rebuildNavigationTargetPositions(state: SkyViewModel) {
        var positions: [String: SIMD3<Float>] = [:]
        positions.reserveCapacity(state.resolvedObjects.count + state.resolvedConstellations.count)

        for object in state.resolvedObjects {
            let p = SkyNodeFactory.position(for: object.horizontal)
            positions[object.id] = SIMD3<Float>(p.x, p.y, p.z)
        }

        for constellation in state.resolvedConstellations {
            guard let centroid = navigationCentroid(
                for: constellation,
                starPositions: state.starPositions
            ) else { continue }
            positions["constellation-\(constellation.id)"] = centroid
        }

        navigationTargetPositions = positions
    }

    private func navigationCentroid(
        for constellation: Constellation,
        starPositions: [String: HorizontalCoordinate]
    ) -> SIMD3<Float>? {
        var sum = SIMD3<Float>(0, 0, 0)
        var count: Float = 0

        for id in constellation.anchorStarIds {
            guard let horizontal = starPositions[id] else { continue }
            sum += horizontal.worldDirection
            count += 1
        }

        if count == 0 {
            for segment in constellation.lines {
                if let a = starPositions[segment.starA] {
                    sum += a.worldDirection
                    count += 1
                }
                if let b = starPositions[segment.starB] {
                    sum += b.worldDirection
                    count += 1
                }
            }
        }

        guard count > 0 else { return nil }
        return simd_normalize(sum / count) * SkyNodeFactory.sphereRadius
    }

    private func renderStars(_ resolved: [ResolvedSkyObject]) {
        let stars = resolved.filter { $0.object.type == .star }
        let newIDs = Set(stars.map { $0.id })
        for (id, node) in starNodes where !newIDs.contains(id) {
            node.removeFromParentNode()
            starNodes.removeValue(forKey: id)
        }
        for s in stars {
            if let existing = starNodes[s.id] {
                existing.position = SkyNodeFactory.position(for: s.horizontal)
            } else {
                // Stars stay procedural sprites — no 3D model substitution.
                let node = SkyNodeFactory.makeStar(resolved: s)
                starsContainer.addChildNode(node)
                starNodes[s.id] = node
            }
        }
    }

    private func renderBodies(_ resolved: [ResolvedSkyObject], moonPhase: MoonPhase.Snapshot) {
        let bodies = resolved.filter { [.sun, .moon, .planet].contains($0.object.type) }
        let newIDs = Set(bodies.map { $0.id })
        for (id, node) in bodyNodes where !newIDs.contains(id) {
            node.removeFromParentNode()
            bodyNodes.removeValue(forKey: id)
        }
        for b in bodies {
            if let existing = bodyNodes[b.id] {
                existing.position = SkyNodeFactory.position(for: b.horizontal)
            } else {
                let node = makeBodyNode(b, moonPhase: moonPhase)
                bodiesContainer.addChildNode(node)
                bodyNodes[b.id] = node
                requestHeroModel(for: b)   // swaps in a bundled .usdz when available
            }
        }
        aimSunlight(using: resolved)
    }

    /// Prefers the native Sun asset and textured 3D bodies for planets/Moon;
    /// falls back to the additive sprite while async model loading completes.
    private func makeBodyNode(_ b: ResolvedSkyObject, moonPhase: MoonPhase.Snapshot) -> SCNNode {
        let radius = sphereRadius(for: b.object)
        if let textured = CelestialBodyFactory.texturedBody(
            bodyName: b.object.name,
            type: b.object.type,
            radius: radius,
            nodeName: SkyNodeFactory.nodeNamePrefix + b.id
        ) {
            textured.position = SkyNodeFactory.position(for: b.horizontal)
            textured.renderingOrder = 50
            // Name label handled by SkyLabelOverlayView (screen-space).
            return textured
        }
        // Fallback: existing sprite (already includes its label + Moon phase art).
        let sprite = SkyNodeFactory.makeBody(resolved: b, moonPhase: moonPhase)
        sprite.position = SkyNodeFactory.position(for: b.horizontal)
        return sprite
    }

    /// Make a loaded model self-illuminated: ignore scene lights (`.constant`)
    /// and emit its own diffuse texture, so every part — including Saturn's rings,
    /// which a directional Sun light would leave in shadow — is fully visible.
    private static func makeModelUnlit(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            guard let materials = child.geometry?.materials else { return }
            for material in materials {
                material.lightingModel = .constant
                material.emission.contents = material.diffuse.contents
            }
        }
    }

    /// On-sphere radius (scene units) for a textured body.
    private func sphereRadius(for object: CelestialObject) -> CGFloat {
        switch object.type {
        case .sun:  return 3.0
        case .moon: return 2.6
        default:
            switch object.name {
            case "Jupiter": return 2.6
            case "Saturn":  return 3.6   // bigger so the rings read clearly on the map
            case "Venus":   return 2.0
            case "Mars":    return 1.7
            case "Mercury": return 1.3
            default:        return 1.5
            }
        }
    }

    /// Aim the directional light along the Sun → origin vector so lit bodies
    /// show correct phases. Directional lights shine along their local -Z, so
    /// positioning the node at the Sun's direction and looking at the origin
    /// makes light travel inward from the Sun. Works even when the Sun is below
    /// the horizon (e.g. a night-time crescent Moon).
    private func aimSunlight(using resolved: [ResolvedSkyObject]) {
        guard let sunLightNode,
              let sun = resolved.first(where: { $0.object.type == .sun }) else { return }
        let dir = sun.horizontal.worldDirection
        sunLightNode.simdPosition = dir * 10
        sunLightNode.look(at: SCNVector3Zero)
    }

    /// Placeholder → 3D-model swap. A sprite shows instantly; meanwhile the
    /// bundled `.usdz` named after the body (e.g. "Jupiter.usdz" in Models3D/) is
    /// parsed OFF the main actor and swapped in when ready. If no model is bundled,
    /// the placeholder remains.
    private func requestHeroModel(for b: ResolvedSkyObject) {
        // The Sun, planets and Moon can use native bundled hero models. Distant
        // catalog stars stay procedural and uniformly scaled for map clarity.
        guard b.object.type == .sun || b.object.type == .planet || b.object.type == .moon else { return }
        guard !heroModelRequested.contains(b.id) else { return }
        heroModelRequested.insert(b.id)

        let modelName = b.object.name              // exact: "Jupiter", "Moon", …
        let nodeName = SkyNodeFactory.nodeNamePrefix + b.id
        let targetRadius = Float(sphereRadius(for: b.object))

        let isSaturn = (modelName == "Saturn")

        Task { [weak self] in
            guard let model = await ModelLoader.shared.load(named: modelName) else { return }
            await MainActor.run {
                guard let self, let placeholder = self.bodyNodes[b.id] else { return }

                // ── Unscaled CONTAINER ──────────────────────────────────────
                // Anchors the body on the sphere and carries the NAME (for tap
                // hit-testing) and the LABEL. Because the container is never
                // scaled, the label keeps a constant size no matter how much the
                // .usdz had to be scaled to normalize its native units. (This was
                // the bug making planet labels microscopic / huge.)
                let container = SCNNode()
                container.name = nodeName
                container.position = placeholder.position

                // Normalize the export's arbitrary scale so its largest dimension
                // equals our intended on-sphere diameter (rings included).
                let (minB, maxB) = model.boundingBox
                let extent = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
                if extent > 0 {
                    let s = (targetRadius * 2) / extent
                    model.scale = SCNVector3(s, s, s)
                }
                model.name = "visual"
                model.renderingOrder = 50

                if isSaturn {
                    // Render Saturn UNLIT (self-illuminated by its own texture) so
                    // the rings are always visible — a directional Sun light leaves
                    // the rings in shadow / too dark to read on the map.
                    Self.makeModelUnlit(model)

                    // ── Saturn re-alignment ─────────────────────────────────
                    // facing → tilt → model. `facing` aims the model's −Z at the
                    // camera (origin); the fixed `tilt` then opens the ring plane
                    // into the iconic oblique pose; the model spins about its pole
                    // INSIDE the tilt, so the rings stay put while the globe turns.
                    let facing = SCNNode()
                    let tilt = SCNNode()
                    tilt.eulerAngles = SCNVector3(-Float.pi * 0.16, 0, 0) // ≈ −29° about local X
                    model.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 140)))
                    tilt.addChildNode(model)
                    facing.addChildNode(tilt)
                    container.addChildNode(facing)
                    self.bodiesContainer.addChildNode(container)
                    facing.look(at: SCNVector3Zero)   // −Z → camera at (0,0,0)
                } else {
                    // Other planets/Moon: a gentle spin about the polar (Y) axis.
                    model.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 120)))
                    container.addChildNode(model)
                    self.bodiesContainer.addChildNode(container)
                }

                // Name label handled by SkyLabelOverlayView (screen-space).
                placeholder.removeFromParentNode()
                self.bodyNodes[b.id] = container
            }
        }
    }

    private func renderConstellations(
        _ constellations: [Constellation],
        starPositions: [String: HorizontalCoordinate],
        enabled: Bool
    ) {
        if !enabled {
            for (_, node) in constellationNodes { node.isHidden = true }
            return
        }
        let newIDs = Set(constellations.map { $0.id })
        for (id, node) in constellationNodes where !newIDs.contains(id) {
            node.removeFromParentNode()
            constellationNodes.removeValue(forKey: id)
        }
        for c in constellations {
            constellationNodes[c.id]?.removeFromParentNode()
            if let node = SkyNodeFactory.makeConstellationGroup(c, starPositions: starPositions) {
                constellationsContainer.addChildNode(node)
                constellationNodes[c.id] = node
            }
        }
    }

    private func renderSelectionHalo(
        for selected: CelestialObject?,
        in resolved: [ResolvedSkyObject]
    ) {
        selectionHaloNode?.removeFromParentNode()
        selectionHaloNode = nil
        guard let selected,
              let target = resolved.first(where: { $0.id == selected.id }) else { return }
        let halo = SkyNodeFactory.makeSelectionHalo(
            at: SkyNodeFactory.position(for: target.horizontal)
        )
        skyRoot.addChildNode(halo)
        selectionHaloNode = halo
    }

    private func renderSignature(state: SkyViewModel) -> Int {
        var hasher = Hasher()
        hasher.combine(state.showConstellations)
        hasher.combine(state.selectedObject?.id ?? "")
        hasher.combine(state.navigationTarget?.id ?? "")
        hasher.combine(Int(state.currentDate.timeIntervalSince1970 / 30))
        if let coord = state.locationService.coordinate {
            hasher.combine(Int(coord.latitude * 100))
            hasher.combine(Int(coord.longitude * 100))
        }
        return hasher.finalize()
    }

    // MARK: - Dome texture

    /// Equirectangular star map for the SkyDome sphere.
    ///
    /// CRITICAL: the 8K map is loaded as a RAW resource file from the bundle, NOT
    /// from `Assets.xcassets`. Xcode's asset catalog recompresses / converts large
    /// images (lossy GPU formats + downsampling), which shredded the Milky Way's
    /// fine gradients into blocky purple/cyan artifacts. `UIImage(contentsOfFile:)`
    /// on the standalone file preserves the original JPEG fidelity 1:1.
    ///
    /// Returned UNROTATED: orientation is applied to the dome node in
    /// `SkyDome.make` (free for an 8K texture — re-rasterising here would spike
    /// memory and stutter the first frame).
    private func domeTexture() -> UIImage {
        // Use the StarsMilkyWay8K photo as the immersive background. Loaded RAW
        // from the bundle resource (Resources/StarsMilkyWay8K.jpg) rather than via
        // UIImage(named:) so the Asset Catalog's lossy recompression is bypassed
        // and the original fidelity is preserved. Falls back to a procedural
        // backdrop only if the file is missing.
        if let path = Bundle.main.path(forResource: "StarsMilkyWay8K", ofType: "jpg"),
           let image = UIImage(contentsOfFile: path) {
            return image
        }
        return backgroundGradientImage(includeStars: false)
    }

    private func backgroundGradientImage(includeStars: Bool = true) -> UIImage {
        // A baked equirectangular (2:1) starfield: deep-space gradient + a faint
        // diagonal Milky Way band + thousands of stars of varying brightness.
        // 4096×2048 gives ~11 texel/° — enough that, with a ~75° FoV, texels are
        // close to 1:1 with screen pixels, so stars stay crisp. Drawn ONCE and
        // wrapped on the dome, so it costs nothing per frame.
        let size = CGSize(width: 4096, height: 2048)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Base gradient
            let colors = [
                UIColor(red: 0.015, green: 0.020, blue: 0.055, alpha: 1.0).cgColor,
                UIColor(red: 0.005, green: 0.010, blue: 0.030, alpha: 1.0).cgColor,
                UIColor(red: 0.000, green: 0.004, blue: 0.016, alpha: 1.0).cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1.0])!
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )

            // Milky Way band — a soft diagonal glow.
            cg.saveGState()
            cg.setBlendMode(.plusLighter)
            for _ in 0..<3 {
                let bandColors = [
                    UIColor(red: 0.30, green: 0.40, blue: 0.62, alpha: 0.0).cgColor,
                    UIColor(red: 0.30, green: 0.40, blue: 0.62, alpha: 0.10).cgColor,
                    UIColor(red: 0.30, green: 0.40, blue: 0.62, alpha: 0.0).cgColor
                ] as CFArray
                let bandGrad = CGGradient(colorsSpace: space, colors: bandColors, locations: [0, 0.5, 1.0])!
                cg.saveGState()
                cg.translateBy(x: size.width * 0.55, y: size.height * 0.5)
                cg.rotate(by: -0.5)
                cg.drawLinearGradient(
                    bandGrad,
                    start: CGPoint(x: 0, y: -size.height * 0.28),
                    end: CGPoint(x: 0, y: size.height * 0.28),
                    options: []
                )
                cg.restoreGState()
            }
            cg.restoreGState()

            // Background point-stars — drawn only when requested. For the sky dome
            // we pass `includeStars: false` so the ONLY stars on screen are the
            // named catalog stars.
            guard includeStars else { return }
            var seed: UInt64 = 0x5EED_1234_ABCD
            func rnd() -> CGFloat {
                seed ^= seed >> 12; seed ^= seed << 25; seed ^= seed >> 27
                return CGFloat((seed &* 2_685_821_657_736_338_717) >> 11) / CGFloat(1 << 53)
            }
            cg.setBlendMode(.plusLighter)
            for _ in 0..<5000 {
                let x = rnd() * size.width
                let y = rnd() * size.height
                let r = 0.6 + rnd() * rnd() * 3.0
                let b = 0.35 + rnd() * 0.65
                // Slight color variety
                let tint = rnd()
                let color: UIColor
                if tint < 0.15 {
                    color = UIColor(red: b, green: b * 0.85, blue: b * 0.7, alpha: b)      // warm
                } else if tint < 0.30 {
                    color = UIColor(red: b * 0.8, green: b * 0.9, blue: b, alpha: b)        // cool
                } else {
                    color = UIColor(white: b, alpha: b)
                }
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }
}
