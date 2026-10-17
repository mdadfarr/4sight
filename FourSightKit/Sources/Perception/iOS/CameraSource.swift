#if os(iOS)
import AVFoundation

public final class CameraSource: NSObject, CaptureSource, AVCaptureVideoDataOutputSampleBufferDelegate,
                                 @unchecked Sendable {
    public let frames: AsyncStream<CapturedFrame>
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    /// For an AVCaptureVideoPreviewLayer; the pipeline never touches it otherwise.
    public let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "foursight.camera")

    public override init() {
        var cont: AsyncStream<CapturedFrame>.Continuation?
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        super.init()
        continuation = cont
    }

    public func start() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { throw CaptureError.noCamera }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
        session.addOutput(output)

        if let conn = output.connection(with: .video) {
            if conn.isVideoStabilizationSupported { conn.preferredVideoStabilizationMode = .off }
            if conn.isCameraIntrinsicMatrixDeliverySupported { conn.isCameraIntrinsicMatrixDeliveryEnabled = true }
        }
        session.commitConfiguration()

        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        // Everything of interest is >5 m away; a hunting autofocus would corrupt box areas.
        if device.isLockingFocusWithCustomLensPositionSupported {
            device.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil)
        }
        device.unlockForConfiguration()

        queue.async { self.session.startRunning() }
    }

    public func stop() { queue.async { self.session.stopRunning() } }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        continuation?.yield(CapturedFrame(pixelBuffer: pb, timestamp: ts,
                                          intrinsics: CapturedFrame.intrinsics(from: sampleBuffer)))
    }
}

public enum CaptureError: Error { case noCamera, cannotAddInput, cannotAddOutput, noVideoTrack }
#endif
