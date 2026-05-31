//
//  SkyNodeFactory.swift
//  Himmel
//
//  Builds every SceneKit node placed on the virtual celestial sphere:
//  background filler stars, catalog stars, planets/Sun/Moon, constellation
//  asterism lines, and the text labels that float beside each element.
//

import Foundation
import SceneKit
import UIKit
import simd

enum SkyNodeFactory {

    /// Radius of the imaginary celestial sphere around the camera, in scene units.
    static let sphereRadius: Float = 50.0

    /// Prefix used on `SCNNode.name` so the coordinator can identify celestial taps.
    static let nodeNamePrefix = "celestial:"

    enum LabelStyle {
        case star, planet, body, constellation, cardinal
    }

    // MARK: - Stars

    static func makeStar(resolved: ResolvedSkyObject) -> SCNNode {
        return ProceduralStarRenderer.makeStarNode(
            for: resolved.object,
            radius: mapStarVisualRadius,
            nodeName: nodeNamePrefix + resolved.id,
            position: position(for: resolved.horizontal),
            segmentCount: 48,
            // No halo for ANY star → every star is the same small coloured dot
            // (like Sheliak / Sulafat). The bright ones looked huge only because
            // of their glow halo; the core radius is already uniform.
            includeHalo: false,
            appliesClassificationScale: false,
            hitTargetRadius: mapStarHitTargetRadius
        )
    }

    // MARK: - Sun / Moon / planets

    static func makeBody(resolved: ResolvedSkyObject, moonPhase: MoonPhase.Snapshot?) -> SCNNode {
        let container = SCNNode()
        container.name = nodeNamePrefix + resolved.id
        container.position = position(for: resolved.horizontal)
        container.constraints = [billboard()]
        container.renderingOrder = 50

        // Planets fall back to a SOLID colour globe (not an additive glow sprite):
        // bodies without a bundled hero .usdz (Uranus, Neptune) otherwise rendered
        // as a bloom-blown white blob. A `.constant` disc in the planet's colour
        // reads as a clean, dim planet and never saturates. Planets that DO have a
        // model show this only for the instant before the textured model swaps in.
        if resolved.object.type == .planet {
            let r = CGFloat(planetSize(for: resolved.object.name)) * 0.42
            container.addChildNode(makePlanetGlobe(named: resolved.object.name, radius: r))
            return container
        }

        let (sprite, size): (UIImage, CGFloat)
        switch resolved.object.type {
        case .sun:
            sprite = SpriteCache.sun()
            size = 6.0
        case .moon:
            sprite = SpriteCache.moon(
                phaseIllumination: moonPhase?.illumination ?? 0.5,
                waxing: (moonPhase?.age ?? 0) < 14.77
            )
            size = 5.0
        default:
            sprite = SpriteCache.starGlow(tint: .white, bright: true)
            size = 3.0
        }

        let plane = SCNPlane(width: size, height: size)
        plane.firstMaterial = makeAdditiveMaterial(image: sprite)
        container.addChildNode(SCNNode(geometry: plane))

        if resolved.object.type == .sun {
            let spin = SCNAction.repeatForever(.rotateBy(x: 0, y: 0, z: .pi, duration: 36.0))
            container.runAction(spin)
        }
        // Name labels are rendered by SkyLabelOverlayView (screen-space), not here.
        return container
    }

    // MARK: - Constellation lines + names

    /// KVC key toggling the constellation horizon fade (0 = off, 1 = on).
    static let horizonFadeKey = "horizonFade"

    /// Surface modifier mirroring `SkyDome.horizonClipModifier`: fades the
    /// asterism lines out just below the horizon so they stop bleeding over the
    /// real ground/buildings in Live AR. The line material is ADDITIVE, so we
    /// must scale the COLOUR toward zero (not just alpha) — additive blending
    /// adds rgb regardless of alpha. `horizonFade` is driven by the coordinator.
    private static let lineHorizonClipModifier = """
    #pragma arguments
    float horizonFade;
    #pragma body
    float3 worldDir = normalize((scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz);
    float clipped = smoothstep(-0.04, 0.06, worldDir.z);
    half hf = half(mix(1.0, clipped, horizonFade));
    _surface.diffuse.rgb *= hf;
    _surface.diffuse.a   *= hf;
    _surface.emission.rgb *= hf;
    _surface.emission.a   *= hf;
    """

