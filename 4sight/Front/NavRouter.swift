import CoreLocation
import MapKit

/// Cycling directions via MKDirections, advanced along the polyline by CoreLocation.
@MainActor
final class NavRouter: NSObject, CLLocationManagerDelegate {
    var onUpdate: (NavState?) -> Void = { _ in }

    private let location = CLLocationManager()
    private var steps: [NavStep] = []
    private var stepEnds: [Double] = []        // cumulative metres at the end of each step
    private var points: [MKMapPoint] = []      // full route polyline
    private var cumulative: [Double] = []      // metres along `points`

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
    }

    var lastLocation: CLLocation? { location.location }

    func requestAuthorization() {
        location.requestWhenInUseAuthorization()
    }

    func route(to destination: MKMapItem) async throws {
        let req = MKDirections.Request()
        req.source = .forCurrentLocation()
        req.destination = destination
        req.transportType = .cycling
        guard let route = try await MKDirections(request: req).calculate().routes.first else { return }
        steps = route.steps.filter { $0.distance > 0 || $0 == route.steps.last }.map(NavStep.init)
        load(points: Array(UnsafeBufferPointer(start: route.polyline.points(), count: route.polyline.pointCount)),
             stepDistances: steps.map(\.distance))
        location.startUpdatingLocation()
        if let loc = location.location { update(with: loc) } else { onUpdate(state(at: 0)) }
    }

    /// Geometry only, so the projection can be checked without MKDirections.
    func load(points: [MKMapPoint], stepDistances: [Double]) {
        if steps.isEmpty { steps = stepDistances.map { NavStep(instruction: "", symbol: "arrow.up", distance: $0, street: "") } }
        var acc = 0.0
        stepEnds = stepDistances.map { acc += $0; return acc }
        self.points = points
        cumulative = [0]
        for i in 1..<points.count { cumulative.append(cumulative[i - 1] + points[i - 1].distance(to: points[i])) }
    }

    func stop() {
        location.stopUpdatingLocation()
        steps = []
        onUpdate(nil)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.update(with: loc) }
    }

    private func update(with loc: CLLocation) {
        guard !steps.isEmpty else { return }
        onUpdate(state(at: progress(of: MKMapPoint(loc.coordinate))))
    }

    /// Metres along the polyline of the rider's projection onto its nearest segment.
    func progress(of p: MKMapPoint) -> Double {
        var best = (dist: Double.infinity, along: 0.0)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let abx = b.x - a.x, aby = b.y - a.y
            let len2 = abx * abx + aby * aby
            let t = len2 > 0 ? min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / len2, 0), 1) : 0
            let q = MKMapPoint(x: a.x + abx * t, y: a.y + aby * t)
            let d = p.distance(to: q)
            if d < best.dist { best = (d, cumulative[i - 1] + a.distance(to: q)) }
        }
        return best.along
    }

    /// Current step = first whose end is still ahead of the rider.
    func state(at along: Double) -> NavState {
        // shortcut: step distances and polyline length can differ by a few metres, revisit if the arrow flips early.
        let i = stepEnds.firstIndex { $0 > along } ?? steps.count - 1
        return NavState(steps: steps, currentIndex: i,
                        distanceToManoeuvre: max(stepEnds[i] - along, 0),
                        remaining: max((stepEnds.last ?? 0) - along, 0))
    }
}

extension NavStep {
    init(_ step: MKRoute.Step) {
        let text = step.instructions
        let lower = text.lowercased()
        let symbol = lower.contains("u-turn") ? "arrow.uturn.left"
            : lower.contains("left") ? "arrow.turn.up.left"
            : lower.contains("right") ? "arrow.turn.up.right"
            : lower.contains("arrive") || lower.contains("destination") ? "flag.checkered"
            : "arrow.up"
        let street = text.range(of: " onto ").map { String(text[$0.upperBound...]) } ?? text
        self.init(instruction: text, symbol: symbol, distance: step.distance, street: street)
    }
}
