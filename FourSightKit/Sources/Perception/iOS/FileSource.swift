#if os(iOS)
import AVFoundation
import CoreVideo

/// Plays a recorded clip through the same pipeline as the live camera, paced to real time.
public final class FileSource: CaptureSource, @unchecked Sendable {
    public let frames: AsyncStream<CapturedFrame>
    /// `<clip>.camera.json` and `<clip>.jsonl` beside the clip, if they are there.
    /// The pipeline reads `ride.track` for the speed and heading the clip was recorded at.
    public let ride: RideSidecar
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    private let url: URL
    private var task: Task<Void, Never>?

    public init(url: URL) {
        self.url = url
        ride = RideSidecar(videoURL: url)
        var cont: AsyncStream<CapturedFrame>.Continuation?
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        continuation = cont
    }

    public func start() throws {
        task = Task { [url, continuation, camera = ride.camera] in
            do {
                let asset = AVURLAsset(url: url)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw CaptureError.noVideoTrack
                }
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings:
                    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                reader.add(output)
                reader.startReading()
                let wall = Date()
                var first: Double?
                var intrinsics: Intrinsics?
                while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
                    guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    let base = first ?? pts
                    if first == nil, let camera {
                        // The sidecar is written for the clip beside it, but rescale anyway in
                        // case the clip was transcoded after extraction.
                        let scaled = camera.scaled(toWidth: Double(CVPixelBufferGetWidth(pb)),
                                                   height: Double(CVPixelBufferGetHeight(pb)))
                        intrinsics = Intrinsics(fx: scaled.f, fy: scaled.f, cx: scaled.u0, cy: scaled.v0)
                    }
                    first = base
                    let due = pts - base - Date().timeIntervalSince(wall)
                    if due > 0 { try await Task.sleep(nanoseconds: UInt64(due * 1e9)) }
                    continuation?.yield(CapturedFrame(pixelBuffer: pb, timestamp: pts, intrinsics: intrinsics,
                                                      cameraHeight: camera?.cameraHeight))
                }
            } catch {}
            continuation?.finish()
        }
    }

    public func stop() { task?.cancel() }
}
#endif
