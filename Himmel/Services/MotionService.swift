//
//  MotionService.swift
//  Himmel
//
//  Publishes a continuously updated rotation matrix that the SceneKit camera
//  uses to mirror the phone's orientation. Uses CoreMotion's
//  `xMagneticNorthZVertical` reference frame so the sky stays locked to true
//  (well, magnetic) compass heading.
//

import Foundation
import CoreMotion
import simd

nonisolated final class MotionService: @unchecked Sendable {

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    /// body→reference rotation (reference = X:North, Y:East, Z:Up).
    /// Reads only — written from the CoreMotion queue.
    nonisolated(unsafe) private var _currentTransform: simd_float4x4 = matrix_identity_float4x4

    /// Thread-safe read of the latest body→world rotation matrix.
    var currentTransform: simd_float4x4 {
        // Atomic-ish: simd_float4x4 is 64 bytes; reads aren't strictly atomic but
        // an occasional torn read is harmless — a single stale frame at most.
        _currentTransform
    }

    init() {
        queue.name = "himmel.motion"
        queue.qualityOfService = .userInteractive
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        let frame: CMAttitudeReferenceFrame =
            CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical)
                ? .xMagneticNorthZVertical
                : .xArbitraryCorrectedZVertical

        manager.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self._currentTransform = Self.makeBodyToWorldTransform(from: motion.attitude)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    // MARK: - Math

    /// Build the body→world rotation matrix from a `CMAttitude`.
    ///
    /// CoreMotion `xMagneticNorthZVertical` reference: X=North, Y=East, Z=Up.
    /// This matches our scene world coordinates, so the matrix is used as-is
    /// for the camera node's transform.
    private static func makeBodyToWorldTransform(from attitude: CMAttitude) -> simd_float4x4 {
        let r = attitude.rotationMatrix
        // CMRotationMatrix `m_ij` is row-major. simd_float4x4 stores columns;
        // column k holds the world-frame coords of body-axis k.
        let col0 = SIMD4<Float>(Float(r.m11), Float(r.m21), Float(r.m31), 0)
        let col1 = SIMD4<Float>(Float(r.m12), Float(r.m22), Float(r.m32), 0)
        let col2 = SIMD4<Float>(Float(r.m13), Float(r.m23), Float(r.m33), 0)
        let col3 = SIMD4<Float>(0, 0, 0, 1)
        return simd_float4x4(col0, col1, col2, col3)
    }
}
