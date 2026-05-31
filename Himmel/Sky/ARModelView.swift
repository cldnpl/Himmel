//
//  ARModelView.swift
//  Himmel
//
//  Custom AR viewer for a single celestial body's .usdz, used by the detail
//  sheet's "View in AR" button. Unlike AR Quick Look (a closed system component),
//  this gives us full control over:
//    • One-finger PAN  → rotate the model on its LOCAL axes (it never moves).
//    • Two-finger PAN  → move the world anchor across detected AR planes.
//    • Two-finger PINCH → scale the model locally with hard Min/Max clamps.
//    • A custom high-visibility coaching hint for poor / cramped environments.
//
//  Rigid anchoring: the tap drops a world-fixed "placement" node; gestures only
//  touch its CHILD model node, so the anchor stays locked to the real-world plane.
//

import SwiftUI
import ARKit
import SceneKit
import Photos

// MARK: - SwiftUI bridge

struct ARModelView: UIViewControllerRepresentable {
    let modelURL: URL?
    let object: CelestialObject?
    let title: String
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> ARModelViewController {
        let vc = ARModelViewController(modelURL: modelURL, object: object, title: title)
        vc.onClose = onClose
        return vc
    }
    func updateUIViewController(_ vc: ARModelViewController, context: Context) {}
}

// MARK: - AR view controller

final class ARModelViewController: UIViewController, ARSessionDelegate, ARCoachingOverlayViewDelegate, UIGestureRecognizerDelegate {

    var onClose: (() -> Void)?

    private let modelURL: URL?
    private let object: CelestialObject?
    private let bodyTitle: String
    private let arView = ARSCNView(frame: .zero)
    private let coachingOverlay = ARCoachingOverlayView()
    private let hintLabel = PaddedHintLabel()
    private let shutterButton = UIButton(type: .custom)
    private let relocateButton = UIButton(type: .system)
    private let captureService = ARSnapshotCaptureService()

    /// Parsed once, cloned on placement.
    private var modelTemplate: SCNNode?
    /// World-fixed anchor node (stays put). Gestures never touch this.
    private weak var placementNode: SCNNode?
    /// The manipulable child (rotated & scaled by gestures).
    private weak var modelNode: SCNNode?

    /// Updated by ARSessionDelegate as planes are discovered.
    private var hasDetectedPlane = false

    // Gesture tuning -----------------------------------------------------------
    /// Radians of rotation per screen point dragged.
    private let rotationSensitivity: Float = 0.012
    /// Scale clamps, computed at placement relative to the fitted base scale.
    private var baseScale: Float = 1
    private var minScale: Float = 0.3
    private var maxScale: Float = 5.0
    private var pinchStartScale: Float = 1

    private let initialSpawnDistance: Float = 0.6
    private let initialSpawnEyeDrop: Float = 0.06
    private let relocationDistance: Float = 0.5
    private let targetModelExtent: Float = 0.18
    private var nextSpawnDistance: Float = 0.6

    init(modelURL: URL?, object: CelestialObject?, title: String) {
        self.modelURL = modelURL
        self.object = object
        self.bodyTitle = title
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupARView()
        setupCoaching()
        setupOverlays()
        setupGestures()
        preloadModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARWorldTrackingConfiguration.isSupported else {
            hintLabel.text = "AR isn't supported on this device."
            hintLabel.isHidden = false
            return
        }
        runARSession(resetTracking: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        coachingOverlay.delegate = nil
        arView.session.delegate = nil
        arView.session.pause()
    }

    // MARK: Setup

    private func setupARView() {
        arView.frame = view.bounds
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.automaticallyUpdatesLighting = true
        arView.session.delegate = self
        arView.scene = SCNScene()
        ProceduralStarRenderer.configureBloom(on: arView.pointOfView?.camera, profile: .ar)
        view.addSubview(arView)
    }

    private func setupCoaching() {
        // Apple's standard "move iPhone to find a surface" coaching.
        coachingOverlay.session = arView.session
        coachingOverlay.delegate = self
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.frame = view.bounds
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coachingOverlay)
    }

