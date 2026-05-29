//
//  CameraPassthrough.swift
//  Himmel
//
//  Live rear-camera passthrough layer for "Live AR Mode". It renders the real
//  world behind the (now transparent) SceneKit star overlay, so the data-driven
//  celestial nodes — already heading/gravity aligned by CoreMotion — appear
//  composited over the physical sky.
//
//  Single responsibility: this type only owns the AVCaptureSession + preview
//  layer. The SceneKit tracking / node logic stays entirely in SkySceneCoordinator.
//

import AVFoundation
import UIKit

final class CameraPassthrough {

    /// A UIView whose backing layer IS the camera preview — insert it behind the
    /// SCNView in the view hierarchy.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    let previewView = PreviewView()

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "himmel.camera.session")
    private var isConfigured = false

    init() {
        previewView.previewLayer.videoGravity = .resizeAspectFill
        previewView.previewLayer.session = session
        previewView.isHidden = true
        previewView.isUserInteractionEnabled = false
    }

    /// Approximate vertical field of view (degrees) of the iPhone wide camera in
    /// portrait. The SceneKit camera is matched to this so the overlaid stars line
    /// up reasonably with the real sky.
    var approximateVerticalFOV: CGFloat { 60 }

    /// Request camera permission (if needed), configure and start the session.
    /// `completion(true)` only when the live feed is running.
    func start(completion: @escaping (Bool) -> Void) {
        let proceed: (Bool) -> Void = { [weak self] granted in
            guard let self, granted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.sessionQueue.async {
                self.configureIfNeeded()
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async {
                    self.previewView.isHidden = false
                    self.applyPortraitOrientation()
                    completion(true)
                }
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            proceed(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { proceed($0) }
        default:
            proceed(false)   // denied / restricted
        }
    }

    /// Stop the live feed and hide the preview.
    func stop() {
        previewView.isHidden = true
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Internals

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        } else {
            NSLog("[Himmel] Live AR: no usable rear camera input.")
        }
        session.commitConfiguration()
    }

    private func applyPortraitOrientation() {
        guard let connection = previewView.previewLayer.connection else { return }
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90   // portrait
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}
