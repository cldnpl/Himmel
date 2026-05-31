//
//  SkySegmenter.swift
//  Himmel
//
//  Live "sky vs. not-sky" segmentation for Live AR Mode.
//
//  WHY THIS EXISTS
//  ---------------
//  Live AR draws the celestial overlay (stars / planets / constellation lines /
//  labels) over a flat rear-camera passthrough, aligned only by CoreMotion. That
//  pipeline has NO depth and NO scene understanding, so by default the overlay
//  bleeds onto whatever the phone is pointed at — a tent, a building, the ground.
//
//  This type looks at the live camera frame and classifies each region as SKY or
//  NOT-SKY using a bundled CoreML semantic-segmentation model, then emits a soft
//  ALPHA MASK (opaque where sky, transparent elsewhere). The coordinator uses that
//  mask to clip the overlay so celestial bodies appear ONLY over real sky.
//
//  GRACEFUL DEGRADATION
//  --------------------
//  If no segmentation model is bundled, `isAvailable` stays false and the type is
//  completely inert — Live AR behaves exactly as before (overlay everywhere). So
//  the app builds and runs with or without the model; dropping the model in is
//  purely additive.
//
//  ADDING THE MODEL (one-time, in Xcode)
//  -------------------------------------
//  1. Obtain a semantic-segmentation Core ML model whose label set includes a
//     "sky" class. The reference target is an **ADE20K**-trained DeepLabV3
//     (`.mlpackage` / `.mlmodel`), where the sky class index is **2**.
//  2. Drag it into the Xcode project (any group; "Copy items if needed", add to
//     the Himmel target). Xcode compiles it to a `*.mlmodelc` in the app bundle.
//  3. If your model's sky class index differs from 2, change `skyClassIndex`.
//     If its compiled name differs, it's still found (we scan for any
//     `*.mlmodelc`), but you can also rename it to `SkySegmentation` to be explicit.
//

import Foundation
import Vision
import CoreML
import CoreImage
import QuartzCore

final class SkySegmenter {

    /// Preferred compiled-model resource name. Any `*.mlmodelc` in the bundle is
    /// accepted as a fallback, so the exact name is not load-bearing.
    static let preferredModelName = "SkySegmentation"

    /// Class index that means "sky" in the model's label map. ADE20K → 2.
    var skyClassIndex: Int = 2

    /// True only when a usable model was found and compiled. When false the type
    /// does nothing and callers should leave the overlay unmasked.
    private(set) var isAvailable = false

    /// Delivered on the MAIN actor with a fresh alpha mask: opaque (white) where
    /// sky was detected, clear elsewhere, already scaled to the portrait frame's
    /// aspect ratio so it composes 1:1 with the camera preview (resizeAspectFill).
    var onMask: ((CGImage) -> Void)?

    // MARK: - Internals

    private var visionModel: VNCoreMLModel?
    private let workQueue = DispatchQueue(label: "himmel.sky.segmenter", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Throttle: run at most ~8 segmentations/sec. The boundary moves slowly with
    /// device motion, and inference is the expensive part — no need to run at 60fps.
    private let minInterval: CFTimeInterval = 1.0 / 8.0
    private var lastRun: CFTimeInterval = 0
    private var inFlight = false

    init() {
        loadModel()
    }

    // MARK: - Model loading

    private func loadModel() {
        guard let url = Self.locateCompiledModel() else {
            isAvailable = false
            return
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let mlModel = try? MLModel(contentsOf: url, configuration: config),
              let vn = try? VNCoreMLModel(for: mlModel) else {
            isAvailable = false
            return
        }
        visionModel = vn
        isAvailable = true
    }

    /// Find a compiled Core ML model in the app bundle. Prefers the canonical name,
    /// then falls back to ANY `*.mlmodelc`, so the user can drop in any sky model.
    private static func locateCompiledModel() -> URL? {
        if let url = Bundle.main.url(forResource: preferredModelName, withExtension: "mlmodelc") {
            return url
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: nil
        ) else { return nil }
        return contents.first { $0.pathExtension == "mlmodelc" }
    }

    // MARK: - Per-frame entry point

    /// Feed a live PORTRAIT camera frame. Cheap to call every frame: it self-throttles
    /// and drops frames while an inference is in flight. No-op if no model is loaded.
    func process(pixelBuffer: CVPixelBuffer) {
        guard isAvailable, let visionModel else { return }
        let now = CACurrentMediaTime()
        guard !inFlight, now - lastRun >= minInterval else { return }
        inFlight = true
        lastRun = now

        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)

        workQueue.async { [weak self] in
            guard let self else { return }
            defer { self.inFlight = false }

            let request = VNCoreMLRequest(model: visionModel)
            // Stretch the (square-ish) model input to the full frame so the output
            // maps linearly back onto the whole frame — no cropped-out edges.
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: .up,
                                                options: [:])
            do {
                try handler.perform([request])
            } catch {
                return
            }

            guard let mask = self.makeMask(from: request.results,
                                           frameWidth: frameWidth,
                                           frameHeight: frameHeight) else { return }
            DispatchQueue.main.async { self.onMask?(mask) }
        }
    }

