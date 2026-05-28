//
//  ProceduralStarRenderer.swift
//  Himmel
//
//  Code-generated stellar renderer for stars and the Sun. Static mesh assets are
//  too opaque and edge-defined for stars, so this renderer builds a high-density
//  emissive sphere, overdrives its emission channel, and relies on camera bloom
//  to create the soft glare that hides the mathematical sphere edge.
//

import SceneKit
import UIKit

enum StellarClassification: String, Hashable {
    case yellowDwarf
    case redGiant
    case redSupergiant
    case blueWhite
    case blueSupergiant
    case whiteDwarf
    case whiteMainSequence

    var tint: UIColor {
        switch self {
        case .yellowDwarf:
            return UIColor(red: 1.00, green: 0.95, blue: 0.64, alpha: 1.0) // #FFF2A3
        case .redGiant:
            return UIColor(red: 1.00, green: 0.42, blue: 0.24, alpha: 1.0)
        case .redSupergiant:
            return UIColor(red: 1.00, green: 0.36, blue: 0.23, alpha: 1.0) // #FF5B3B
        case .blueWhite:
            return UIColor(red: 0.74, green: 0.84, blue: 1.00, alpha: 1.0)
        case .blueSupergiant:
            return UIColor(red: 0.65, green: 0.78, blue: 0.97, alpha: 1.0) // #A5C7F7
        case .whiteDwarf, .whiteMainSequence:
            return UIColor(red: 0.94, green: 0.97, blue: 1.00, alpha: 1.0)
        }
    }

    var displayName: String {
        switch self {
        case .yellowDwarf: return "Yellow dwarf"
        case .redGiant: return "Red giant"
        case .redSupergiant: return "Red supergiant"
        case .blueWhite: return "Blue-white star"
        case .blueSupergiant: return "Blue supergiant"
        case .whiteDwarf: return "White dwarf"
        case .whiteMainSequence: return "White main-sequence star"
        }
    }

    var radiusScale: Float {
        switch self {
        case .yellowDwarf: return 1.0
        case .redGiant: return 1.35
        case .redSupergiant: return 1.75
        case .blueWhite: return 1.15
        case .blueSupergiant: return 1.55
        case .whiteDwarf: return 0.55
        case .whiteMainSequence: return 0.90
        }
    }

    var emissionIntensity: CGFloat {
        switch self {
        case .redGiant, .redSupergiant: return 3.1
        case .blueSupergiant: return 3.8
        case .blueWhite: return 3.4
        case .whiteDwarf: return 2.8
        case .whiteMainSequence: return 3.0
        case .yellowDwarf: return 3.5
        }
    }

    static func infer(from object: CelestialObject) -> StellarClassification {
        guard object.type != .sun else { return .yellowDwarf }

        let id = object.id.lowercased()
        let text = "\(object.name) \(object.subtitle) \(object.summary) \(object.facts.joined(separator: " "))"
            .lowercased()

        if ["betelgeuse", "antares"].contains(id) || text.contains("red supergiant") {
            return .redSupergiant
        }
        if text.contains("red giant") || text.contains("orange giant") || text.contains("orange supergiant") {
            return .redGiant
        }
        if text.contains("blue supergiant") {
            return .blueSupergiant
        }
        if text.contains("blue-white") || text.contains("hot blue") || text.contains("blue giant") {
            return .blueWhite
        }
        if text.contains("white dwarf") {
            return .whiteDwarf
        }
        if text.contains("white main-sequence") || text.contains("a-type") || text.contains("f-type") {
            return .whiteMainSequence
        }
        return .yellowDwarf
    }
}

enum ProceduralStarRenderer {
    struct BloomProfile {
        let intensity: CGFloat
        let threshold: CGFloat
        let blurRadius: CGFloat

        static let sky = BloomProfile(intensity: 1.45, threshold: 0.92, blurRadius: 18)
        static let preview = BloomProfile(intensity: 1.75, threshold: 0.88, blurRadius: 22)
        static let ar = BloomProfile(intensity: 1.65, threshold: 0.90, blurRadius: 20)
    }

