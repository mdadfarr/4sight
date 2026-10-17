#if os(iOS)
import AVFoundation

public final class CameraSource: NSObject, CaptureSource, AVCaptureVideoDataOutputSampleBufferDelegate,
                                 @unchecked Sendable {
    public let frames: AsyncStream<CapturedFrame>
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    /// For an AVCaptureVideoPreviewLayer; the pipeline never touches it otherwise.
    public let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "foursight.camera")
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

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
            // Turn every frame upright by gravity, like the Camera app. The detector is only good
            // on upright people and cars, and "image right = rider's left" only holds upright, so
            // this makes detection and the left/right grip correct however the phone is mounted.
            let rc = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            let apply = { [weak conn] in
                guard let conn else { return }
                let angle = rc.videoRotationAngleForHorizonLevelCapture
                if conn.isVideoRotationAngleSupported(angle) { conn.videoRotationAngle = angle }
            }
            apply()
            rotation = rc
            rotationObservation = rc.observe(\.videoRotationAngleForHorizonLevelCapture) { [queue] _, _ in
                queue.async { apply() }
            }
        }
        session.commitConfiguration()

        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        // Focus: locked at infinity left anything nearer than a few metres soft (people indoors,
        // a car at the moment it passes), and soft boxes flicker and mis-size. Continuous AF biased
        // far, with smooth (slow) focus moves so box sizes don't breathe frame to frame.
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .far }
        if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
        // Exposure: cap it at 1/250 s. Auto exposure otherwise stretches to 1/30 s in shade or
        // indoors, and rack vibration plus a passing car smear into a blur the detector misses.
        // Costs some noise in low light, which the detector tolerates far better than blur.
        let cap = CMTime(value: 1, timescale: 250)
        if device.exposureMode == .continuousAutoExposure || device.exposureMode == .autoExpose,
           CMTimeCompare(cap, device.activeFormat.minExposureDuration) >= 0,
           CMTimeCompare(cap, device.activeFormat.maxExposureDuration) <= 0 {
            device.activeMaxExposureDuration = cap
        }
        device.unlockForConfiguration()

        queue.async { self.session.startRunning() }
    }

    public func stop() { queue.async { self.session.stopRunning() } }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        // Focal length from the delivered matrix (square pixels, so it survives a 90 degree turn);
        // principal point at the buffer centre. shortcut: the true centre is within a few px on
        // iPhone, and the delivered cx/cy may be in the unrotated sensor frame; calibrate if gaps drift.
        let intrinsics = CapturedFrame.intrinsics(from: sampleBuffer).map {
            Intrinsics(fx: $0.fx, fy: $0.fx, cx: Double(CVPixelBufferGetWidth(pb)) / 2,
                       cy: Double(CVPixelBufferGetHeight(pb)) / 2)
        }
        continuation?.yield(CapturedFrame(pixelBuffer: pb, timestamp: ts, intrinsics: intrinsics))
    }
}

public enum CaptureError: Error { case noCamera, cannotAddInput, cannotAddOutput, noVideoTrack }
#endif
