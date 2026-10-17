#if os(iOS)
import AVFoundation

/// Plays a recorded clip through the same pipeline as the live camera, paced to real time.
public final class FileSource: CaptureSource, @unchecked Sendable {
    public let frames: AsyncStream<CapturedFrame>
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    private let url: URL
    private var task: Task<Void, Never>?

    public init(url: URL) {
        self.url = url
        var cont: AsyncStream<CapturedFrame>.Continuation?
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        continuation = cont
    }

    public func start() throws {
        task = Task { [url, continuation] in
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
                var wall = Date()
                var first: Double?
                while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
                    guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    var due = pts - (first ?? pts) - Date().timeIntervalSince(wall)
                    // Decoder itself more than 1 s behind (overloaded host): restart pacing from here.
                    if first == nil || due < -1 { first = pts; wall = Date(); due = 0 }
                    if due > 0 { try await Task.sleep(nanoseconds: UInt64(due * 1e9)) }
                    // Late frame: drop it here like a live camera would. Yielding it would let the
                    // reader's pixel-buffer pool back-pressure us into consumer-paced playback.
                    if due < -0.05 { continue }
                    continuation?.yield(CapturedFrame(pixelBuffer: pb, timestamp: pts, intrinsics: nil))
                }
            } catch {}
            continuation?.finish()
        }
    }

    public func stop() { task?.cancel() }
}
#endif
