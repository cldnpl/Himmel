//
//  SkySceneView.swift
//  Himmel
//
//  SwiftUI wrapper. Returns a container holding the SCNView (3D sky) with the
//  screen-space label overlay on top, so projected name labels sit above the
//  rendered scene while taps still fall through to the SCNView.
//

import SwiftUI
import SceneKit

struct SkySceneView: UIViewRepresentable {

    let viewModel: SkyViewModel
    let onSelect: (String) -> Void

    func makeCoordinator() -> SkySceneCoordinator {
        SkySceneCoordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let coordinator = context.coordinator
        coordinator.attach(viewModel: viewModel, onSelect: onSelect)
        coordinator.start()

        let container = UIView()

        // Live-AR camera passthrough — the BOTTOM layer, behind everything. Hidden
        // until Live AR Mode is toggled on; shows the real sky through the (then
        // transparent) SCNView.
        let cameraPreview = coordinator.cameraPreviewView
        cameraPreview.frame = container.bounds
        cameraPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(cameraPreview)

        // 3D scene fills the container, above the camera feed.
        let scn = coordinator.scnView
        scn.frame = container.bounds
        scn.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(scn)

        // Label overlay sits on top, projecting through the same SCNView's camera.
        let overlay = coordinator.labelOverlay
        overlay.frame = container.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.sceneView = scn
        overlay.cameraNode = coordinator.cameraNodeForProjection
        container.addSubview(overlay)
        // The overlay is refreshed by the coordinator's single per-frame clock.

        coordinator.render(state: viewModel)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.applyARState(live: viewModel.isLiveARMode,
                                         virtualSky: viewModel.arShowVirtualSky)
        context.coordinator.render(state: viewModel)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: SkySceneCoordinator) {
        coordinator.stop()
    }
}
