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
        case star, planet, body, constellation
    }

    // MARK: - Stars

    static func makeStar(resolved: ResolvedSkyObject) -> SCNNode {
        let container = SCNNode()
        container.name = nodeNamePrefix + resolved.id
        container.position = position(for: resolved.horizontal)
        container.constraints = [billboard()]
        container.renderingOrder = 10

        let mag = resolved.object.magnitude ?? 3.0
        let size = starSize(forMagnitude: mag)
        let tint = starTint(for: resolved.object)

        let glowPlane = SCNPlane(width: CGFloat(size), height: CGFloat(size))
        glowPlane.firstMaterial = makeAdditiveMaterial(
            image: SpriteCache.starGlow(tint: tint, bright: mag < 1.2)
        )
        container.addChildNode(SCNNode(geometry: glowPlane))

        // Label — only on brighter stars to keep the chart legible.
        if mag < 3.6 {
            let label = makeLabel(
                text: resolved.object.name,
                style: .star,
                yOffset: -Float(size) * 0.65
            )
            container.addChildNode(label)
        }
        return container
    }

    // MARK: - Sun / Moon / planets

    static func makeBody(resolved: ResolvedSkyObject, moonPhase: MoonPhase.Snapshot?) -> SCNNode {
        let container = SCNNode()
        container.name = nodeNamePrefix + resolved.id
        container.position = position(for: resolved.horizontal)
        container.constraints = [billboard()]
        container.renderingOrder = 50

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
        case .planet:
            sprite = SpriteCache.planet(named: resolved.object.name)
            size = planetSize(for: resolved.object.name)
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

        let label = makeLabel(
            text: resolved.object.name,
            style: resolved.object.type == .planet ? .planet : .body,
            yOffset: -Float(size) * 0.7
        )
        container.addChildNode(label)
        return container
    }

    // MARK: - Constellation lines + names

    static func makeConstellationGroup(
        _ constellation: Constellation,
        starPositions: [String: HorizontalCoordinate]
    ) -> SCNNode? {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        var i: Int32 = 0
        var anchorSum = SIMD3<Float>(0, 0, 0)
        var anchorCount: Float = 0
        for segment in constellation.lines {
            guard let a = starPositions[segment.starA],
                  let b = starPositions[segment.starB] else { continue }
            guard a.altitudeDegrees > -3 && b.altitudeDegrees > -3 else { continue }
            let pa = position(for: a)
            let pb = position(for: b)
            vertices.append(pa)
            vertices.append(pb)
            indices.append(i); indices.append(i + 1); i += 2
            anchorSum += SIMD3<Float>(pa.x, pa.y, pa.z)
            anchorSum += SIMD3<Float>(pb.x, pb.y, pb.z)
            anchorCount += 2
        }
        guard !indices.isEmpty else { return nil }

        let group = SCNNode()
        group.name = "constellation:\(constellation.id)"

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
        lineGeom.firstMaterial = lineMat
        let lineNode = SCNNode(geometry: lineGeom)
        lineNode.renderingOrder = -50
        group.addChildNode(lineNode)

        if anchorCount > 0 {
            let centroid = simd_normalize(anchorSum / anchorCount) * sphereRadius
            let labelNode = makeLabel(
                text: constellation.name.uppercased(),
                style: .constellation,
                yOffset: 0
            )
            labelNode.position = SCNVector3(centroid.x, centroid.y, centroid.z)
            labelNode.constraints = [billboard()]
            labelNode.renderingOrder = -40
            group.addChildNode(labelNode)
        }
        return group
    }

    // MARK: - Background filler stars

    static func makeBackgroundStars(count: Int = 600) -> SCNNode {
        let parent = SCNNode()
        var seed: UInt64 = 0xC0FF_EE_DE_AD_BE_EF
        let sprite = SpriteCache.backgroundStar()
        for _ in 0..<count {
            let u = nextRandom(&seed)
            let v = nextRandom(&seed)
            let theta = 2.0 * Float.pi * Float(u)
            let phi = acos(2.0 * Float(v) - 1.0)
            let dir = SIMD3<Float>(
                sin(phi) * cos(theta),
                sin(phi) * sin(theta),
                cos(phi)
            )
            let size = CGFloat(0.10 + 0.18 * Float(nextRandom(&seed)))
            let plane = SCNPlane(width: size, height: size)
            plane.firstMaterial = makeAdditiveMaterial(image: sprite)
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(
                dir.x * sphereRadius * 0.99,
                dir.y * sphereRadius * 0.99,
                dir.z * sphereRadius * 0.99
            )
            node.constraints = [billboard()]
            node.renderingOrder = -200
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
        let scale: CGFloat = 1.0 / 60.0
        let plane = SCNPlane(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        plane.firstMaterial = makeAlphaMaterial(image: image)
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, yOffset, 0)
        node.constraints = [billboard()]
        node.renderingOrder = 80
        return node
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
        switch style {
        case .star:
            attrs = [
                .font: UIFont.systemFont(ofSize: 22, weight: .regular),
                .foregroundColor: UIColor(white: 0.92, alpha: 0.95),
                .shadow: shadow,
                .kern: 0.4
            ]
        case .planet:
            attrs = [
                .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1.0),
                .shadow: shadow,
                .kern: 0.6
            ]
        case .body:
            attrs = [
                .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: UIColor(white: 1.0, alpha: 1.0),
                .shadow: shadow,
                .kern: 0.6
            ]
        case .constellation:
            attrs = [
                .font: UIFont.systemFont(ofSize: 28, weight: .light),
                .foregroundColor: UIColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 0.85),
                .shadow: shadow,
                .kern: 2.6
            ]
        }
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let bounds = attributed.boundingRect(
            with: CGSize(width: 1024, height: 256),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let pad: CGFloat = 14
        let size = CGSize(
            width: ceil(bounds.width) + pad * 2,
            height: ceil(bounds.height) + pad * 2
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { _ in
            attributed.draw(at: CGPoint(x: pad, y: pad))
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
