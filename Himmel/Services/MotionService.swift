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

// MARK: - Camera-orientation policy

/// Maps the raw device attitude to the orientation we assign to the SceneKit
/// camera. Kept separate from `MotionService` so the *sensor reading* and the
/// *camera-mapping policy* stay decoupled (easy to tweak/test in one place).
///
/// COORDINATE FRAMES
/// ─────────────────
/// • World (reference) frame — CoreMotion `xMagneticNorthZVertical`, right-handed:
///       +X = magnetic North,  +Y = West,  +Z = Up.
///   Star positions use this SAME frame, so camera and stars stay consistent.
/// • Device body frame — fixed to the hardware, INDEPENDENT of UI orientation:
///       +X = right edge,  +Y = top edge,  +Z = out of the screen toward the user.
///   The app is locked to Portrait, so this already equals SceneKit's camera-local
///   frame (camera looks down −Z, +Y up, +X right). ⇒ no portrait axis remap and
///   no pitch↔roll cross-talk to undo. (Cross-talk only appears when you read raw
///   gyro WITHOUT a reference frame, or let the UI auto-rotate.)
///
/// WHY THE INVERSION
/// ─────────────────
/// `CMAttitude` and a camera transform run in OPPOSITE directions: the attitude
/// matrix is "world-as-seen-from-the-device", whereas the camera node needs
/// "device-placed-in-the-world". Feeding the attitude in raw makes the whole
/// rotation read with the wrong sign — pitch, yaw (and roll) all respond
/// reversed. Taking the conjugate `q⁻¹` (== inverse for a unit quaternion)
/// flips the full rotation back so the motion tracks the phone naturally.
enum SkyCameraMotion {

    /// `true`  → apply q⁻¹ (corrects the reversed pitch/yaw/roll the user reported).
    /// `false` → use the attitude as-is (the previous, inverted behaviour).
    /// One-line switch to flip the whole feel if a device reports the opposite.
    static let invertAttitude = true

    /// Convert a body→world attitude quaternion into the camera's orientation.
    static func cameraOrientation(for attitude: simd_quatf) -> simd_quatf {
        // q⁻¹ reverses every axis of rotation at once (a single, clean operation
        // instead of negating individual components, which would risk a
        // left-handed / mirrored basis). For a unit quaternion this is just the
        // conjugate: (x, y, z, w) → (−x, −y, −z, w).
        invertAttitude ? attitude.inverse : attitude
    }
}
