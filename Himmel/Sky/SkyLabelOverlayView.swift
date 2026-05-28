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

    /// Source labels. Replaced wholesale whenever the sky recomputes (~30s),
    /// which (re)builds the reusable UILabel pool.
    var labels: [SkyLabel] = [] {
        didSet { rebuildPool() }
    }

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

    /// Fixed-point typography per kind, with a text drop-shadow and (for bright
    /// bodies) a translucent rounded pill so names lift off the dense Milky Way.
    private func style(_ label: PaddedLabel, for item: SkyLabel) {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero

        let font: UIFont
        let color: UIColor
        var kern: CGFloat = 0.2
        var pill = false
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

        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .shadow: shadow,
            .kern: kern
        ])
        label.textAlignment = .center
        label.numberOfLines = 1
        if pill {
            label.backgroundColor = UIColor(white: 0, alpha: 0.32)
            label.layer.cornerRadius = 9
            label.clipsToBounds = true
        } else {
            label.backgroundColor = .clear
            label.layer.cornerRadius = 0
            label.clipsToBounds = false
        }
    }

    // MARK: - Per-frame layout

    /// Called once per frame by the renderer's single clock (SkySceneCoordinator),
    /// AFTER the camera transform for this frame has been set — so projection is
    /// locked to the exact camera the 3D scene is drawn with.
    func refresh() {
        layoutLabels()
    }

    private func layoutLabels() {
        guard let scn = sceneView, !labels.isEmpty else { return }
        let viewBounds = bounds

        // 1. PROJECT every label's 3D world position to 2D screen space, and note
        //    which are actually on-screen and in front of the camera.
        struct Projected { let item: SkyLabel; let anchor: CGPoint; let onScreen: Bool }
        var projected: [Projected] = []
        projected.reserveCapacity(labels.count)
        var anchors: [CGPoint] = []   // all visible dot positions, to avoid covering them

        for item in labels {
            let p = scn.projectPoint(SCNVector3(item.world.x, item.world.y, item.world.z))
            // z ∈ [0,1] → in front of camera & within near/far. z > 1 (or < 0) → behind.
            let inFront = p.z > 0 && p.z < 1
            let anchor = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
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

        for entry in ordered {
            guard let view = pool[entry.item.id],
                  let size = sizeCache[entry.item.id] else { continue }

            let rect = placement(for: entry.item, anchor: entry.anchor, size: size,
                                 bounds: viewBounds, placed: placed, anchors: anchors)
            if let rect {
                view.frame = rect
                view.isHidden = false
                placed.append(rect.insetBy(dx: -2, dy: -2))   // padding between labels
                shownIDs.insert(entry.item.id)
            } else {
                view.isHidden = true   // no collision-free slot → drop (priority yields)
            }
        }
        // Hide everything we didn't place (off-screen or behind camera).
        for (id, view) in pool where !shownIDs.contains(id) {
            view.isHidden = true
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