    static func makeConstellationGroup(
        _ constellation: ResolvedConstellation
    ) -> SCNNode? {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        var i: Int32 = 0
        for segment in constellation.segments {
            let a = segment.a
            let b = segment.b
            guard a.altitudeDegrees > -3 && b.altitudeDegrees > -3 else { continue }
            vertices.append(position(for: a))
            vertices.append(position(for: b))
            indices.append(i); indices.append(i + 1); i += 2
        }
        guard !indices.isEmpty else { return nil }

        let group = SCNNode()
        group.name = nodeNamePrefix + "constellation-\(constellation.id)"

        let lineGeom = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .line)]
        )
        let lineMat = SCNMaterial()
        lineMat.diffuse.contents = UIColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.55)
        lineMat.emission.contents = UIColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.55)
        lineMat.lightingModel = .constant
        lineMat.writesToDepthBuffer = false
        lineMat.readsFromDepthBuffer = false
        lineMat.blendMode = .add
        // Horizon masking layer: off by default, switched on in Live AR by the
        // coordinator so lines fade at the horizon instead of overlaying ground.
        lineMat.shaderModifiers = [.surface: lineHorizonClipModifier]
        lineMat.setValue(NSNumber(value: 0.0), forKey: horizonFadeKey)
        lineGeom.firstMaterial = lineMat
        let lineNode = SCNNode(geometry: lineGeom)
        lineNode.renderingOrder = -50
        group.addChildNode(lineNode)
        // The constellation NAME is rendered by SkyLabelOverlayView at the
        // centroid (computed separately by the coordinator), not as a 3D node.
        return group
    }

    /// Centroid direction (unit vector × radius) of a constellation's visible
    /// asterism, used by the overlay to place the constellation name. Returns nil
    /// if no segment is above the horizon.
    static func constellationCentroid(
        _ constellation: ResolvedConstellation
    ) -> SIMD3<Float>? {
        var sum = SIMD3<Float>(0, 0, 0)
        var count: Float = 0
        for segment in constellation.segments {
            let a = segment.a
            let b = segment.b
            guard a.altitudeDegrees > -3 && b.altitudeDegrees > -3 else { continue }
            sum += a.worldDirection
            sum += b.worldDirection
            count += 2
        }
        guard count > 0 else { return nil }
        return simd_normalize(sum / count) * sphereRadius
    }

    // MARK: - Ground silhouette (Stellarium-style horizon)

    /// Builds the fixed ground as a *thin* silhouette band sitting on the horizon
    /// (Stellarium-style), NOT a full black hemisphere: a low rolling treeline
    /// rising a few degrees above the horizon, on top of a short dark skirt that
    /// blends into the night background just below it.
    static func makeGround() -> SCNNode {
        let container = SCNNode()
        container.name = "ground"
        let R = sphereRadius * 0.92

        // 1) Short dark skirt just below the horizon (z ∈ [-skirtH, 0]).
        //    Only ~12° tall, so it reads as a slim base — not a black wall.
        //    Its colour matches the background's lower band so the bottom edge
        //    melts into the sky instead of forming a hard line.
        let skirtH = sphereRadius * 0.20
        let skirt = SCNCylinder(radius: CGFloat(R), height: CGFloat(skirtH))
        skirt.radialSegmentCount = 96
        let skirtMat = SCNMaterial()
        skirtMat.diffuse.contents = UIColor(red: 0.006, green: 0.010, blue: 0.024, alpha: 1.0)
        skirtMat.lightingModel = .constant
        skirtMat.isDoubleSided = true
        skirtMat.writesToDepthBuffer = false
        skirtMat.readsFromDepthBuffer = false
        skirt.firstMaterial = skirtMat
        let skirtNode = SCNNode(geometry: skirt)
        skirtNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)   // axis local +Y → world +Z
        skirtNode.position = SCNVector3(0, 0, -skirtH / 2)        // spans z ∈ [-skirtH, 0]
        skirtNode.renderingOrder = 120
        container.addChildNode(skirtNode)

        // 2) Low rolling treeline silhouette rising just above the horizon.
        let skyline = makeSkylineMesh(radius: R * 0.999, segments: 220)
        skyline.renderingOrder = 121
        container.addChildNode(skyline)

        return container
    }

    /// A 360° low silhouette (treeline / distant hills) rising only a few degrees
    /// above the horizon. Smooth, correlated heights from a few harmonics give an
    /// organic edge instead of jagged blocks; occasional taller trees add accent.
    private static func makeSkylineMesh(radius r: Float, segments: Int) -> SCNNode {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        var seed: UInt64 = 0xBEEF_F00D_1234
        let twoPi = 2 * Float.pi
        var idx: Int32 = 0
        let zBottom: Float = -0.25   // dip a touch below the horizon to meet the skirt

        // Smooth rolling height (in scene units) from low-frequency harmonics.
        // Max ≈ 2.2 units at radius ~46 → only ~2.7° tall: a slim silhouette.
        func heightAt(_ a: Float) -> Float {
            let rolling = 0.55
                + 0.35 * sin(a * 6 + 0.5)
                + 0.22 * sin(a * 11 + 1.7)
                + 0.13 * sin(a * 19 + 4.1)
            return max(0.18, rolling)
        }

        for i in 0..<segments {
            let a0 = twoPi * Float(i) / Float(segments)
            let a1 = twoPi * Float(i + 1) / Float(segments)
            let mid = (a0 + a1) * 0.5
            var h = heightAt(mid) * 1.4
            // Rare taller tree for character.
            if nextRandom(&seed) < 0.05 { h += Float(0.8 + nextRandom(&seed) * 1.2) }

            let b0 = SCNVector3(r * cos(a0), r * sin(a0), zBottom)
            let b1 = SCNVector3(r * cos(a1), r * sin(a1), zBottom)
            let t1 = SCNVector3(r * cos(a1), r * sin(a1), h)
            let t0 = SCNVector3(r * cos(a0), r * sin(a0), h)
            vertices.append(contentsOf: [b0, b1, t1, t0])
            indices.append(contentsOf: [idx, idx + 1, idx + 2, idx, idx + 2, idx + 3])
            idx += 4
        }

        let geom = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.002, green: 0.004, blue: 0.012, alpha: 1.0)
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = false
        geom.firstMaterial = mat
        return SCNNode(geometry: geom)
    }

    // MARK: - Cardinal markers (N / E / S / W)

    static func makeCardinalMarkers() -> SCNNode {
        let parent = SCNNode()
        parent.name = "cardinals"
        let points: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        for (label, az) in points {
            let coord = HorizontalCoordinate(azimuthDegrees: az, altitudeDegrees: 3.5)
            let node = makeLabel(text: label, style: .cardinal, yOffset: 0)
            node.position = position(for: coord)
            node.renderingOrder = 140   // above the skyline so always visible
            parent.addChildNode(node)
        }
        return parent
    }

    // MARK: - Selection halo

    static func makeSelectionHalo(at position: SCNVector3) -> SCNNode {
        let plane = SCNPlane(width: 7.0, height: 7.0)
        plane.firstMaterial = makeAdditiveMaterial(image: SpriteCache.halo())
        let node = SCNNode(geometry: plane)
        node.position = position
        node.constraints = [billboard()]
        node.renderingOrder = 200
        let up = SCNAction.scale(to: 1.12, duration: 0.8)
        let down = SCNAction.scale(to: 0.86, duration: 0.8)
        up.timingMode = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        node.runAction(.repeatForever(.sequence([up, down])))
        return node
    }

    // MARK: - Position helper

    static func position(for horizontal: HorizontalCoordinate) -> SCNVector3 {
        let v = horizontal.worldDirection
        return SCNVector3(v.x * sphereRadius, v.y * sphereRadius, v.z * sphereRadius)
    }

    // MARK: - Internal helpers

    private static func billboard() -> SCNBillboardConstraint {
        let b = SCNBillboardConstraint()
        b.freeAxes = .all
        return b
    }

    /// A flat, solid-colour planet disc for bodies without a bundled hero model.
    /// `.constant` shading shows the colour at its true value — no directional
    /// light multiplication, so it can never bloom out to white.
    private static func makePlanetGlobe(named name: String, radius: CGFloat) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 48
        sphere.isGeodesic = false

        let mat = SCNMaterial()
        mat.diffuse.contents = planetBaseColor(named: name)
        mat.lightingModel = .constant
        mat.metalness.contents = 0.0
        mat.roughness.contents = 1.0
        mat.specular.contents = UIColor.black
        mat.emission.contents = nil
        sphere.firstMaterial = mat

        return SCNNode(geometry: sphere)
    }

    /// Representative surface colour per planet (moderate reflectances, opaque) for
    /// the solid-disc fallback. Kept slightly muted so the disc stays a calm dot.
    private static func planetBaseColor(named name: String) -> UIColor {
        switch name {
        case "Mercury": return UIColor(red: 0.62, green: 0.58, blue: 0.52, alpha: 1)
        case "Venus":   return UIColor(red: 0.85, green: 0.78, blue: 0.58, alpha: 1)
        case "Mars":    return UIColor(red: 0.78, green: 0.34, blue: 0.22, alpha: 1)
        case "Jupiter": return UIColor(red: 0.80, green: 0.66, blue: 0.48, alpha: 1)
        case "Saturn":  return UIColor(red: 0.80, green: 0.71, blue: 0.52, alpha: 1)
        case "Uranus":  return UIColor(red: 0.55, green: 0.78, blue: 0.82, alpha: 1)
        case "Neptune": return UIColor(red: 0.30, green: 0.42, blue: 0.78, alpha: 1)
        default:        return UIColor(red: 0.60, green: 0.60, blue: 0.62, alpha: 1)
        }
    }

    private static func makeAdditiveMaterial(image: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.blendMode = .add
        return m
    }

    private static func makeAlphaMaterial(image: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.blendMode = .alpha
        return m
    }

    private static func starSize(forMagnitude mag: Double) -> Float {
        let m = Float(max(-1.5, min(6.0, mag)))
        let size = 2.4 - (m + 1.5) * (1.85 / 6.5)
        return max(0.55, size)
    }

    private static let mapStarVisualRadius: Float = 0.18
    private static let mapStarHitTargetRadius: Float = 0.95

    private static func planetSize(for name: String) -> CGFloat {
        switch name {
        case "Jupiter": return 4.4
        case "Venus":   return 4.0
        case "Saturn":  return 4.0
        case "Mars":    return 3.4
        case "Mercury": return 2.6
        default:        return 3.0
        }
    }

    private static func starTint(for object: CelestialObject) -> UIColor {
        let colorMap: [String: UIColor] = [
            "betelgeuse": UIColor(red: 1.00, green: 0.62, blue: 0.45, alpha: 1),
            "antares":    UIColor(red: 1.00, green: 0.55, blue: 0.40, alpha: 1),
            "aldebaran":  UIColor(red: 1.00, green: 0.72, blue: 0.50, alpha: 1),
            "arcturus":   UIColor(red: 1.00, green: 0.78, blue: 0.55, alpha: 1),
            "pollux":     UIColor(red: 1.00, green: 0.82, blue: 0.62, alpha: 1),
            "capella":    UIColor(red: 1.00, green: 0.95, blue: 0.78, alpha: 1),
            "vega":       UIColor(red: 0.85, green: 0.93, blue: 1.00, alpha: 1),
            "sirius":     UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1),
            "rigel":      UIColor(red: 0.78, green: 0.88, blue: 1.00, alpha: 1),
            "spica":      UIColor(red: 0.78, green: 0.88, blue: 1.00, alpha: 1),
            "deneb":      UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1),
            "altair":     UIColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 1),
            "polaris":    UIColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 1),
        ]
        return colorMap[object.id] ?? UIColor(white: 1.0, alpha: 1.0)
    }

    private static func nextRandom(_ seed: inout UInt64) -> Double {
        seed ^= seed >> 12
        seed ^= seed << 25
        seed ^= seed >> 27
        let result = seed &* 2_685_821_657_736_338_717
        return Double(result >> 11) / Double(1 << 53)
    }

    // MARK: - Labels

    static func makeLabel(text: String, style: LabelStyle, yOffset: Float) -> SCNNode {
        let image = SpriteCache.label(text: text, style: style)
        // Scene-units per texture point, chosen per style so the visual hierarchy
        // is: planets/bodies > constellations > stars. Smaller divisor = bigger.
        let scale: CGFloat
        switch style {
        case .planet, .body:   scale = 1.0 / 42.0
        case .constellation:   scale = 1.0 / 40.0
        case .cardinal:        scale = 1.0 / 34.0
        case .star:            scale = 1.0 / 54.0
        }
        let plane = SCNPlane(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        plane.firstMaterial = makeAlphaMaterial(image: image)
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, yOffset, 0)
        node.constraints = [billboard()]      // ← always faces the camera (0,0,0)
        node.renderingOrder = 80              // drawn after bodies → never occluded
        return node
    }

    /// Reusable labeling entry point. Attaches a billboarded name label to `node`,
    /// placed just *below* the body, at a constant on-sphere size that is
    /// INDEPENDENT of any scale applied to the body's visual (so a normalized
    /// .usdz model can't shrink/blow up its own label).
    ///
    /// - Parameters:
    ///   - node: the (unscaled) container the label is parented to.
    ///   - text: the display name.
    ///   - style: typography preset (.planet / .body / .star / .constellation / .cardinal).
    ///   - bodyRadius: on-sphere radius of the body in scene units, used to offset
    ///     the label clear of the model.
    @discardableResult
    static func addLabel(
        to node: SCNNode,
        text: String,
        style: LabelStyle,
        bodyRadius: Float = 0
    ) -> SCNNode {
        let yOffset = -(bodyRadius * 1.35 + 1.4)   // a constant gap under the body
        let label = makeLabel(text: text, style: style, yOffset: yOffset)
        node.addChildNode(label)
        return label
    }
}

