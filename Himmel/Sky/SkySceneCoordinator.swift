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
    private let cameraNode = SCNNode()
    private let motion = MotionService()

    private weak var viewModel: SkyViewModel?
    private var onSelect: ((String) -> Void)?

    private var starNodes: [String: SCNNode] = [:]
    private var bodyNodes: [String: SCNNode] = [:]
    private var constellationNodes: [String: SCNNode] = [:]
    private var selectionHaloNode: SCNNode?
    private var backgroundStarsNode: SCNNode?

    private var lastRenderSignature: Int = 0

    override init() {
        self.scnView = SCNView(frame: .zero)
        super.init()
        configureScene()
    }

    // MARK: - Setup

    private func configureScene() {
        // Deep-night background — no camera passthrough.
        scene.background.contents = backgroundGradientImage()

        scnView.scene = scene
        scnView.backgroundColor = UIColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1.0)
        scnView.isOpaque = true
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = true
        scnView.delegate = self

        // Camera — wide field of view like Sky Guide's default.
        let cam = SCNCamera()
        cam.fieldOfView = 75
        cam.zNear = 0.1
        cam.zFar = 200
        cameraNode.camera = cam
        cameraNode.position = SCNVector3Zero
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        scene.rootNode.addChildNode(skyRoot)

        // Filler starfield — small, faint, all over the sphere.
        let bg = SkyNodeFactory.makeBackgroundStars(count: 700)
        skyRoot.addChildNode(bg)
        backgroundStarsNode = bg

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

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let transform = motion.currentTransform
        Task { @MainActor in
            self.cameraNode.simdTransform = transform
        }
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
                let node = SkyNodeFactory.makeBody(resolved: b, moonPhase: moonPhase)
                skyRoot.addChildNode(node)
                bodyNodes[b.id] = node
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

    // MARK: - Background image

    private func backgroundGradientImage() -> UIImage {
        // Vertical gradient: deep navy at the bottom to near-black at the top.
        // Used as scene.background (treated as equirectangular by SceneKit).
        let size = CGSize(width: 256, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(red: 0.02, green: 0.03, blue: 0.09, alpha: 1.0).cgColor,
                UIColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1.0).cgColor,
                UIColor(red: 0.00, green: 0.01, blue: 0.04, alpha: 1.0).cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1.0])!
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }
    }
}
