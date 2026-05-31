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

    /// Live-frame tap for analysis (sky segmentation). Set to a handler to receive
    /// rear-camera frames as `CVPixelBuffer`s, already rotated to PORTRAIT and in
    /// 32BGRA; set back to `nil` to stop the delivery cost. Called on a private
    /// queue, never the main thread. Independent of the on-screen preview layer.
    var onFrame: ((CVPixelBuffer) -> Void)? {
        get { frameDelegate.onFrame }
        set { frameDelegate.onFrame = newValue }
    }

    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "himmel.camera.video")
    private let frameDelegate = FrameDelegate()

    /// Forwards sample buffers to `onFrame` as bare pixel buffers. Kept as a tiny
    /// NSObject so `CameraPassthrough` itself need not inherit from NSObject.
    private final class FrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var onFrame: ((CVPixelBuffer) -> Void)?
        func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard let onFrame, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            onFrame(pb)
        }
    }

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

        // Frame tap for analysis (sky segmentation). Late frames are dropped so the
        // segmenter never queues up behind a slow inference. 32BGRA is what Vision /
        // Core Image consume most cheaply.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(frameDelegate, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()
    }

    private func applyPortraitOrientation() {
        // Rotate BOTH the on-screen preview and the analysis frames to portrait, so
        // the segmentation mask lines up 1:1 with what the user sees.
        rotateToPortrait(previewView.previewLayer.connection)
        rotateToPortrait(videoOutput.connection(with: .video))
    }

    private func rotateToPortrait(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90   // portrait
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}
