//
//  SkySceneView.swift
//  Himmel
//
//  SwiftUI wrapper around the SCNView-backed SkySceneCoordinator.
//

import SwiftUI
import SceneKit

struct SkySceneView: UIViewRepresentable {

    let viewModel: SkyViewModel
    let onSelect: (String) -> Void

    func makeCoordinator() -> SkySceneCoordinator {
        SkySceneCoordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let coordinator = context.coordinator
        coordinator.attach(viewModel: viewModel, onSelect: onSelect)
        coordinator.start()
        coordinator.render(state: viewModel)
        return coordinator.scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.render(state: viewModel)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: SkySceneCoordinator) {
        coordinator.stop()
    }
}
