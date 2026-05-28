//
//  SkyNavigationSolver.swift
//  Himmel
//
//  Camera-relative vector math for object guidance. This stays separate from
//  search state and SwiftUI so the render loop only does projection work.
//

import CoreGraphics
import SceneKit
import simd

struct SkyNavigationSolver {

    func evaluate(
        targetID: String,
        targetName: String,
        targetWorldPosition: SIMD3<Float>,
        cameraNode: SCNNode,
        sceneView: SCNView
    ) -> SkyNavigationGuidance {
        let cameraPosition = cameraNode.simdWorldPosition
        let targetDirection = simd_normalize(targetWorldPosition - cameraPosition)

        let transform = cameraNode.simdWorldTransform
        let cameraRight = simd_normalize(SIMD3<Float>(
            transform.columns.0.x,
            transform.columns.0.y,
            transform.columns.0.z
        ))
        let cameraUp = simd_normalize(SIMD3<Float>(
            transform.columns.1.x,
            transform.columns.1.y,
            transform.columns.1.z
        ))
        let cameraForward = simd_normalize(-SIMD3<Float>(
            transform.columns.2.x,
            transform.columns.2.y,
            transform.columns.2.z
        ))

        let forwardDot = simd_dot(targetDirection, cameraForward)
        let rightDot = simd_dot(targetDirection, cameraRight)
        let upDot = simd_dot(targetDirection, cameraUp)

        let yaw = atan2(rightDot, forwardDot)
        let pitch = atan2(upDot, sqrt(max(0, forwardDot * forwardDot + rightDot * rightDot)))
        let angularDistance = acos(max(-1, min(1, forwardDot)))

        let projected = sceneView.projectPoint(SCNVector3(
            targetWorldPosition.x,
            targetWorldPosition.y,
            targetWorldPosition.z
        ))
        let point = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        let bounds = sceneView.bounds
        let visibleBounds = bounds.insetBy(dx: 18, dy: 18)
        let inDepthRange = projected.z > 0 && projected.z < 1
        let finiteProjection = point.x.isFinite && point.y.isFinite
        let isVisible = inDepthRange && finiteProjection && visibleBounds.contains(point)

        // ── 8-way direction ──────────────────────────────────────────────────
        // Build the screen-space direction vector from the viewport CENTRE toward
        // the target, then quantise its angle into one of 8 sectors. We derive the
        // vector from the camera-relative dot products (rightDot, upDot) rather
        // than the projected point, because those stay valid even when the target
        // is BEHIND the camera (where projectPoint mirrors). +x = right, +y = up.
        let direction: SkyNavigationDirection?
        if isVisible {
            direction = nil
        } else {
            let theta = atan2(Double(upDot), Double(rightDot))   // math angle, +y up
            direction = SkyNavigationDirection(angle: theta)
        }

        let closeness = 1.0 - min(Double(angularDistance), .pi) / .pi
        let intensity = max(0.18, min(1.0, closeness))

        return SkyNavigationGuidance(
            targetID: targetID,
            targetName: targetName,
            direction: direction,
            isTargetVisible: isVisible,
            angularDistanceDegrees: Double(angularDistance) * 180.0 / .pi,
            yawDegrees: Double(yaw) * 180.0 / .pi,
            pitchDegrees: Double(pitch) * 180.0 / .pi,
            intensity: intensity
        )
    }
}
