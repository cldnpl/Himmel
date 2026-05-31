//
//  CelestialBodyFactory.swift
//  Himmel
//
//  Builds 3D *textured* bodies (Sun / Moon / planets) as programmatic low-poly
//  spheres, binding the equirectangular maps from Solar System Scope
//  (https://www.solarsystemscope.com/textures/) — Diffuse, Normal, Specular.
//
//  Asset naming convention (add the PNGs to Assets.xcassets with these names):
//      tex_<key>_diffuse     (required — colour map)
//      tex_<key>_normal      (optional — surface relief / bump)
//      tex_<key>_specular    (optional — light reflection mask)
//      tex_<key>_ring        (optional — Saturn ring slice, alpha cutout)
//
//  where <key> ∈ { sun, mercury, venus, earth, moon, mars, jupiter, saturn, ... }
//
//  Graceful degradation: if the required diffuse texture is missing, the
//  factory returns `nil` and the renderer falls back to the additive sprite.
//

import SceneKit
import UIKit

enum CelestialBodyFactory {

    /// Segment count for the generated spheres. Low enough to stay cheap on
    /// mobile, high enough to look smooth at the small on-sphere size.
    private static let sphereSegments: Int = 48

    /// Build a textured 3D body node, or `nil` if no diffuse texture is bundled.
    ///
    /// - The Sun is rendered *unlit* (emissive) — it is the light source.
    /// - Moon and planets use a Blinn material so the scene's directional
    ///   "sunlight" produces physically correct phases automatically.
    static func texturedBody(
        bodyName: String,
        type: CelestialObjectType,
        radius: CGFloat,
        nodeName: String
    ) -> SCNNode? {
        let key = textureKey(for: bodyName)
        guard let diffuse = UIImage(named: "tex_\(key)_diffuse") else { return nil }

        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = sphereSegments
        sphere.isGeodesic = false

        let mat = SCNMaterial()
        mat.diffuse.contents = diffuse

        if type == .sun {
            // The Sun emits light; render it unlit + emissive so it stays bright
            // regardless of scene lighting, and never sits in its own shadow.
            mat.lightingModel = .constant
            mat.emission.contents = diffuse
            mat.writesToDepthBuffer = true
        } else {
            // Matte lit body — relief from the normal map, but NO specular glint
            // or environment reflection (planets/the Moon are not glossy).
            if let normal = UIImage(named: "tex_\(key)_normal") {
                mat.normal.contents = normal
                mat.normal.intensity = 0.85
            }
            applyMatteSurface(to: mat)
            mat.writesToDepthBuffer = true
        }
        sphere.firstMaterial = mat

        let container = SCNNode()
        container.name = nodeName

        let body = SCNNode(geometry: sphere)
        // Orient the texture's north pole toward +Z (scene "up"). SCNSphere's
        // poles are on its local Y axis, so tilt -90° about X to map Y→Z.
        body.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        // Gentle axial spin for life (purely cosmetic).
        body.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: .pi * 2, duration: 90)))
        container.addChildNode(body)

        // Saturn-style ring, if a ring slice texture is provided.
        if let ring = UIImage(named: "tex_\(key)_ring") {
            container.addChildNode(makeRingNode(texture: ring, planetRadius: radius))
        }

        return container
    }

    // MARK: - Matte surface

    /// Make a body material MATTE: pure diffuse response, no specular highlight
    /// and no environment (image-based) reflection. This is what removes the
    /// "shiny plastic / white luminous film" from lit planets and the Moon —
    /// both on the star map and in AR, where ARKit's automatic environment probe
    /// would otherwise reflect off the imported PBR (`.physicallyBased`)
    /// materials. The diffuse colour and normal/relief maps are left intact.
    ///
    /// Do NOT call this on the Sun: it must stay emissive `.constant`.
    static func applyMatteSurface(to material: SCNMaterial) {
        material.lightingModel = .lambert          // diffuse only — no specular term
        material.metalness.contents = 0.0          // neutralize any imported PBR metal
        material.roughness.contents = 1.0          // fully rough → no sharp reflection
        material.specular.contents = UIColor.black // belt-and-suspenders for blinn/phong
        material.reflective.contents = nil         // no environment mirror / IBL sheen
        material.emission.contents = nil           // no self-glow / double-exposure
    }

    // MARK: - Ring

    /// A flat, double-sided annulus textured with an alpha-cutout ring slice.
    /// Cheaper and sharper than a full ring mesh; tilts to mimic Saturn's tilt.
    private static func makeRingNode(texture: UIImage, planetRadius: CGFloat) -> SCNNode {
        let inner = planetRadius * 1.25
        let outer = planetRadius * 2.30
        let ringPlane = SCNPlane(width: outer * 2, height: outer * 2)

        let mat = SCNMaterial()
        mat.diffuse.contents = texture
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        mat.writesToDepthBuffer = false
        ringPlane.firstMaterial = mat

        let node = SCNNode(geometry: ringPlane)
        // Lay it flat (in the planet's equatorial plane) and apply ~26.7° tilt.
        node.eulerAngles = SCNVector3(-Float.pi / 2 + 0.466, 0, 0)
        _ = inner // documented intent; SCNPlane uses the texture's transparency
        return node
    }

    // MARK: - Texture key

    /// Maps a display name ("Mars") to a texture asset key ("mars").
    private static func textureKey(for name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }
}
