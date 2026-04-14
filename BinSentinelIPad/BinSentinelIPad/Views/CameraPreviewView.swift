import AVFoundation
import SwiftUI
import UIKit

extension AVCaptureVideoOrientation {
    init(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: self = .portrait
        }
    }

}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Normalized metadata rect for salient-object highlight (see `CameraService.salientMetadataRect`).
    var highlightMetadataRect: CGRect?
    /// Keeps photo + motion-analysis connections aligned with the preview when the device rotates.
    var onVideoOrientationChange: (AVCaptureVideoOrientation) -> Void = { _ in }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onVideoOrientationResolved = onVideoOrientationChange
        view.highlightMetadataRect = highlightMetadataRect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.onVideoOrientationResolved = onVideoOrientationChange
        uiView.highlightMetadataRect = highlightMetadataRect
        uiView.setNeedsLayout()
    }
}

final class PreviewView: UIView {
    /// Called from `layoutSubviews` after applying the same orientation to the preview layer.
    var onVideoOrientationResolved: ((AVCaptureVideoOrientation) -> Void)?
    /// Normalized metadata-output coordinates (origin top-left) for `layerRectConverted(fromMetadataOutputRect:)`.
    var highlightMetadataRect: CGRect?

    private let highlightBorderView: UIView = {
        let v = UIView()
        v.layer.borderColor = UIColor.systemGreen.cgColor
        v.layer.borderWidth = 3
        v.layer.cornerRadius = 12
        v.layer.cornerCurve = .continuous
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(highlightBorderView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(highlightBorderView)
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        videoPreviewLayer.masksToBounds = true
        guard let connection = videoPreviewLayer.connection else { return }

        let uiOrientation = window?.windowScene?.interfaceOrientation ?? .portrait
        let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: uiOrientation)

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }

        onVideoOrientationResolved?(videoOrientation)

        if let meta = highlightMetadataRect {
            let lr = videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: meta)
            highlightBorderView.frame = lr
            highlightBorderView.isHidden = lr.width < 2 || lr.height < 2
        } else {
            highlightBorderView.isHidden = true
        }
        bringSubviewToFront(highlightBorderView)
    }
}
