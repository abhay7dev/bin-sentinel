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
    var onVideoOrientationResolved: ((AVCaptureVideoOrientation) -> Void)?
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

    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .dark)
        let v = UIVisualEffectView(effect: blur)
        v.isUserInteractionEnabled = false
        v.alpha = 0.85
        v.isHidden = true
        return v
    }()

    private let blurMaskLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(blurView)
        addSubview(highlightBorderView)
        blurView.layer.mask = blurMaskLayer
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(blurView)
        addSubview(highlightBorderView)
        blurView.layer.mask = blurMaskLayer
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
        blurView.frame = bounds

        guard let connection = videoPreviewLayer.connection else { return }

        let uiOrientation = window?.windowScene?.interfaceOrientation ?? .portrait
        let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: uiOrientation)

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }

        onVideoOrientationResolved?(videoOrientation)

        if let meta = highlightMetadataRect {
            let lr = videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: meta)
            let validBox = lr.width >= 2 && lr.height >= 2

            highlightBorderView.frame = lr
            highlightBorderView.isHidden = !validBox
            blurView.isHidden = !validBox

            if validBox {
                let fullPath = UIBezierPath(rect: bounds)
                let cutout = UIBezierPath(roundedRect: lr, cornerRadius: 12)
                fullPath.append(cutout)
                fullPath.usesEvenOddFillRule = true
                blurMaskLayer.fillRule = .evenOdd
                blurMaskLayer.path = fullPath.cgPath
            }
        } else {
            highlightBorderView.isHidden = true
            blurView.isHidden = true
        }
        bringSubviewToFront(blurView)
        bringSubviewToFront(highlightBorderView)
    }
}
