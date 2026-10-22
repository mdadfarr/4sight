import AVFoundation
import Perception
import Protocol
import SwiftUI
import UIKit

/// Live camera (or replay frame) with detection boxes drawn over it.
struct RearPreview: UIViewRepresentable {
    let session: AVCaptureSession?
    let image: CGImage?
    let tracks: [OverlayTrack]

    func makeUIView(context: Context) -> PreviewUIView { PreviewUIView() }

    func updateUIView(_ v: PreviewUIView, context: Context) {
        if v.previewLayer.session !== session { v.previewLayer.session = session }
        v.imageLayer.contents = image
        v.imageLayer.isHidden = session != nil
        v.draw(tracks)
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    let imageLayer = CALayer()
    private var boxes: [CAShapeLayer] = []
    private var labels: [CATextLayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspect
        imageLayer.contentsGravity = .resizeAspect
        layer.addSublayer(imageLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageLayer.frame = bounds
    }

    func draw(_ tracks: [OverlayTrack]) {
        while boxes.count < tracks.count {
            let l = CAShapeLayer(); l.fillColor = nil; l.lineWidth = 2
            layer.addSublayer(l); boxes.append(l)
            let t = CATextLayer(); t.fontSize = 11; t.truncationMode = .end; t.contentsScale = UIScreen.main.scale
            t.foregroundColor = UIColor.white.cgColor; t.backgroundColor = UIColor.black.withAlphaComponent(0.6).cgColor
            layer.addSublayer(t); labels.append(t)
        }
        for (i, l) in boxes.enumerated() {
            guard i < tracks.count else { l.path = nil; labels[i].isHidden = true; continue }
            let t = tracks[i]
            let r = previewLayer.session != nil
                ? previewLayer.layerRectConverted(fromMetadataOutputRect: t.rect)
                : fitted(t.rect)
            l.path = UIBezierPath(rect: r).cgPath
            l.strokeColor = (t.level >= 2 ? UIColor(Theme.red) : t.level == 1 ? UIColor(Theme.amber) : UIColor(Theme.edge)).cgColor
            // Distance on every box, so a range estimate can be checked against a tape measure.
            let label = labels[i]
            label.isHidden = false
            label.string = String(format: " %@ %.1f m ", t.cls.rawValue, t.z)
            // Sized to its text and placed inside the box's top edge, so neighbours don't overlap.
            let size = label.preferredFrameSize()
            label.frame = CGRect(x: r.minX, y: r.minY, width: min(size.width, max(r.width, 40)), height: size.height)
        }
    }

    /// Normalised rect → layer rect for the aspect-fitted replay image.
    private func fitted(_ r: CGRect) -> CGRect {
        guard let img = imageLayer.contents else { return .zero }
        let iw = CGFloat(CFGetTypeID(img as CFTypeRef) == CGImage.typeID ? (img as! CGImage).width : 16)
        let ih = CGFloat(CFGetTypeID(img as CFTypeRef) == CGImage.typeID ? (img as! CGImage).height : 9)
        let scale = min(bounds.width / iw, bounds.height / ih)
        let w = iw * scale, h = ih * scale
        let ox = (bounds.width - w) / 2, oy = (bounds.height - h) / 2
        return CGRect(x: ox + r.minX * w, y: oy + r.minY * h, width: r.width * w, height: r.height * h)
    }
}
