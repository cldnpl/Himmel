//
//  SkyLabelOverlayView.swift
//  Himmel
//
//  Screen-space label layer (Sky Guide / Stellarium style). Instead of drawing
//  names as 3D billboard planes — whose size depends on scene depth and which
//  freely overlap — we render them as native 2D UIKit text:
//
//   • Each label's 3D world position is PROJECTED to 2D screen coordinates every
//     frame via the SceneKit camera, so the text tracks its star/planet.
//   • Font size is FIXED in points → always crisp, never microscopic or giant,
//     independent of scene scale or distance.
//   • A greedy COLLISION resolver lays labels out by priority, offsetting them
//     below / above / beside the dot and dropping the lowest-priority ones that
//     can't fit — so labels never cover other dots or each other.
//
//  The view is transparent and ignores touches, so taps still reach the SCNView.
//

import UIKit
import SceneKit
import simd

/// One labellable sky element handed to the overlay by the renderer.
struct SkyLabel {
    enum Kind { case planet, body, cardinal, star, constellation }
    let id: String
    let world: SIMD3<Float>     // position on the celestial sphere (scene world space)
    let text: String
    let kind: Kind

    /// Higher wins when two labels compete for the same screen area.
    var priority: Int {
        switch kind {
        case .planet:        return 100
        case .body:          return 90
        case .cardinal:      return 70
        case .star:          return 50
        case .constellation: return 30
        }
    }
}

/// A UILabel with internal padding so the translucent pill background has margin.
private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right,
                      height: s.height + insets.top + insets.bottom)
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = super.sizeThatFits(size)
        return CGSize(width: s.width + insets.left + insets.right,
                      height: s.height + insets.top + insets.bottom)
    }
}

final class SkyLabelOverlayView: UIView {

    /// The SCNView whose camera we project through.
    weak var sceneView: SCNView?

    /// The camera node we project through. Projection is computed MANUALLY from
    /// this node's world transform (set this very frame) rather than
    /// `SCNView.projectPoint`, which samples the camera's *presentation* node —
    /// i.e. the previously rendered frame. Reading the live model transform keeps
    /// every label rigidly locked to its 3D anchor with zero one-frame drag.
    weak var cameraNode: SCNNode?

    /// Source labels. Replaced wholesale whenever the sky recomputes (~30s),
    /// which (re)builds the reusable UILabel pool.
    var labels: [SkyLabel] = [] {
        didSet { rebuildPool() }
    }
    var highlightedLabelID: String? {
        didSet {
            guard highlightedLabelID != oldValue else { return }
            restylePool()
        }
    }

    /// Live AR Mode: hide labels of objects below the horizon so names never sit
    /// on the surrounding buildings/ground — only the real sky is annotated.
    var cullBelowHorizon = false

    private var pool: [String: PaddedLabel] = [:]
    private var sizeCache: [String: CGSize] = [:]

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false   // taps fall through to the SCNView
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Pool management

    private func rebuildPool() {
        let liveIDs = Set(labels.map(\.id))
        // Recycle/remove labels no longer present.
        for (id, view) in pool where !liveIDs.contains(id) {
            view.removeFromSuperview()
            pool[id] = nil
            sizeCache[id] = nil
        }
        // Create/update labels for the current set.
        for item in labels {
            let view = pool[item.id] ?? {
                let v = PaddedLabel()
                v.isHidden = true
                addSubview(v)
                pool[item.id] = v
                return v
            }()
            style(view, for: item)
            sizeCache[item.id] = view.sizeThatFits(CGSize(width: 400, height: 80))
        }
    }

    private func restylePool() {
        for item in labels {
            guard let view = pool[item.id] else { continue }
            style(view, for: item)
            sizeCache[item.id] = view.sizeThatFits(CGSize(width: 400, height: 80))
        }
    }

    /// Fixed-point typography per kind, with a text drop-shadow and (for bright
    /// bodies) a translucent rounded pill so names lift off the dense Milky Way.
    private func style(_ label: PaddedLabel, for item: SkyLabel) {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.95)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = .zero

        var font: UIFont
        var color: UIColor
        var kern: CGFloat = 0.2
        // EVERY label gets a translucent pill so names stay readable over a bright
        // daytime sky as well as the night background.
        var pill = true
        var text = item.text

