#if os(iOS)
import CoreML
import Vision
import Protocol

/// YOLO11n via Vision, filtered to the six classes the contract knows about.
public final class Detector: @unchecked Sendable {
    private let request: VNCoreMLRequest
    public var minConfidence = 0.1

    public init(modelName: String = "yolo11n", bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: modelName, withExtension: "mlmodelc")
            ?? bundle.url(forResource: modelName, withExtension: "mlpackage") else {
            throw DetectorError.modelNotFound(modelName)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: config))
        request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
    }

    public func detect(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up)
        -> [Detection] {
        let w = Double(CVPixelBufferGetWidth(pixelBuffer))
        let h = Double(CVPixelBufferGetHeight(pixelBuffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        guard (try? handler.perform([request])) != nil,
              let results = request.results as? [VNRecognizedObjectObservation] else { return [] }
        return results.compactMap { obs in
            guard let top = obs.labels.first, let cls = VehicleClass(rawValue: top.identifier),
                  Double(top.confidence) >= minConfidence else { return nil }
            // Vision boxes are normalised with a bottom-left origin; the pipeline wants pixels, top-left.
            let b = obs.boundingBox
            let box = Box(x: b.minX * w, y: (1 - b.maxY) * h, w: b.width * w, h: b.height * h)
            return Detection(box: box, cls: cls, confidence: Double(top.confidence))
        }
    }
}

public enum DetectorError: Error { case modelNotFound(String) }
#endif
