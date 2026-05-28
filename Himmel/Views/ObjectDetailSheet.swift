//
//  ObjectDetailSheet.swift
//  Himmel
//
//  Glassmorphic detail card shown when the user taps a celestial object.
//  Contains a live 3D preview viewport, an AR Quick Look button, and a
//  type-dependent parameter grid.
//

import SwiftUI
import SceneKit

struct ObjectDetailSheet: View {

    let object: CelestialObject

    /// When set, presents the custom in-place AR model viewer.
    @State private var arPresentation: ARPresentation?

    /// Bundled .usdz for opaque bodies and the native Sun asset.
    private var modelURL: URL? {
        guard object.type == .sun || object.type == .planet || object.type == .moon else { return nil }
        return Bundle.main.url(forResource: object.name, withExtension: "usdz")
    }

    private var supportsAR: Bool {
        object.type == .star || modelURL != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBlock

                Divider()
                    .overlay(Color.white.opacity(0.14))   // thin, high-transparency

                // Long description
                Text(object.summary)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                parameterGrid
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fullScreenCover(item: $arPresentation) { presentation in
            ARModelView(modelURL: presentation.url, object: presentation.object, title: presentation.title) {
                arPresentation = nil
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Header (preview · name/desc · AR button)

    private var headerBlock: some View {
        HStack(alignment: .top, spacing: 16) {

            // 3D preview viewport — isolated SceneKit scene, no calibration grid.
            BodyPreview(object: object, modelURL: modelURL)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(object.name)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(object.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if supportsAR {
                arButton()
            }
        }
    }

    private func arButton() -> some View {
        Button {
            arPresentation = ARPresentation(url: modelURL, object: object, title: object.name)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "arkit")
                    .font(.system(size: 24, weight: .regular))
                Text("View in AR")
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(width: 86, height: 76)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dynamic parameter grid

    private var parameterGrid: some View {
        let params = DetailParameters.make(for: object)
        return Group {
            if !params.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(params, id: \.label) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.label.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(p.value)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.white.opacity(0.95))
                                .minimumScaleFactor(0.7)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct ARPresentation: Identifiable {
    let id = UUID()
    let url: URL?
    let object: CelestialObject
    let title: String
}

// MARK: - Type-dependent parameters

/// Flexible data model: maps a celestial object to the technical parameters
/// relevant for its kind (planet / star / constellation / …).
enum DetailParameters {
    struct Item { let label: String; let value: String }

    nonisolated static func make(for object: CelestialObject) -> [Item] {
        switch object.type {
        case .planet, .moon:
            // The ephemeris layer already produced "Label: value" facts.
            return object.facts.compactMap(split)
        case .sun, .star:
            let metadata = StellarMetadata.make(for: object)
            return [
                Item(label: "Age", value: metadata.age),
                Item(label: "Color", value: metadata.color),
                Item(label: "Temperature", value: metadata.temperature),
                Item(label: "Distance from Earth", value: metadata.distanceFromEarth)
            ]
        case .constellation:
            return object.facts.compactMap(split)
        default:
            return object.facts.compactMap(split)
        }
    }

    /// Turn "Diameter: 139,820 km" → Item(label: "Diameter", value: "139,820 km").
    private nonisolated static func split(_ fact: String) -> Item? {
        guard let range = fact.range(of: ": ") else {
            return Item(label: "", value: fact)
        }
        return Item(label: String(fact[..<range.lowerBound]),
                    value: String(fact[range.upperBound...]))
    }

}

// MARK: - 3D preview viewport

/// Isolated SceneKit viewport. Shows opaque bodies/Sun from .usdz and stars from
/// ProceduralStarRenderer. Transparent background so it sits
/// cleanly inside the glassmorphic card (no calibration grid / opaque container).
private struct BodyPreview: UIViewRepresentable {
    let object: CelestialObject
    let modelURL: URL?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling2X
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true            // let the user spin it
        view.scene = makeScene()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let content = SCNNode()
        if object.type == .star {
            content.addChildNode(ProceduralStarRenderer.makeStarNode(
                for: object,
                radius: 1.2,
                segmentCount: 64,
                includeHalo: true
            ))
        } else if let modelURL, let loaded = try? SCNScene(url: modelURL, options: [.convertToYUp: true]) {
            for child in loaded.rootNode.childNodes { content.addChildNode(child) }
        } else {
            content.addChildNode(makeGlowSphere(for: object))
        }

        // Normalize size & center so any model frames identically.
        let (minB, maxB) = content.boundingBox
        let extent = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
        if extent > 0 {
            let s = 3.0 / extent
            content.scale = SCNVector3(s, s, s)
            let center = SCNVector3((minB.x + maxB.x) / 2 * s,
                                    (minB.y + maxB.y) / 2 * s,
                                    (minB.z + maxB.z) / 2 * s)
            content.position = SCNVector3(-center.x, -center.y, -center.z)
        }
        content.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 14)))
        scene.rootNode.addChildNode(content)

        // Framing camera.
        let cam = SCNNode()
        cam.camera = SCNCamera()
        ProceduralStarRenderer.configureBloom(on: cam.camera, profile: .preview)
        cam.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(cam)

        // A soft key light so unlit star spheres still read as 3D.
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .directional
        light.position = SCNVector3(3, 4, 6)
        scene.rootNode.addChildNode(light)

        return scene
    }

    private func makeGlowSphere(for object: CelestialObject) -> SCNNode {
        let sphere = SCNSphere(radius: 1.2)
        let mat = SCNMaterial()
        let color: UIColor = object.type == .sun
            ? UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1)
            : UIColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 1)
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.lightingModel = .constant
        sphere.firstMaterial = mat
        return SCNNode(geometry: sphere)
    }

}

#Preview {
    ObjectDetailSheet(object: CelestialObject(
        id: "preview",
        name: "Vega",
        type: .star,
        equatorial: EquatorialCoordinate(rightAscensionHours: 18.6, declinationDegrees: 38.78),
        magnitude: 0.03,
        designation: "α Lyr",
        subtitle: "The harp star",
        summary: "One of the nearest naked-eye stars (25 light-years).",
        facts: ["Spectral type: A0 V", "Distance: 25 ly"]
    ))
    .preferredColorScheme(.dark)
}
