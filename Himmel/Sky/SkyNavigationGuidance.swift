//
//  SkyNavigationGuidance.swift
//  Himmel
//
//  Small value types shared between the high-frequency SceneKit navigation
//  solver and the SwiftUI overlay.
//

import Foundation
import CoreGraphics

/// 8-way compass direction toward an off-screen target. A single precise arrow
/// (cardinal OR diagonal) replaces the old multi-arrow cardinal set.
enum SkyNavigationDirection: Hashable, CaseIterable {
    case right, upRight, up, upLeft, left, downLeft, down, downRight

    /// Map a screen-space angle (radians, math convention: +x = right, +y = UP)
    /// to one of 8 sectors of 45°.
    init(angle: Double) {
        // Normalize to [0, 2π).
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        // Each sector spans 45°; offset by 22.5° so a sector is CENTERED on its axis.
        let sector = Int((a + .pi / 8) / (.pi / 4)) % 8
        self = SkyNavigationDirection.allCases[sector]
    }

    var symbolName: String {
        switch self {
        case .right:     return "arrow.right"
        case .upRight:   return "arrow.up.right"
        case .up:        return "arrow.up"
        case .upLeft:    return "arrow.up.left"
        case .left:      return "arrow.left"
        case .downLeft:  return "arrow.down.left"
        case .down:      return "arrow.down"
        case .downRight: return "arrow.down.right"
        }
    }

    /// Unit vector (screen space, +y DOWN for UIKit) used to place the arrow
    /// along the corresponding screen edge / corner.
    var screenVector: CGVector {
        switch self {
        case .right:     return CGVector(dx: 1, dy: 0)
        case .upRight:   return CGVector(dx: 1, dy: -1)
        case .up:        return CGVector(dx: 0, dy: -1)
        case .upLeft:    return CGVector(dx: -1, dy: -1)
        case .left:      return CGVector(dx: -1, dy: 0)
        case .downLeft:  return CGVector(dx: -1, dy: 1)
        case .down:      return CGVector(dx: 0, dy: 1)
        case .downRight: return CGVector(dx: 1, dy: 1)
        }
    }
}

struct SkyNavigationGuidance: Equatable {
    var targetID: String?
    var targetName: String
    /// Single 8-way arrow direction; nil when the target is on-screen.
    var direction: SkyNavigationDirection?
    var isTargetVisible: Bool
    var angularDistanceDegrees: Double
    var yawDegrees: Double
    var pitchDegrees: Double
    var intensity: Double

    var isActive: Bool { targetID != nil }
    var shouldShowArrows: Bool { isActive && !isTargetVisible && direction != nil }

    static let inactive = SkyNavigationGuidance(
        targetID: nil,
        targetName: "",
        direction: nil,
        isTargetVisible: false,
        angularDistanceDegrees: 180,
        yawDegrees: 0,
        pitchDegrees: 0,
        intensity: 0
    )
}