// MARK: - Sprite cache

private enum SpriteCache {

    private static let cache = NSCache<NSString, UIImage>()

    static func starGlow(tint: UIColor, bright: Bool) -> UIImage {
        let key = "starglow_\(tint.cacheKey)_\(bright)" as NSString
        if let img = cache.object(forKey: key) { return img }
        let size = bright ? 192 : 128
        let img = drawWithContext(size: size) { ctx, dim in
            drawRadialGradient(
                ctx: ctx, size: dim,
                colors: [
                    tint.withAlphaComponent(1.0),
                    tint.withAlphaComponent(0.65),
                    tint.withAlphaComponent(0.0)
                ],
                locations: [0.0, 0.30, 1.0]
            )
            if bright {
                ctx.saveGState()
                ctx.setBlendMode(.plusLighter)
                ctx.setStrokeColor(tint.withAlphaComponent(0.55).cgColor)
                ctx.setLineWidth(CGFloat(dim) * 0.018)
                ctx.setLineCap(.round)
                let center = CGFloat(dim) / 2
                let spike = CGFloat(dim) * 0.46
                ctx.move(to: CGPoint(x: center - spike, y: center))
                ctx.addLine(to: CGPoint(x: center + spike, y: center))
                ctx.move(to: CGPoint(x: center, y: center - spike))
                ctx.addLine(to: CGPoint(x: center, y: center + spike))
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
        cache.setObject(img, forKey: key)
        return img
    }

    static func backgroundStar() -> UIImage {
        let key: NSString = "bgstar"
        if let img = cache.object(forKey: key) { return img }
        let img = drawWithContext(size: 48) { ctx, dim in
            drawRadialGradient(
                ctx: ctx, size: dim,
                colors: [
                    UIColor(white: 1.0, alpha: 0.75),
                    UIColor(white: 1.0, alpha: 0.15),
                    UIColor(white: 1.0, alpha: 0.0)
                ],
                locations: [0.0, 0.35, 1.0]
            )
        }
        cache.setObject(img, forKey: key)
        return img
    }

    static func sun() -> UIImage {
        let key: NSString = "sun"
        if let img = cache.object(forKey: key) { return img }
        let img = drawWithContext(size: 256) { ctx, dim in
            drawRadialGradient(
                ctx: ctx, size: dim,
                colors: [
                    UIColor(red: 1.00, green: 0.90, blue: 0.55, alpha: 1.0),
                    UIColor(red: 1.00, green: 0.78, blue: 0.30, alpha: 0.55),
                    UIColor(red: 1.00, green: 0.65, blue: 0.20, alpha: 0.0)
                ],
                locations: [0.0, 0.16, 1.0]
            )
            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            let center = CGFloat(dim) / 2
            let coreR = CGFloat(dim) * 0.12
            ctx.setFillColor(UIColor(white: 1.0, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: center - coreR, y: center - coreR,
                width: coreR * 2, height: coreR * 2
            ))
            ctx.restoreGState()
        }
        cache.setObject(img, forKey: key)
        return img
    }

    static func moon(phaseIllumination: Double, waxing: Bool) -> UIImage {
        let bucket = Int((phaseIllumination * 16.0).rounded())
        let key = "moon_\(bucket)_\(waxing)" as NSString
        if let img = cache.object(forKey: key) { return img }
        let img = drawWithContext(size: 256) { ctx, dim in
            let center = CGFloat(dim) / 2
            let diskR = CGFloat(dim) * 0.32
            drawRadialGradient(
                ctx: ctx, size: dim,
                colors: [
                    UIColor(white: 0.95, alpha: 0.65),
                    UIColor(white: 0.92, alpha: 0.18),
                    UIColor(white: 0.92, alpha: 0.0)
                ],
                locations: [0.20, 0.40, 1.0]
            )
            ctx.saveGState()
            let disc = CGRect(x: center - diskR, y: center - diskR, width: diskR * 2, height: diskR * 2)
            ctx.addEllipse(in: disc)
            ctx.clip()
            ctx.setFillColor(UIColor(red: 0.93, green: 0.92, blue: 0.86, alpha: 1.0).cgColor)
            ctx.fill(disc)
            if phaseIllumination < 0.97 {
                ctx.setFillColor(UIColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1.0).cgColor)
                let dx = (1.0 - 2.0 * CGFloat(phaseIllumination)) * diskR
                let direction: CGFloat = waxing ? -1 : 1
                let shadowRect = CGRect(
                    x: center + direction * dx - diskR,
                    y: center - diskR,
                    width: diskR * 2,
                    height: diskR * 2
                )
                ctx.fillEllipse(in: shadowRect)
            }
            ctx.restoreGState()
        }
        cache.setObject(img, forKey: key)
        return img
    }

    static func planet(named name: String) -> UIImage {
        let key = "planet_\(name)" as NSString
        if let img = cache.object(forKey: key) { return img }
        let (core, glow, hasRing): (UIColor, UIColor, Bool) = {
            switch name {
            case "Mercury":
                return (UIColor(red: 0.85, green: 0.80, blue: 0.70, alpha: 1),
                        UIColor(red: 0.85, green: 0.80, blue: 0.70, alpha: 0.45), false)
            case "Venus":
                return (UIColor(red: 1.00, green: 0.92, blue: 0.70, alpha: 1),
                        UIColor(red: 1.00, green: 0.92, blue: 0.70, alpha: 0.55), false)
            case "Mars":
                return (UIColor(red: 1.00, green: 0.42, blue: 0.26, alpha: 1),
                        UIColor(red: 1.00, green: 0.42, blue: 0.26, alpha: 0.45), false)
            case "Jupiter":
                return (UIColor(red: 1.00, green: 0.82, blue: 0.58, alpha: 1),
                        UIColor(red: 1.00, green: 0.78, blue: 0.50, alpha: 0.45), false)
            case "Saturn":
                return (UIColor(red: 0.96, green: 0.85, blue: 0.62, alpha: 1),
                        UIColor(red: 0.96, green: 0.85, blue: 0.62, alpha: 0.40), true)
            case "Uranus":
                return (UIColor(red: 0.65, green: 0.86, blue: 0.90, alpha: 1),
                        UIColor(red: 0.65, green: 0.86, blue: 0.90, alpha: 0.45), false)
            case "Neptune":
                return (UIColor(red: 0.45, green: 0.55, blue: 0.95, alpha: 1),
                        UIColor(red: 0.45, green: 0.55, blue: 0.95, alpha: 0.45), false)
            default:
                return (.white, UIColor(white: 1, alpha: 0.4), false)
            }
        }()
        let img = drawWithContext(size: 256) { ctx, dim in
            drawRadialGradient(
                ctx: ctx, size: dim,
                colors: [
                    core.withAlphaComponent(0.95),
                    glow,
                    core.withAlphaComponent(0.0)
                ],
                locations: [0.0, 0.30, 1.0]
            )
            let center = CGFloat(dim) / 2
            let r = CGFloat(dim) * 0.20
            ctx.saveGState()
            ctx.setFillColor(core.cgColor)
            ctx.fillEllipse(in: CGRect(x: center - r, y: center - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
            if hasRing {
                ctx.saveGState()
                ctx.translateBy(x: center, y: center)
                ctx.rotate(by: -0.35)
                ctx.setBlendMode(.plusLighter)
                let outerR: CGFloat = r * 2.05
                let ringRect = CGRect(
                    x: -outerR, y: -outerR * 0.28,
                    width: outerR * 2, height: outerR * 0.56
                )
                ctx.setStrokeColor(UIColor(red: 0.95, green: 0.86, blue: 0.65, alpha: 0.85).cgColor)
                ctx.setLineWidth(2.4)
                ctx.strokeEllipse(in: ringRect)
                ctx.setStrokeColor(UIColor(red: 0.95, green: 0.86, blue: 0.65, alpha: 0.40).cgColor)
                ctx.setLineWidth(1.0)
                ctx.strokeEllipse(in: ringRect.insetBy(dx: -2.5, dy: -0.8))
                ctx.restoreGState()
            }
        }
        cache.setObject(img, forKey: key)
        return img
    }

    static func halo() -> UIImage {
        let key: NSString = "halo"
        if let img = cache.object(forKey: key) { return img }
        let img = drawWithContext(size: 256) { ctx, dim in
            drawRadialGradient(
                ctx: ctx, size: dim,
                colors: [
                    UIColor(white: 1.0, alpha: 0.0),
                    UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.65),
                    UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.0)
                ],
                locations: [0.0, 0.46, 0.62]
            )
        }
        cache.setObject(img, forKey: key)
        return img
    }

    static func label(text: String, style: SkyNodeFactory.LabelStyle) -> UIImage {
        let key = "label_\(style)_\(text)" as NSString
        if let img = cache.object(forKey: key) { return img }
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = CGSize(width: 0, height: 0)
        let attrs: [NSAttributedString.Key: Any]
        // `pill` = draw a semi-transparent rounded background behind the text so
        // bright bodies' names stay legible over the busy 8K starfield.
        let pill: Bool
        switch style {
        case .star:
            attrs = [
                .font: UIFont.systemFont(ofSize: 26, weight: .medium),
                .foregroundColor: UIColor(white: 0.94, alpha: 0.95),
                .shadow: shadow,
                .kern: 0.4
            ]
            pill = false
        case .planet:
            attrs = [
                .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                .foregroundColor: UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0),
                .shadow: shadow,
                .kern: 0.6
            ]
            pill = true
        case .body:
            attrs = [
                .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                .foregroundColor: UIColor(white: 1.0, alpha: 1.0),
                .shadow: shadow,
                .kern: 0.6
            ]
            pill = true
        case .constellation:
            attrs = [
                .font: UIFont.systemFont(ofSize: 30, weight: .light),
                .foregroundColor: UIColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 0.88),
                .shadow: shadow,
                .kern: 3.0
            ]
            pill = false
        case .cardinal:
            attrs = [
                .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: UIColor(red: 0.95, green: 0.55, blue: 0.45, alpha: 0.95),
                .shadow: shadow,
                .kern: 1.0
            ]
            pill = false
        }
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let bounds = attributed.boundingRect(
            with: CGSize(width: 1024, height: 256),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let padX: CGFloat = pill ? 26 : 16
        let padY: CGFloat = pill ? 14 : 12
        let size = CGSize(
            width: ceil(bounds.width) + padX * 2,
            height: ceil(bounds.height) + padY * 2
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            if pill {
                // Rounded translucent backdrop to "lift" the name off the sky.
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height * 0.32)
                UIColor(white: 0.0, alpha: 0.42).setFill()
                path.fill()
            }
            attributed.draw(at: CGPoint(x: padX, y: padY))
        }
        cache.setObject(img, forKey: key)
        return img
    }

    private static func drawWithContext(
        size: Int,
        body: (CGContext, Int) -> Void
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { rendererCtx in
            body(rendererCtx.cgContext, size)
        }
    }

    private static func drawRadialGradient(
        ctx: CGContext,
        size: Int,
        colors: [UIColor],
        locations: [CGFloat]
    ) {
        let space = CGColorSpaceCreateDeviceRGB()
        let cgColors = colors.map { $0.cgColor } as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: cgColors, locations: locations)!
        let center = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: CGFloat(size) / 2,
            options: []
        )
    }
}

private extension UIColor {
    var cacheKey: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.2f-%.2f-%.2f-%.2f", r, g, b, a)
    }
}

extension SCNVector3 {
    init(_ v: SIMD3<Float>) { self.init(v.x, v.y, v.z) }
}
