import AVFoundation
import CoreVideo
import Foundation

/// Writes the camera frames to Documents/ride-<stamp>.mov and GPS fixes to ride-<stamp>.jsonl.
nonisolated final class RideLogger: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let gps: FileHandle
    private var started = false
    private let queue = DispatchQueue(label: "foursight.ridelog")

    init(width: Int, height: Int) throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let base = docs.appendingPathComponent("ride-\(stamp)")
        writer = try AVAssetWriter(outputURL: base.appendingPathExtension("mov"), fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        let jsonl = base.appendingPathExtension("jsonl")
        FileManager.default.createFile(atPath: jsonl.path, contents: nil)
        gps = try FileHandle(forWritingTo: jsonl)
    }

    func append(_ pixelBuffer: CVPixelBuffer, at seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if !started {
            started = true
            writer.startWriting()
            writer.startSession(atSourceTime: time)
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    /// One JSON object per line: {"t","lat","lon","speed","heading"}; t is the same clock as the video.
    func append(_ line: String) {
        queue.async { self.gps.write(Data((line + "\n").utf8)) }
    }

    func finish() {
        queue.async { try? self.gps.close() }
        guard started, writer.status == .writing else { return }
        input.markAsFinished()
        writer.finishWriting {}
    }
}