    static func makeStarNode(
        for object: CelestialObject,
        radius: Float,
        nodeName: String? = nil,
        position: SCNVector3? = nil,
        segmentCount: Int = 64,
        includeHalo: Bool = true,
        appliesClassificationScale: Bool = true,
        hitTargetRadius: Float? = nil
    ) -> SCNNode {
        let classification = StellarClassification.infer(from: object)
        let finalRadius = radius * (appliesClassificationScale ? classification.radiusScale : 1)

        let container = SCNNode()
        container.name = nodeName
        if let position {
            container.position = position
        }
        container.renderingOrder = 60

        let sphere = SCNSphere(radius: CGFloat(finalRadius))
        sphere.segmentCount = max(48, segmentCount)
        sphere.isGeodesic = false
        sphere.firstMaterial = makeCoreMaterial(for: classification)

        let core = SCNNode(geometry: sphere)
        core.name = "stellar-core"
        core.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 100)))
        container.addChildNode(core)

        if let hitTargetRadius {
            container.addChildNode(makeHitTarget(radius: max(hitTargetRadius, finalRadius)))
        }

        if includeHalo {
            container.addChildNode(makeHalo(size: CGFloat(finalRadius * 5.6),
                                           tint: classification.tint,
                                           alpha: 0.42))
            container.addChildNode(makeHalo(size: CGFloat(finalRadius * 9.0),
                                           tint: classification.tint,
                                           alpha: 0.18))
        }

        return container
    }

    static func configureBloom(on camera: SCNCamera?, profile: BloomProfile) {
        guard let camera else { return }
        camera.wantsHDR = true
        camera.bloomIntensity = profile.intensity
        camera.bloomThreshold = profile.threshold
        camera.bloomBlurRadius = profile.blurRadius
        camera.exposureOffset = 0
    }

    private static func makeCoreMaterial(for classification: StellarClassification) -> SCNMaterial {
        let texture = StellarTextureCache.surfaceTexture(for: classification)

        let material = SCNMaterial()
        material.diffuse.contents = texture
        material.diffuse.intensity = 1.35
        material.emission.contents = texture
        material.emission.intensity = classification.emissionIntensity
        material.multiply.contents = classification.tint
        material.lightingModel = .constant
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        material.isDoubleSided = false
        return material
    }

    private static func makeHalo(size: CGFloat, tint: UIColor, alpha: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.diffuse.contents = StellarTextureCache.haloTexture(tint: tint, alpha: alpha)
        material.emission.contents = tint.withAlphaComponent(alpha)
        material.emission.intensity = 2.0
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.blendMode = .add
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        node.renderingOrder = 59
        return node
    }

    private static func makeHitTarget(radius: Float) -> SCNNode {
        let sphere = SCNSphere(radius: CGFloat(radius))
        sphere.segmentCount = 16

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.clear
        material.transparency = 0.001
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        sphere.firstMaterial = material

        let node = SCNNode(geometry: sphere)
        node.name = "stellar-hit-target"
        node.renderingOrder = -100
        return node
    }
}

private enum StellarTextureCache {
    private static var surfaceCache: [StellarClassification: UIImage] = [:]
    private static var haloCache: [String: UIImage] = [:]

    static func surfaceTexture(for classification: StellarClassification) -> UIImage {
        if let cached = surfaceCache[classification] { return cached }
        if let bundled = UIImage(named: "tex_sun_diffuse") {
            surfaceCache[classification] = bundled
            return bundled
        }

        let generated = makeProceduralSurface(tint: classification.tint)
        surfaceCache[classification] = generated
        return generated
    }

    static func haloTexture(tint: UIColor, alpha: CGFloat) -> UIImage {
        let key = "\(tint.description)-\(alpha)"
        if let cached = haloCache[key] { return cached }

        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                tint.withAlphaComponent(alpha).cgColor,
                tint.withAlphaComponent(alpha * 0.30).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.36, 1.0]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors,
                                      locations: locations)!
            cg.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: 0,
                endCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                endRadius: size.width / 2,
                options: [.drawsAfterEndLocation]
            )
        }
        haloCache[key] = image
        return image
    }

    private static func makeProceduralSurface(tint: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            var seed: UInt64 = 0x5354_4152_5F48_4452
            for _ in 0..<2200 {
                let x = CGFloat(nextRandom(&seed)) * size.width
                let y = CGFloat(nextRandom(&seed)) * size.height
                let w = CGFloat(2.0 + nextRandom(&seed) * 10.0)
                let hot = CGFloat(0.72 + nextRandom(&seed) * 0.28)
                let color = blend(tint, with: .white, amount: hot).withAlphaComponent(0.34)
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: w, height: w * 0.58))
            }

            for _ in 0..<120 {
                let y = CGFloat(nextRandom(&seed)) * size.height
                let h = CGFloat(0.7 + nextRandom(&seed) * 2.2)
                cg.setFillColor(tint.withAlphaComponent(0.10).cgColor)
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: h))
            }
        }
    }

    private static func blend(_ a: UIColor, with b: UIColor, amount: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * amount,
            green: ag + (bg - ag) * amount,
            blue: ab + (bb - ab) * amount,
            alpha: aa + (ba - aa) * amount
        )
    }

    private static func nextRandom(_ seed: inout UInt64) -> Double {
        seed ^= seed >> 12
        seed ^= seed << 25
        seed ^= seed >> 27
        let result = seed &* 2_685_821_657_736_338_717
        return Double(result & 0xFFFF) / Double(0xFFFF)
    }
}