        switch item.kind {
        case .planet:
            font = .systemFont(ofSize: 16, weight: .semibold)
            color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
            pill = true
        case .body:
            font = .systemFont(ofSize: 16, weight: .semibold)
            color = .white
            pill = true
        case .cardinal:
            font = .systemFont(ofSize: 17, weight: .bold)
            color = UIColor(red: 0.95, green: 0.55, blue: 0.45, alpha: 0.95)
        case .star:
            font = .systemFont(ofSize: 12, weight: .medium)
            color = UIColor(red: 0.92, green: 0.94, blue: 1.0, alpha: 0.95)
        case .constellation:
            font = .systemFont(ofSize: 13, weight: .light)
            color = UIColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 0.9)
            kern = 2.0
            text = item.text.uppercased()
        }

        let isHighlighted = item.id == highlightedLabelID
        if isHighlighted {
            font = .systemFont(ofSize: max(font.pointSize, 16), weight: .bold)
            color = .white
            pill = true
            kern = 0.2
            text = item.text
        }

        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .shadow: shadow,
            .kern: kern
        ])
        label.textAlignment = .center
        label.numberOfLines = 1
        if pill {
            label.backgroundColor = isHighlighted
                ? UIColor(red: 0.20, green: 0.48, blue: 1.0, alpha: 0.55)
                : UIColor(white: 0, alpha: 0.5)   // stronger so text reads on bright sky
            label.layer.cornerRadius = 9
            label.clipsToBounds = true
        } else {
            label.backgroundColor = .clear
            label.layer.cornerRadius = 0
            label.clipsToBounds = false
        }
        label.layer.borderWidth = isHighlighted ? 1 : 0
        label.layer.borderColor = isHighlighted
            ? UIColor.white.withAlphaComponent(0.8).cgColor
            : UIColor.clear.cgColor
    }

    // MARK: - Per-frame layout

    /// Called once per frame by the renderer's single clock (SkySceneCoordinator),
    /// AFTER the camera transform for this frame has been set — so projection is
    /// locked to the exact camera the 3D scene is drawn with.
    func refresh() {
        layoutLabels()
    }

    /// Hard teardown: hide every pooled label immediately and drop the highlight.
    /// Bound to search reset / navigation cancellation so no label can ghost on
    /// the HUD after the high-frequency projection stops updating it.
    func clearAllActiveLabels() {
        highlightedLabelID = nil
        hideAllPooledLabels()
    }

    private func hideAllPooledLabels() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (_, view) in pool { view.isHidden = true }
        CATransaction.commit()
    }

    private func layoutLabels() {
        // If there is nothing to project (no labels) or no camera yet, force-hide
        // everything instead of returning early and leaving stale frames on screen.
        guard let cam = cameraNode, let scnCam = cam.camera, !labels.isEmpty else {
            hideAllPooledLabels()
            return
        }
        let viewBounds = bounds
        let w = Float(viewBounds.width)
        let h = Float(viewBounds.height)
        guard w > 0, h > 0 else { return }

        // Build the view-projection matrix from the camera's LIVE world transform
        // (the one we set this same frame), so projection is locked to render.
        let viewMatrix = simd_inverse(cam.simdWorldTransform)
        let projMatrix = simd_float4x4(scnCam.projectionTransform(withViewportSize: viewBounds.size))
        let viewProjection = projMatrix * viewMatrix

        // 1. PROJECT every label's 3D world position to 2D screen space, and note
        //    which are actually on-screen and in front of the camera.
        struct Projected { let item: SkyLabel; let anchor: CGPoint; let onScreen: Bool }
        var projected: [Projected] = []
        projected.reserveCapacity(labels.count)
        var anchors: [CGPoint] = []   // all visible dot positions, to avoid covering them

        for item in labels {
            // Live AR Mode: skip anything below the horizon (world +Z is up) so
            // labels appear only over the real sky, never on nearby buildings.
            if cullBelowHorizon, item.world.z < 0 { continue }

            let clip = viewProjection * SIMD4<Float>(item.world.x, item.world.y, item.world.z, 1)
            // clip.w > 0 ⇒ in front of the camera. Behind ⇒ skip (never drag a
            // mirror-projected ghost across the screen).
            let inFront = clip.w > 0.0001
            var anchor = CGPoint(x: -10_000, y: -10_000)
            if inFront {
                let ndcX = clip.x / clip.w
                let ndcY = clip.y / clip.w
                let sx = (ndcX * 0.5 + 0.5) * w
                let sy = (1 - (ndcY * 0.5 + 0.5)) * h   // flip Y → UIKit top-left
                anchor = CGPoint(x: CGFloat(sx), y: CGFloat(sy))
            }
            let onScreen = inFront
                && viewBounds.insetBy(dx: -40, dy: -40).contains(anchor)
            projected.append(Projected(item: item, anchor: anchor, onScreen: onScreen))
            if onScreen { anchors.append(anchor) }
        }

        // 2. RESOLVE collisions greedily, highest priority first.
        let ordered = projected
            .filter { $0.onScreen }
            .sorted { $0.item.priority > $1.item.priority }

        var placed: [CGRect] = []
        var shownIDs = Set<String>()

        // Disable implicit animations so frames don't smear during fast rotation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // BULLETPROOF: hide everything first; only labels that pass the frustum
        // test AND win collision this frame get re-shown. A label can therefore
        // never freeze/ghost — if it's not actively placed this exact frame, it's
        // hidden, full stop.
        for (_, view) in pool { view.isHidden = true }

        for entry in ordered {
            guard let view = pool[entry.item.id],
                  let size = sizeCache[entry.item.id] else { continue }

            // Constellation names are ALWAYS shown at their centroid when on
            // screen — they are exempt from collision culling so they never
            // vanish just because a star label sits nearby (previously the lowest
            // priority meant they got dropped whenever centred). They are NOT
            // added to `placed`, so they don't block other labels.
            if entry.item.kind == .constellation {
                var center = entry.anchor
                // Keep the name fully on screen even if the centroid is near an edge.
                center.x = min(max(center.x, size.width / 2 + 4), viewBounds.width - size.width / 2 - 4)
                center.y = min(max(center.y, size.height / 2 + 4), viewBounds.height - size.height / 2 - 4)
                view.frame = CGRect(x: center.x - size.width / 2,
                                    y: center.y - size.height / 2,
                                    width: size.width, height: size.height)
                view.isHidden = false
                shownIDs.insert(entry.item.id)
                continue
            }

            let rect = placement(for: entry.item, anchor: entry.anchor, size: size,
                                 bounds: viewBounds, placed: placed, anchors: anchors)
            if let rect {
                view.frame = rect
                view.isHidden = false
                // Keep the highlight border in sync EVERY frame so a previous
                // target's ring can never linger after the target changes/clears.
                view.layer.borderColor = (entry.item.id == highlightedLabelID)
                    ? UIColor.white.withAlphaComponent(0.8).cgColor
                    : UIColor.clear.cgColor
                placed.append(rect.insetBy(dx: -2, dy: -2))   // padding between labels
                shownIDs.insert(entry.item.id)
            }
        }

        CATransaction.commit()
    }

    /// Finds a collision-free rectangle for one label, trying candidate offsets in
    /// priority order. Returns nil if every candidate collides or leaves the screen.
    private func placement(
        for item: SkyLabel,
        anchor: CGPoint,
        size: CGSize,
        bounds: CGRect,
        placed: [CGRect],
        anchors: [CGPoint]
    ) -> CGRect? {
        let dot = labelClearance(for: item.kind)
        let halfW = size.width / 2
        let halfH = size.height / 2

        // Candidate CENTRE points. Constellations prefer the centroid itself;
        // everything else prefers BELOW the dot, then above, then the sides.
        let centres: [CGPoint]
        if item.kind == .constellation {
            centres = [
                anchor,
                CGPoint(x: anchor.x, y: anchor.y + dot + halfH),
                CGPoint(x: anchor.x, y: anchor.y - dot - halfH)
            ]
        } else {
            centres = [
                CGPoint(x: anchor.x, y: anchor.y + dot + halfH),   // below (preferred)
                CGPoint(x: anchor.x, y: anchor.y - dot - halfH),   // above
                CGPoint(x: anchor.x + dot + halfW, y: anchor.y),   // right
                CGPoint(x: anchor.x - dot - halfW, y: anchor.y)    // left
            ]
        }

        for c in centres {
            let rect = CGRect(x: c.x - halfW, y: c.y - halfH, width: size.width, height: size.height)
            // Must stay (mostly) on screen.
            if !bounds.insetBy(dx: -6, dy: -6).contains(rect) { continue }
            // Must not overlap an already-placed label.
            if placed.contains(where: { $0.intersects(rect) }) { continue }
            // Must not cover another body's dot (its own anchor is allowed).
            if anchors.contains(where: { $0 != anchor && rect.insetBy(dx: -2, dy: -2).contains($0) }) { continue }
            return rect
        }
        return nil
    }

    private func labelClearance(for kind: SkyLabel.Kind) -> CGFloat {
        switch kind {
        case .star: return 18
        case .planet, .body: return 22
        case .cardinal: return 16
        case .constellation: return 10
        }
    }
}
