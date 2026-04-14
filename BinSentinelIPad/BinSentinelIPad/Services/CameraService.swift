import AVFoundation
import Combine
import CoreGraphics
import UIKit

final class CameraService: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var motionLevel: Double = 0
    @Published var autoCaptureSignal = 0
    /// Normalized metadata-output rect (top-left origin) for salient “object” highlight on the preview.
    @Published var salientMetadataRect: CGRect?

    private let output = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var photoCaptureContinuation: CheckedContinuation<UIImage, Error>?
    private let videoQueue = DispatchQueue(label: "binsentinel.video.queue")

    private var previousAverageLuma: Double?
    private var stableFrameCount = 0
    private var sawMotion = false
    private var frameCounter = 0
    private var lastAutoSignalAt = Date.distantPast

    private let motionThreshold = 2.4
    private let stableThreshold = 0.7
    private let stableFramesRequired = 8
    private let signalCooldownSeconds: TimeInterval = 2.0

    private var lastSaliencyAt: CFTimeInterval = 0
    private let saliencyMinInterval: CFTimeInterval = 0.35
    private let cameraPosition: AVCaptureDevice.Position = .front

    private var smoothedRect: CGRect?
    private var nilRectStreak = 0
    private let nilGracePeriod = 5
    private let smoothingFactor: CGFloat = 0.25

    func configureSession() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }

        guard authorizationStatus == .authorized else { return }
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        defer {
            session.commitConfiguration()
        }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input),
            session.canAddOutput(output),
            session.canAddOutput(videoOutput)
        else {
            return
        }

        session.addInput(input)
        session.addOutput(output)
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        syncCaptureConnections(videoOrientation: .portrait)
    }

    /// Aligns still capture + motion frames with `AVCaptureVideoPreviewLayer` (updated from window interface orientation).
    func syncCaptureConnections(videoOrientation: AVCaptureVideoOrientation) {
        if let c = output.connection(with: .video), c.isVideoOrientationSupported {
            c.videoOrientation = videoOrientation
        }
        if let c = videoOutput.connection(with: .video), c.isVideoOrientationSupported {
            c.videoOrientation = videoOrientation
        }
    }

    func startRunning() {
        guard authorizationStatus == .authorized else { return }
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                self.session.startRunning()
            }
        }
    }

    func stopRunning() {
        DispatchQueue.main.async { [weak self] in
            self?.salientMetadataRect = nil
        }
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            photoCaptureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard authorizationStatus == .authorized else { return }

        frameCounter += 1

        if frameCounter % 8 == 0,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let now = CACurrentMediaTime()
            if now - lastSaliencyAt >= saliencyMinInterval {
                lastSaliencyAt = now
                let orientation = connection.videoOrientation
                let rawRect = SalientRegionDetector.mostSalientMetadataRect(
                    pixelBuffer: pixelBuffer,
                    videoOrientation: orientation,
                    cameraPosition: cameraPosition
                )
                let finalRect = self.applySmoothing(rawRect)
                DispatchQueue.main.async { [weak self] in
                    self?.salientMetadataRect = finalRect
                }
            }
        }

        if frameCounter % 3 != 0 {
            return
        }

        guard
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let avgLuma = averageLuma(from: pixelBuffer)
        else { return }

        let delta: Double
        if let previous = previousAverageLuma {
            delta = abs(avgLuma - previous)
        } else {
            delta = 0
        }
        previousAverageLuma = avgLuma

        if delta > motionThreshold {
            sawMotion = true
            stableFrameCount = 0
        } else if delta < stableThreshold {
            stableFrameCount += 1
        } else {
            stableFrameCount = 0
        }

        let now = Date()
        if sawMotion &&
            stableFrameCount >= stableFramesRequired &&
            now.timeIntervalSince(lastAutoSignalAt) > signalCooldownSeconds {
            sawMotion = false
            stableFrameCount = 0
            lastAutoSignalAt = now
            DispatchQueue.main.async { [weak self] in
                self?.autoCaptureSignal += 1
            }
        }

        let normalized = min(max(delta / 8.0, 0), 1)
        DispatchQueue.main.async { [weak self] in
            self?.motionLevel = normalized
        }
    }

    private func applySmoothing(_ raw: CGRect?) -> CGRect? {
        guard let raw else {
            nilRectStreak += 1
            if nilRectStreak >= nilGracePeriod {
                smoothedRect = nil
            }
            return smoothedRect
        }
        nilRectStreak = 0
        guard let prev = smoothedRect else {
            smoothedRect = raw
            return raw
        }
        let a = smoothingFactor
        let result = CGRect(
            x: prev.minX + a * (raw.minX - prev.minX),
            y: prev.minY + a * (raw.minY - prev.minY),
            width: prev.width + a * (raw.width - prev.width),
            height: prev.height + a * (raw.height - prev.height)
        )
        smoothedRect = result
        return result
    }

    private func averageLuma(from pixelBuffer: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return nil
        }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let step = 8
        var sum = 0.0
        var count = 0.0

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * bytesPerRow + x
                sum += Double(buffer[offset])
                count += 1
                x += step
            }
            y += step
        }

        guard count > 0 else { return nil }
        return sum / count
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            photoCaptureContinuation?.resume(throwing: error)
            photoCaptureContinuation = nil
            return
        }

        guard
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            photoCaptureContinuation?.resume(throwing: APIClientError.serializationFailed)
            photoCaptureContinuation = nil
            return
        }

        photoCaptureContinuation?.resume(returning: image)
        photoCaptureContinuation = nil
    }
}
