import AVFoundation
import CoreGraphics
import Vision

/// Maps live video buffer → normalized "metadata" rect (origin top-left) for `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)`.
enum SalientRegionDetector {
    private static let minimumArea: CGFloat = 0.03
    private static let maximumArea: CGFloat = 0.85

    static func mostSalientMetadataRect(
        pixelBuffer: CVPixelBuffer,
        videoOrientation: AVCaptureVideoOrientation,
        cameraPosition: AVCaptureDevice.Position
    ) -> CGRect? {
        let imageOrientation = videoOrientation.cgImagePropertyOrientation(for: cameraPosition)

        let objectnessReq = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attentionReq = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: imageOrientation, options: [:])
        do {
            try handler.perform([objectnessReq, attentionReq])

            let objectRegions = (objectnessReq.results?.first as? VNSaliencyImageObservation)?.salientObjects ?? []
            let attentionRegions = (attentionReq.results?.first as? VNSaliencyImageObservation)?.salientObjects ?? []

            let isFront = cameraPosition == .front

            let validObjects = objectRegions.filter {
                $0.boundingBox.area >= minimumArea && $0.boundingBox.area <= maximumArea
            }
            if let bestObj = validObjects.max(by: { $0.confidence < $1.confidence }) {
                return visionBoundingBoxToMetadataRect(bestObj.boundingBox, mirrorX: isFront)
            }

            let validAttention = attentionRegions.filter {
                $0.boundingBox.area >= minimumArea && $0.boundingBox.area <= maximumArea
            }
            if let bestAtt = validAttention.max(by: { $0.confidence < $1.confidence }) {
                return visionBoundingBoxToMetadataRect(bestAtt.boundingBox, mirrorX: isFront)
            }

            return nil
        } catch {
            return nil
        }
    }

    /// Vision normalized coords (origin bottom-left) → metadata coords (origin top-left).
    /// Front camera preview is auto-mirrored by AVCaptureVideoPreviewLayer, so we flip x to match.
    private static func visionBoundingBoxToMetadataRect(_ vn: CGRect, mirrorX: Bool) -> CGRect {
        let x = mirrorX ? (1.0 - vn.maxX) : vn.minX
        return CGRect(x: x, y: 1.0 - vn.maxY, width: vn.width, height: vn.height)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

extension AVCaptureVideoOrientation {
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