    private func setupOverlays() {
        // Custom high-visibility environment hint (poor tracking / cramped space).
        hintLabel.text = "For an optimal experience, move to an open, spacious, and well-lit area."
        hintLabel.isHidden = true
        view.addSubview(hintLabel)

        configureShutterButton()
        view.addSubview(shutterButton)

        configureRelocateButton()
        view.addSubview(relocateButton)

        // Close button.
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .white
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        relocateButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            close.widthAnchor.constraint(equalToConstant: 34),
            close.heightAnchor.constraint(equalToConstant: 34),

            relocateButton.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            relocateButton.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -14),
            relocateButton.widthAnchor.constraint(equalToConstant: 38),
            relocateButton.heightAnchor.constraint(equalToConstant: 38),

            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 70),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: 78),
            shutterButton.heightAnchor.constraint(equalToConstant: 78)
        ])
    }

    private func configureShutterButton() {
        shutterButton.backgroundColor = .clear
        shutterButton.layer.cornerRadius = 39
        shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
        shutterButton.layer.borderWidth = 3
        shutterButton.layer.shadowColor = UIColor.black.cgColor
        shutterButton.layer.shadowOpacity = 0.25
        shutterButton.layer.shadowRadius = 10
        shutterButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        shutterButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        shutterButton.addTarget(self, action: #selector(shutterTouchDown), for: .touchDown)
        shutterButton.addTarget(self, action: #selector(shutterTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let inner = UIView()
        inner.isUserInteractionEnabled = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.backgroundColor = .white
        inner.layer.cornerRadius = 31
        shutterButton.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            inner.widthAnchor.constraint(equalToConstant: 62),
            inner.heightAnchor.constraint(equalToConstant: 62)
        ])
    }

    private func configureRelocateButton() {
        let image = UIImage(systemName: "arrow.clockwise.circle.fill")
        relocateButton.setImage(image, for: .normal)
        relocateButton.tintColor = .white
        relocateButton.backgroundColor = UIColor.black.withAlphaComponent(0.30)
        relocateButton.layer.cornerRadius = 19
        relocateButton.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        relocateButton.layer.borderWidth = 0.8
        relocateButton.addTarget(self, action: #selector(relocateTapped), for: .touchUpInside)
    }

    private func setupGestures() {
        let oneFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleOneFingerPan(_:)))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.delegate = self
        arView.addGestureRecognizer(oneFingerPan)

        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = self
        arView.addGestureRecognizer(twoFingerPan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        arView.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
    }

    private func preloadModel() {
        if let object, object.type == .star {
            modelTemplate = ProceduralStarRenderer.makeStarNode(
                for: object,
                radius: 1.0,
                segmentCount: 64,
                includeHalo: true
            )
            return
        }

        guard let modelURL else { return }
        guard let scene = try? SCNScene(url: modelURL, options: [.convertToYUp: true]) else { return }
        let node = SCNNode()
        for child in scene.rootNode.childNodes { node.addChildNode(child) }

        // Tame the imported PBR so ARKit's automatic environment probe (IBL)
        // can't paint a shiny white film over the body. Matches the star-map
        // treatment: the Sun keeps its authored emissive look; everything else
        // becomes matte so the texture reads true under the AR environment light.
        if object?.type != .sun {
            node.enumerateHierarchy { child, _ in
                child.geometry?.materials.forEach { CelestialBodyFactory.applyMatteSurface(to: $0) }
            }
        }

        modelTemplate = node
    }

    private func runARSession(resetTracking: Bool) {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        let options: ARSession.RunOptions = resetTracking
            ? [.resetTracking, .removeExistingAnchors]
            : []
        arView.session.run(config, options: options)
    }

    // MARK: Placement (rigid world anchor)

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let point = g.location(in: arView)
        guard let result = raycastDetectedPlane(at: point) else { return }
        placeModel(using: result.worldTransform)
    }

    // MARK: One-finger orbit rotation (LOCAL transform only)

    @objc private func handleOneFingerPan(_ g: UIPanGestureRecognizer) {
        guard let model = modelNode else { return }
        let t = g.translation(in: arView)

        // UIKit screen space is +X to the right and +Y downward. The previous
        // direct mapping made the object visually turn away from the finger.
        // Inverting both deltas makes the surface follow the gesture:
        //   drag right: dx > 0  -> local yaw decreases
        //   drag up:    dy < 0  -> local pitch increases
        // Only the child model's local Euler angles are changed; the AR anchor
        // parent remains fixed in world space.
        model.eulerAngles.y -= Float(t.x) * rotationSensitivity
        model.eulerAngles.x -= Float(t.y) * rotationSensitivity

        // Consume the delta so the next event is incremental (smooth, no jumps).
        g.setTranslation(.zero, in: arView)
    }

    // MARK: Two-finger world-space translation (ANCHOR transform only)

    @objc private func handleTwoFingerPan(_ g: UIPanGestureRecognizer) {
        guard let anchor = placementNode, g.numberOfTouches == 2 else { return }
        let center = CGPoint(
            x: (g.location(ofTouch: 0, in: arView).x + g.location(ofTouch: 1, in: arView).x) * 0.5,
            y: (g.location(ofTouch: 0, in: arView).y + g.location(ofTouch: 1, in: arView).y) * 0.5
        )
        guard let result = raycastDetectedPlane(at: center) else { return }
        let p = result.worldTransform.columns.3
        anchor.simdPosition = SIMD3<Float>(p.x, p.y, p.z)
        orientAnchorTowardCamera(anchor)
    }

    // MARK: Pinch-to-scale (clamped)

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let model = modelNode else { return }
        switch g.state {
        case .began:
            pinchStartScale = model.simdScale.x
        case .changed:
            // newScale = scaleAtGestureStart × pinchFactor, clamped to [min, max].
            let proposed = pinchStartScale * Float(g.scale)
            let clamped = max(minScale, min(maxScale, proposed))
            model.simdScale = SIMD3(repeating: clamped)
        default:
            break
        }
    }

    private func raycastDetectedPlane(at point: CGPoint) -> ARRaycastResult? {
        guard let query = arView.raycastQuery(
            from: point,
            allowing: .existingPlaneGeometry,
            alignment: .any
        ) else { return nil }
        return arView.session.raycast(query).first
    }

    // MARK: Camera-relative spawning

    private func spawnInFrontOfCurrentCameraIfNeeded() {
        guard placementNode == nil,
              hasDetectedPlane,
              !coachingOverlay.isActive,
              modelTemplate != nil,
              let frame = arView.session.currentFrame else { return }
        placeModel(using: CameraRelativePlacement.spawnTransform(
            cameraTransform: frame.camera.transform,
            forwardDistance: nextSpawnDistance,
            verticalEyeOffset: initialSpawnEyeDrop
        ))
    }

    private func resetPlacementAndRestartCoaching() {
        placementNode?.removeFromParentNode()
        placementNode = nil
        modelNode = nil
        hasDetectedPlane = false
        nextSpawnDistance = relocationDistance
        hintLabel.isHidden = false

        runARSession(resetTracking: true)
        coachingOverlay.setActive(true, animated: true)
    }

    private func placeModel(using worldTransform: simd_float4x4) {
        guard let template = modelTemplate else { return }

        let root = placementNode ?? SCNNode()
        root.simdTransform = worldTransform
        if root.parent == nil {
            arView.scene.rootNode.addChildNode(root)
        }

        if modelNode == nil {
            let model = template.clone()
            let normalized = NormalizedModelNode.make(
                from: model,
                targetMaxDimension: targetModelExtent
            )
            root.addChildNode(normalized.node)
            modelNode = normalized.node

            baseScale = normalized.baseScale
            minScale = normalized.baseScale * 0.3
            maxScale = normalized.baseScale * 50.0
        }

        placementNode = root
        nextSpawnDistance = initialSpawnDistance
        orientAnchorTowardCamera(root)
    }

    private func orientAnchorTowardCamera(_ anchor: SCNNode) {
        guard let frame = arView.session.currentFrame else { return }
        let camera = frame.camera.transform.columns.3
        anchor.look(at: SCNVector3(camera.x, camera.y, camera.z))
    }

    // MARK: Gesture coordination

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
    }

    // MARK: Tracking status → custom hint

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async { [weak self] in
            self?.updateTrackingStatus(camera.trackingState)
            if case .normal = camera.trackingState {
                self?.spawnInFrontOfCurrentCameraIfNeeded()
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        ProceduralStarRenderer.configureBloom(on: arView.pointOfView?.camera, profile: .ar)
        if case .normal = frame.camera.trackingState {
            DispatchQueue.main.async { [weak self] in
                self?.spawnInFrontOfCurrentCameraIfNeeded()
            }
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        updatePlaneStateIfNeeded(from: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updatePlaneStateIfNeeded(from: anchors)
    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        spawnInFrontOfCurrentCameraIfNeeded()
    }

    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        resetPlacementAndRestartCoaching()
    }

    private func updatePlaneStateIfNeeded(from anchors: [ARAnchor]) {
        guard anchors.contains(where: { $0 is ARPlaneAnchor }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasDetectedPlane = true
            if let state = self.arView.session.currentFrame?.camera.trackingState {
                self.updateTrackingStatus(state)
            }
        }
    }

    private func updateTrackingStatus(_ state: ARCamera.TrackingState) {
        let isNormal: Bool
        if case .normal = state { isNormal = true } else { isNormal = false }

        // Show the environment hint until tracking is solid and enough space has
        // been mapped. This complements ARCoachingOverlay with the requested copy.
        let needsBetterEnvironment = !isNormal || !hasDetectedPlane
        hintLabel.isHidden = placementNode != nil || !needsBetterEnvironment
    }

    @objc private func closeTapped() { onClose?() }

    @objc private func relocateTapped() {
        resetPlacementAndRestartCoaching()
    }

    @objc private func shutterTouchDown() {
        UIView.animate(withDuration: 0.08, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.shutterButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            self.shutterButton.alpha = 0.82
        }
    }

    @objc private func shutterTouchUp() {
        UIView.animate(withDuration: 0.16, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.2, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.shutterButton.transform = .identity
            self.shutterButton.alpha = 1
        }
    }

    @objc private func captureTapped() {
        guard presentedViewController == nil else { return }
        captureService.capture(from: arView) { [weak self] image in
            guard let self else { return }
            let preview = SnapshotPreviewViewController(image: image, object: self.object)
            self.present(preview, animated: true)
        }
    }
}

// MARK: - Placement math

private enum CameraRelativePlacement {
    static func spawnTransform(
        cameraTransform: simd_float4x4,
        forwardDistance: Float,
        verticalEyeOffset: Float
    ) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        // ARKit stores the camera basis vectors in the transform columns.
        // The camera looks down its local -Z axis, so the world-space forward
        // gaze vector is the negated third column of the camera matrix.
        let forward = normalizedCameraForward(from: cameraTransform)

        // Place the anchor directly along the current camera ray, then lower it
        // slightly from eye level so the model appears centered and comfortable
        // in the viewport instead of spawning at world origin or behind the user.
        var target = cameraPosition + forward * forwardDistance
        target.y -= verticalEyeOffset

        transform.columns.3 = SIMD4<Float>(target.x, target.y, target.z, 1)
        return transform
    }

    static func position(from transform: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    private static func normalizedCameraForward(from cameraTransform: simd_float4x4) -> SIMD3<Float> {
        let negativeZ = SIMD3<Float>(
            -cameraTransform.columns.2.x,
            -cameraTransform.columns.2.y,
            -cameraTransform.columns.2.z
        )
        let rawLength = simd_length(negativeZ)
        guard rawLength > Float.ulpOfOne else { return SIMD3<Float>(0, 0, -1) }
        return negativeZ / rawLength
    }
}

private enum NormalizedModelNode {
    struct Result {
        let node: SCNNode
        let baseScale: Float
    }

    static func make(from node: SCNNode, targetMaxDimension: Float) -> Result {
        let (minB, maxB) = node.boundingBox
        let extent = SIMD3<Float>(
            maxB.x - minB.x,
            maxB.y - minB.y,
            maxB.z - minB.z
        )
        let maxDimension = max(extent.x, max(extent.y, extent.z))
        let scale = maxDimension > .ulpOfOne ? targetMaxDimension / maxDimension : 1

        let center = SIMD3<Float>(
            (minB.x + maxB.x) * 0.5,
            (minB.y + maxB.y) * 0.5,
            (minB.z + maxB.z) * 0.5
        )
        node.simdScale = SIMD3<Float>(repeating: scale)
        node.simdPosition = -center * scale
        return Result(node: node, baseScale: scale)
    }
}

// MARK: - Capture pipeline

private final class ARSnapshotCaptureService {
    func capture(from view: ARSCNView, completion: @escaping (UIImage) -> Void) {
        DispatchQueue.main.async {
            completion(view.snapshot())
        }
    }
}

private enum PhotoSaveResult {
    case success
    case denied
    case failure(Error?)
}

private final class PhotoLibrarySaver {
    func save(_ image: UIImage, completion: @escaping (PhotoSaveResult) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            performSave(image, completion: completion)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] newStatus in
                guard let self else { return }
                switch newStatus {
                case .authorized, .limited:
                    self.performSave(image, completion: completion)
                default:
                    completion(.denied)
                }
            }
        case .denied, .restricted:
            completion(.denied)
        @unknown default:
            completion(.denied)
        }
    }

    private func performSave(_ image: UIImage, completion: @escaping (PhotoSaveResult) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }, completionHandler: { success, error in
            completion(success ? .success : .failure(error))
        })
    }
}

