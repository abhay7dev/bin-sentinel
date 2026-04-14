import AVFoundation
import CoreGraphics
import Vision

/// Maps live video buffer → normalized “metadata” rect (origin top-left) for `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)`.
enum SalientRegionDetector {
    /// Minimum salient area (normalized 0–1) before drawing a highlight.
    private static let minimumArea: CGFloat = 0.04

    static func mostSalientMetadataRect(
        pixelBuffer: CVPixelBuffer,
        videoOrientation: AVCaptureVideoOrientation,
        cameraPosition: AVCaptureDevice.Position
    ) -> CGRect? {
        let imageOrientation = videoOrientation.cgImagePropertyOrientation(for: cameraPosition)
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: imageOrientation, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first as? VNSaliencyImageObservation else {
                return nil
            }
            let regions = obs.salientObjects ?? []
            guard !regions.isEmpty else { return nil }
            let best = regions.max(by: { $0.boundingBox.area < $1.boundingBox.area })!
            guard best.boundingBox.area >= minimumArea else { return nil }
            return visionBoundingBoxToMetadataRect(best.boundingBox)
        } catch {
            return nil
        }
    }

    /// Vision uses normalized coords, origin **bottom-left**.
    private static func visionBoundingBoxToMetadataRect(_ vn: CGRect) -> CGRect {
        CGRect(x: vn.minX, y: 1.0 - vn.maxY, width: vn.width, height: vn.height)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

extension AVCaptureVideoOrientation {
    /// Orientation of pixel data for Vision (depends on front vs back camera).
    func cgImagePropertyOrientation(for cameraPosition: AVCaptureDevice.Position) -> CGImagePropertyOrientation {
        let front = cameraPosition == .front
        switch self {
        case .portrait:
            return front ? .leftMirrored : .right
        case .portraitUpsideDown:
            return front ? .rightMirrored : .left
        case .landscapeRight:
            return front ? .downMirrored : .up
        case .landscapeLeft:
            return front ? .upMirrored : .down
        @unknown default:
            return .up
        }
    }
}
