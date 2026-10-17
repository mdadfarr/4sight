#if os(iOS)
import AVFoundation
import CoreVideo

public struct Intrinsics: Sendable {
    public var fx: Double, fy: Double, cx: Double, cy: Double
    public init(fx: Double, fy: Double, cx: Double, cy: Double) {
        self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy
    }
}

public struct CapturedFrame: @unchecked Sendable {
    public var pixelBuffer: CVPixelBuffer
    public var timestamp: TimeInterval
    public var intrinsics: Intrinsics?
    /// Lens height above the road, metres, when the source knows it (replayed rides do).
    public var cameraHeight: Double?

    public init(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval,
                intrinsics: Intrinsics? = nil, cameraHeight: Double? = nil) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
        self.intrinsics = intrinsics
        self.cameraHeight = cameraHeight
    }
}

public protocol CaptureSource: AnyObject {
    var frames: AsyncStream<CapturedFrame> { get }
    func start() throws
    func stop()
}

extension CapturedFrame {
    /// Reads the per-frame intrinsic matrix attached by AVFoundation when delivery is enabled.
    static func intrinsics(from sample: CMSampleBuffer) -> Intrinsics? {
        guard let att = CMGetAttachment(sample, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                        attachmentModeOut: nil) else { return nil }
        let data = att as! CFData as Data
        guard data.count >= MemoryLayout<matrix_float3x3>.size else { return nil }
        let m = data.withUnsafeBytes { $0.load(as: matrix_float3x3.self) }
        return Intrinsics(fx: Double(m.columns.0.x), fy: Double(m.columns.1.y),
                          cx: Double(m.columns.2.x), cy: Double(m.columns.2.y))
    }
}
#endif