private final class SnapshotPreviewViewController: UIViewController {
    private let image: UIImage
    private let object: CelestialObject?
    private let photoSaver = PhotoLibrarySaver()

    private let imageView = UIImageView()
    private let imageContainer = UIView()
    private let saveButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    init(image: UIImage, object: CelestialObject?) {
        self.image = image
        self.object = object
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        buildLayout()
    }

    // MARK: Layout (HIG-compliant)

    private func buildLayout() {
        // ── Native-style top bar: Cancel (X) · title · Save (checkmark) ──────
        let cancel = UIButton(type: .system)
        cancel.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancel.tintColor = .systemBlue
        cancel.accessibilityLabel = "Cancel"
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints = false

        saveButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        saveButton.tintColor = .systemBlue
        saveButton.accessibilityLabel = "Save to Photos"
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Snapshot"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .label
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        // ── Clean floating preview (rounded, subtle shadow, no border) ──────
        imageView.image = image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 18
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false

        imageContainer.layer.cornerRadius = 18
        imageContainer.layer.cornerCurve = .continuous
        imageContainer.layer.shadowColor = UIColor.black.cgColor
        imageContainer.layer.shadowOpacity = 0.18
        imageContainer.layer.shadowRadius = 16
        imageContainer.layer.shadowOffset = CGSize(width: 0, height: 8)
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageView)

