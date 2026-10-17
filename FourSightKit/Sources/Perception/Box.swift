import Foundation
import Protocol

/// Axis-aligned box in image pixels, origin top-left.
public struct Box: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    public var cx: Double { x + w / 2 }
    public var cy: Double { y + h / 2 }
    public var area: Double { w * h }
    public var bottom: Double { y + h }

    public func touchesEdge(imageW: Double, imageH: Double, margin: Double = 2) -> Bool {
        x <= margin || y <= margin || x + w >= imageW - margin || y + h >= imageH - margin
    }

    public func iou(_ o: Box) -> Double {
        let iw = max(0, min(x + w, o.x + o.w) - max(x, o.x))
        let ih = max(0, min(y + h, o.y + o.h) - max(y, o.y))
        let inter = iw * ih
        let union = area + o.area - inter
        return union > 0 ? inter / union : 0
    }
}

public struct Detection: Equatable, Sendable {
    public var box: Box
    public var cls: VehicleClass
    public var confidence: Double

    public init(box: Box, cls: VehicleClass, confidence: Double) {
        self.box = box; self.cls = cls; self.confidence = confidence
    }
}

public struct Track: Equatable, Sendable {
    public var id: Int
    public var cls: VehicleClass
    public var box: Box
    public var hits: Int
    public var misses: Int
    public var age: Int
}