    // MARK: - Mask construction

    /// Turn the model's segmentation output into a soft alpha mask scaled to the
    /// camera frame's aspect ratio. Handles the two common output shapes:
    ///   • `VNCoreMLFeatureValueObservation` carrying an `MLMultiArray` of class ids
    ///   • `VNPixelBufferObservation` carrying a single-channel label image
    private func makeMask(from results: [VNObservation]?,
                          frameWidth: Int,
                          frameHeight: Int) -> CGImage? {
        guard let results else { return nil }

        var base: CGImage?
        if let feature = results.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first,
           let multiArray = feature.featureValue.multiArrayValue {
            base = maskImage(from: multiArray)
        } else if let pixelObs = results.compactMap({ $0 as? VNPixelBufferObservation }).first {
            base = maskImage(from: pixelObs.pixelBuffer)
        }

        guard let base else { return nil }
        return finalize(base, frameWidth: frameWidth, frameHeight: frameHeight)
    }

    /// Build an opaque-white / clear RGBA image from an `[..., H, W]` class-id array.
    private func maskImage(from array: MLMultiArray) -> CGImage? {
        let shape = array.shape.map { $0.intValue }
        guard shape.count >= 2 else { return nil }
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        guard width > 0, height > 0 else { return nil }

        let strides = array.strides.map { $0.intValue }
        let hStride = strides[strides.count - 2]
        let wStride = strides[strides.count - 1]

        let count = width * height
        var pixels = [UInt8](repeating: 0, count: count * 4)

        // Read as Int32 (class ids). Core ML segmentation maps are typically Int32.
        let sky = Int32(skyClassIndex)
        array.dataPointer.withMemoryRebound(to: Int32.self, capacity: array.count) { ptr in
            for y in 0..<height {
                let rowBase = y * hStride
                for x in 0..<width {
                    if ptr[rowBase + x * wStride] == sky {
                        let i = (y * width + x) * 4
                        pixels[i] = 255       // R
                        pixels[i + 1] = 255   // G
                        pixels[i + 2] = 255   // B
                        pixels[i + 3] = 255   // A (opaque → visible)
                    }
                }
            }
        }
        return rgbaImage(from: &pixels, width: width, height: height)
    }

    /// Build the alpha mask from a single-channel label `CVPixelBuffer` (8-bit).
    private func maskImage(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let src = baseAddress.assumingMemoryBound(to: UInt8.self)

        let sky = UInt8(truncatingIfNeeded: skyClassIndex)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let rowBase = y * rowBytes
            for x in 0..<width where src[rowBase + x] == sky {
                let i = (y * width + x) * 4
                pixels[i] = 255; pixels[i + 1] = 255; pixels[i + 2] = 255; pixels[i + 3] = 255
            }
        }
        return rgbaImage(from: &pixels, width: width, height: height)
    }

    private func rgbaImage(from pixels: inout [UInt8], width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: info) else { return nil }
        return ctx.makeImage()
    }

    /// Scale the raw (model-resolution) mask to the frame aspect ratio and soften
    /// the edge so the overlay fades in/out at the sky boundary instead of a hard,
    /// aliased cut. Returns a CGImage suitable as a CALayer mask (uses its alpha).
    private func finalize(_ image: CGImage, frameWidth: Int, frameHeight: Int) -> CGImage? {
        var ci = CIImage(cgImage: image)

        // Stretch the (scaleFill) model output to the portrait frame's dimensions so
        // the mask matches the previewed camera pixels under resizeAspectFill.
        let sx = CGFloat(frameWidth) / CGFloat(image.width)
        let sy = CGFloat(frameHeight) / CGFloat(image.height)
        ci = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        // Soft edge.
        ci = ci.applyingGaussianBlur(sigma: 3.0)
            .cropped(to: CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))

        return ciContext.createCGImage(ci, from: ci.extent)
    }
}