        // ── Floating Share button (directly below the snapshot card) ────────
        // NOTE: ALL textual metadata (Phase, Illumination, distance, etc.) is
        // intentionally removed — the snapshot itself is the sole focus.
        var shareConfig = UIButton.Configuration.filled()
        shareConfig.title = "Share"
        shareConfig.image = UIImage(systemName: "square.and.arrow.up")
        shareConfig.imagePadding = 8
        shareConfig.baseBackgroundColor = .systemBlue
        shareConfig.cornerStyle = .capsule
        shareButton.configuration = shareConfig
        shareButton.accessibilityLabel = "Share"
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false

        [cancel, title, saveButton, imageContainer, shareButton].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            saveButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Snapshot card — the absolute centre of attention.
            imageContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
            imageContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            imageContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            imageContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.58),

            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            // Share floats directly below the card.
            shareButton.topAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: 28),
            shareButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 200),
            shareButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    // MARK: Actions

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func saveTapped() {
        saveButton.isEnabled = false
        photoSaver.save(image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveButton.isEnabled = true
                switch result {
                case .success:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.saveButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.dismiss(animated: true) }
                case .denied:
                    self.showAlert(title: "Photos Access Needed", message: "Allow photo access in Settings to save this snapshot.")
                case .failure:
                    self.showAlert(title: "Unable to Save", message: "The snapshot could not be saved. Please try again.")
                }
            }
        }
    }

    @objc private func shareTapped() {
        // Immediate tactile/visual feedback so the tap never feels "dead".
        UIView.animate(withDuration: 0.08, animations: {
            self.shareButton.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: { _ in
            UIView.animate(withDuration: 0.12) { self.shareButton.transform = .identity }
        })

        // Present on the NEXT main-runloop tick and feed the image through a
        // lazy UIActivityItemProvider (its `item` is fetched off the main thread
        // by the system), so building the share sheet never blocks the UI.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let provider = SnapshotItemProvider(image: self.image)
            let activity = UIActivityViewController(activityItems: [provider], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = self.shareButton
            activity.popoverPresentationController?.sourceRect = self.shareButton.bounds
            self.present(activity, animated: true)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Lazy share item (keeps the share sheet off the main thread)

/// Supplies the snapshot image to `UIActivityViewController`. The system reads
/// `item` on a background queue, so large-image handoff never blocks the UI.
private final class SnapshotItemProvider: UIActivityItemProvider {
    private let image: UIImage
    init(image: UIImage) {
        self.image = image
        super.init(placeholderItem: image)
    }
    override var item: Any { image }
}

// MARK: - Hint label (rounded translucent pill)

private final class PaddedHintLabel: UILabel {
    private let insets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        numberOfLines = 0
        textAlignment = .center
        font = .systemFont(ofSize: 15, weight: .semibold)
        textColor = .white
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        layer.cornerRadius = 14
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right,
                      height: s.height + insets.top + insets.bottom)
    }
}
