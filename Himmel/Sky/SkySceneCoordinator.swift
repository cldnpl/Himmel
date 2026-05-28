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
    private let skyRoot = SCNNode()
    /// Accessed from SceneKit's render thread inside `renderer(_:updateAtTime:)`.
    /// Created once in `init` and never reassigned, so unchecked access is safe.
    nonisolated(unsafe) private let cameraNode = SCNNode()
    private let motion = MotionService()

    private weak var viewModel: SkyViewModel?
    private var onSelect: ((String) -> Void)?

    private var starNodes: [String: SCNNode] = [:]
    private var bodyNodes: [String: SCNNode] = [:]
    private var constellationNodes: [String: SCNNode] = [:]
    private var selectionHaloNode: SCNNode?

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
        scnView.rendersContinuously = true
        scnView.delegate = self

        // Camera — wide field of view like Sky Guide's default.
        // zFar must exceed the SkyDome radius (140) so the dome isn't clipped.
        let cam = SCNCamera()
        cam.fieldOfView = 75
        cam.zNear = 0.1
        cam.zFar = 400
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

        // Lighting. Only the textured 3D bodies react to this; the additive
        // sprites and starfield are unlit (.constant), so this is harmless when
        // no textures are bundled.
        //  • Directional "sunlight" — aimed at the Sun's real direction each
        //    update, giving planets and the Moon physically correct phases.
        //  • A faint ambient so the night side isn't pure black.
        let sun = SCNNode()
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.intensity = 1200
        sunLight.color = UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1.0)
        sun.light = sunLight
        scene.rootNode.addChildNode(sun)
        sunLightNode = sun

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 45
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)

        // Cardinal markers (N/E/S/W) — fixed to the world so they stay locked to
        // the horizon. The ground/city silhouette is intentionally omitted: the
        // sky fills the whole view.
        scene.rootNode.addChildNode(SkyNodeFactory.makeCardinalMarkers())

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
        motion.stop()
    }

    // MARK: - Per-frame camera update

    /// Called on SceneKit's render thread every frame. We set the camera
    /// orientation here *synchronously* — dispatching to the main actor would
    /// add a frame of latency and cause the visible stutter. A light
    /// quaternion slerp smooths sensor jitter without adding lag.
    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // 1. Raw device attitude (body→world) as a quaternion.
        let attitude = simd_quatf(motion.currentTransform)
        // 2. Apply the camera-mapping policy: invert (q⁻¹) so pitch/yaw track the
        //    phone naturally instead of mirrored. See SkyCameraMotion for the math.
        let target = SkyCameraMotion.cameraOrientation(for: attitude)
        // 3. Slerp from the current orientation → anti-jitter, zero added lag.
        let current = cameraNode.simdOrientation
        cameraNode.simdOrientation = simd_slerp(current, target, 0.5)
    }

    // MARK: - Tap

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: scnView)
        let opts: [SCNHitTestOption: Any] = [
            .boundingBoxOnly: true,
            .ignoreHiddenNodes: true,
            .searchMode: SCNHitTestSearchMode.all.rawValue
        ]
        let hits = scnView.hitTest(point, options: opts)
        guard !hits.isEmpty else { return }

        // Walk up to the celestial container node and pick the closest by angular dist.
        let cameraPos = SIMD3<Float>(0, 0, 0)
        let rayDir = rayDirection(at: point)
        var best: (id: String, angle: Float)?

        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node {
                if let name = n.name, name.hasPrefix(SkyNodeFactory.nodeNamePrefix) {
                    let id = String(name.dropFirst(SkyNodeFactory.nodeNamePrefix.count))
                    let p = n.simdWorldPosition
                    let toNode = simd_normalize(p - cameraPos)
                    let cosA = simd_dot(simd_normalize(rayDir), toNode)
                    let angle = acos(max(-1, min(1, cosA)))
                    if best == nil || angle < best!.angle {
                        best = (id, angle)
                    }
                    break
                }
                node = n.parent
            }
        }
        if let best { onSelect?(best.id) }
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
                let node = SkyNodeFactory.makeStar(resolved: s)
                skyRoot.addChildNode(node)
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
                skyRoot.addChildNode(node)
                bodyNodes[b.id] = node
                requestHeroModel(for: b)   // no-op unless a model is bundled
            }
        }
        aimSunlight(using: resolved)
    }

    /// Prefers a textured 3D sphere (Solar System Scope maps); falls back to the
    /// additive sprite when no diffuse texture is bundled for this body.
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
            // Name label beside the sphere (label keeps its own billboard).
            let label = SkyNodeFactory.makeLabel(
                text: b.object.name,
                style: b.object.type == .planet ? .planet : .body,
                yOffset: -Float(radius) * 1.6
            )
            textured.addChildNode(label)
            return textured
        }
        // Fallback: existing sprite (already includes its label + Moon phase art).
        let sprite = SkyNodeFactory.makeBody(resolved: b, moonPhase: moonPhase)
        sprite.position = SkyNodeFactory.position(for: b.horizontal)
        return sprite
    }

    /// On-sphere radius (scene units) for a textured body.
    private func sphereRadius(for object: CelestialObject) -> CGFloat {
        switch object.type {
        case .sun:  return 3.0
        case .moon: return 2.6
        default:
            switch object.name {
            case "Jupiter": return 2.2
            case "Saturn":  return 2.0
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

    /// Demonstrates the placeholder→model swap. If a bundled model named after
    /// the body exists (e.g. "saturn.usdz" from Sketchfab), it is parsed off the
    /// main actor and swapped in for the procedural placeholder. Otherwise nothing
    /// happens and the placeholder stays.
    private func requestHeroModel(for b: ResolvedSkyObject) {
        guard !heroModelRequested.contains(b.id) else { return }
        heroModelRequested.insert(b.id)
        let modelName = b.object.name.lowercased()
        let nodeName = SkyNodeFactory.nodeNamePrefix + b.id
        let targetRadius = Float(sphereRadius(for: b.object))

        Task { [weak self] in
            guard let model = await ModelLoader.shared.load(named: modelName) else { return }
            await MainActor.run {
                guard let self, let placeholder = self.bodyNodes[b.id] else { return }
                // Normalize arbitrary export scale to our on-sphere radius.
                let (minB, maxB) = model.boundingBox
                let extent = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
                if extent > 0 {
                    let s = (targetRadius * 2) / extent
                    model.scale = SCNVector3(s, s, s)
                }
                model.name = nodeName
                model.position = placeholder.position
                model.renderingOrder = 50
                let label = SkyNodeFactory.makeLabel(
                    text: b.object.name,
                    style: b.object.type == .planet ? .planet : .body,
                    yOffset: -targetRadius * 1.6
                )
                model.addChildNode(label)
                self.skyRoot.addChildNode(model)
                placeholder.removeFromParentNode()
                self.bodyNodes[b.id] = model
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
                skyRoot.addChildNode(node)
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
        hasher.combine(Int(state.currentDate.timeIntervalSince1970 / 30))
        if let coord = state.locationService.coordinate {
            hasher.combine(Int(coord.latitude * 100))
            hasher.combine(Int(coord.longitude * 100))
        }
        return hasher.finalize()
    }

    // MARK: - Dome texture

    /// Equirectangular star map for the SkyDome sphere. Loading priority:
    ///   1. "StarsMilkyWay8K" — the Solar System Scope 8K Stars + Milky Way map.
    ///   2. "StarrySky"       — any other bundled equirect/photo.
    ///   3. procedural 4096×2048 starfield (so the dome is never empty).
    ///
    /// The image is returned UNROTATED: rotation is applied to the dome node in
    /// `SkyDome.make`, which is free for an 8K texture (re-rasterising 130+ MB
    /// here would spike memory and stutter the first frame).
    private func domeTexture() -> UIImage {
        UIImage(named: "StarsMilkyWay8K")
            ?? UIImage(named: "StarrySky")
            ?? backgroundGradientImage()
    }

    private func backgroundGradientImage() -> UIImage {
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

            // Stars
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
