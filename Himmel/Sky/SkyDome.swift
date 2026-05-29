//
//  SkyDome.swift
//  Himmel
//
//  Builds the immersive star background as a giant INVERTED sphere (a sky dome)
//  rather than relying on `scene.background.contents`.
//
//  WHY NOT scene.background.contents = <single image>?
//  ────────────────────────────────────────────────────
//  SceneKit's `background.contents` expects either a 6-image cube map or a
//  proper 2:1 equirectangular panorama. Feeding it a single arbitrary photo
//  makes it sample the image along cube-face directions, which produces the
//  "tunnel / vortex" pinch and the black gaps the user is seeing: the pixels
//  converge to a focal point and large solid angles map to nothing.
//
//  THE FIX: map the equirectangular image onto the inner surface of a large
//  SCNSphere. With the camera locked at the sphere's centre (0,0,0) and only
//  rotating, the user always sees a seamless, distortion-free interior.
//

import SceneKit
import UIKit

enum SkyDome {

    /// Radius of the dome. Must be larger than the star sphere (≈50) so the dome
    /// sits behind every other object, and smaller than the camera's `zFar`.
    static let radius: CGFloat = 140

    /// KVC key for the shader uniform that toggles below-horizon clipping.
    /// 0 → full sphere (virtual / non-AR mode); 1 → only the sky hemisphere is
    /// drawn, the lower half fades out so the live camera (ground/buildings)
    /// shows through in AR Sky mode.
    static let horizonFadeKey = "horizonFade"

    /// Surface shader modifier that fades the dome out below the horizon.
    /// World +Z is up, so a fragment's world-space direction `.z` is sin(altitude):
    /// ≥0 above the horizon, <0 below. When `horizonFade` is 1 we smoothstep the
    /// alpha to zero just under the horizon line, confining the 360° backdrop to
    /// the sky exactly like the real celestial bodies. Runs in the SURFACE stage,
    /// where `u_inverseViewTransform` and `_surface.position` are both available
    /// (the transform uniforms are exposed via the `scn_frame` struct in modern
    /// SceneKit Metal; the legacy `u_inverseViewTransform` alias is undeclared and
    /// makes the shader fail to compile → magenta dome).
    private static let horizonClipModifier = """
    #pragma arguments
    float horizonFade;
    #pragma body
    float3 worldDir = normalize((scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz);
    float clipped = smoothstep(-0.04, 0.06, worldDir.z);
    float fade = mix(1.0, clipped, horizonFade);
    _surface.diffuse.a *= half(fade);
    """

    /// Build the sky-dome node.
    ///
    /// - Parameters:
    ///   - texture: the equirectangular star map (ideally 2:1). A non-2:1 photo
    ///     still maps cleanly — it just wraps with a single seam instead of
    ///     tunneling.
    ///   - rotationCCW: texture rotation in radians. The Milky Way source is
    ///     horizontal; +π/2 rotates it 90° counter-clockwise for portrait.
    /// - Parameters:
    ///   - texture: the equirectangular (2:1) "Stars + Milky Way" 8K map.
    ///   - rotationCCW: how much to spin the whole dome counter-clockwise so the
    ///     Milky Way reads well in portrait. Applied to the NODE, not the UVs —
    ///     this is free (no texel remap) and, crucially for an 8K texture, avoids
    ///     re-rasterising 130+ MB of pixels. Set to 0 to keep the map in its
    ///     astronomically-correct orientation.
    static func make(
        texture: UIImage,
        rotationCCW: Float = .pi / 2,
        brightness: CGFloat = 1.0
    ) -> SCNNode {

        // High segment count → the UV-sphere's poles converge over many tiny
        // triangles instead of a few large ones, which all but eliminates the
        // visible "pinching" artifact at the zenith and nadir.
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 128
        sphere.isGeodesic = false

        let material = SCNMaterial()
        material.diffuse.contents = texture

        // ── Unlit / emissive ────────────────────────────────────────────────
        // `.constant` ignores every light in the scene → the sky keeps constant
        // colour, never darkens, and skips lighting math for stable 60fps. This
        // is the "soft emotional backdrop": the Milky Way glow and background
        // star density come straight from the texture, untouched by scene lights.
        material.lightingModel = .constant
        material.writesToDepthBuffer = false   // never occludes / never z-fights
        material.readsFromDepthBuffer = false

        // ── Render the INNER surface ────────────────────────────────────────
        // SCNSphere normals face outward; we are inside it, so cull the front
        // (outer) faces and draw the back (inner) faces the camera actually sees.
        material.cullMode = .front
        material.isDoubleSided = false

        // ── Sampling / filtering (tuned for an 8K equirect) ─────────────────
        // wrapS = .repeat → longitude wraps seamlessly around 360°, so the map's
        //                   left/right edges meet with no visible seam.
        // wrapT = .clamp  → latitude clamps at the poles so the top/bottom rows
        //                   don't wrap back and mirror across the zenith/nadir.
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp

        // 8K means texels are ~1:1 with screen pixels, so magnification is no
        // longer the problem — minification is (lots of texels per pixel toward
        // the poles / during fast rotation). Trilinear + anisotropic 16× tames
        // that without blurring the centre of view.
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter  = .linear
        material.diffuse.mipFilter           = .linear   // builds mips → no shimmer
        material.diffuse.maxAnisotropy       = 16        // crisp at grazing angles

        // ── Brightness attenuation ──────────────────────────────────────────
        // Multiply the sampled texture by a grey so the backdrop reads as a
        // SUBTLE deep-space glow instead of overpowering the catalog stars.
        // brightness 1.0 = untouched, 0.4 ≈ 40% as bright. Done on the GPU sampler
        // (free), so the 8K texture is never re-rasterised.
        if brightness < 0.999 {
            material.multiply.contents = UIColor(white: brightness, alpha: 1.0)
        }

        // Below-horizon clipping (disabled by default; enabled in AR Sky mode).
        // Needs alpha blending so the faded lower half lets the camera through.
        material.blendMode = .alpha
        material.transparencyMode = .default
        material.shaderModifiers = [.surface: horizonClipModifier]
        material.setValue(NSNumber(value: 0.0), forKey: horizonFadeKey)

        sphere.firstMaterial = material

        let node = SCNNode(geometry: sphere)
        node.name = "skyDome"
        node.renderingOrder = -1000   // drawn FIRST, behind every other object
        node.castsShadow = false

        // ── 90° rotation via the NODE (memory-free, distortion-free) ────────
        // Rotating the dome around the viewing axis spins the whole sphere; the
        // texture is never re-sampled, so an 8K map costs nothing extra and the
        // poles stay clean (a UV rotation would swap lon/lat and stretch them).
        node.eulerAngles = SCNVector3(0, 0, rotationCCW)
        return node
    }
}
