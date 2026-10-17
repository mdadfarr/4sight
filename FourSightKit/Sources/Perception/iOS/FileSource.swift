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
                let wall = Date()
                var first: Double?
                while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
                    guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    let base = first ?? pts
                    first = base
                    let due = pts - base - Date().timeIntervalSince(wall)
                    if due > 0 { try await Task.sleep(nanoseconds: UInt64(due * 1e9)) }
                    continuation?.yield(CapturedFrame(pixelBuffer: pb, timestamp: pts, intrinsics: nil))
                }
            } catch {}
            continuation?.finish()
        }
    }

    public func stop() { task?.cancel() }
}
#endif
