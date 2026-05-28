//
//  ModelLoader.swift
//  Himmel
//
//  Asynchronous loader for complex hero models (e.g. a detailed Saturn-with-rings
//  or a comet from https://sketchfab.com/tags/planets). Parsing a .usdz/.scn can
//  take tens of milliseconds — doing it on the main thread would stutter the
//  render loop, so we parse off-thread and hand back a ready-to-insert node.
//
//  Usage pattern (placeholder → swap):
//      1. Renderer shows a cheap procedural sphere immediately.
//      2. Renderer kicks off `ModelLoader.shared.load(named:)`.
//      3. When the node arrives, the renderer swaps the placeholder for it.
//

import SceneKit

/// Serializes model parsing off the main actor and caches results.
actor ModelLoader {

    static let shared = ModelLoader()

    /// Flattened, reusable template nodes keyed by resource name.
    private var cache: [String: SCNNode] = [:]

    /// Load a bundled model (.usdz / .scn / .gltf-as-scn) by base resource name.
    /// Returns a *clone* so callers can mutate transform/position freely.
    /// Returns `nil` if the resource isn't bundled (caller keeps its placeholder).
    func load(named name: String, fileExtensions: [String] = ["usdz", "scn"]) -> SCNNode? {
        if let cached = cache[name] {
            return cached.clone()
        }
        guard let url = Self.resolveURL(name: name, extensions: fileExtensions),
              let scene = try? SCNScene(url: url, options: [
                  .checkConsistency: false,
                  // Convert to SceneKit's unit/axis conventions on import.
                  .convertToYUp: true,
                  .createNormalsIfAbsent: true
              ]) else {
            return nil
        }

        // Collapse the imported hierarchy into a single template node.
        let template = SCNNode()
        for child in scene.rootNode.childNodes {
            template.addChildNode(child)
        }
        // Force-decode geometry/textures now (still off the main actor) so the
        // first on-screen frame doesn't pay the upload cost.
        template.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { _ = $0.diffuse.contents }
        }

        cache[name] = template
        return template.clone()
    }

    private static func resolveURL(name: String, extensions: [String]) -> URL? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
