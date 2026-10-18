import CoreLocation
import MapKit

/// Cycling directions via MKDirections, advanced along the polyline by CoreLocation.
@MainActor
final class NavRouter: NSObject, CLLocationManagerDelegate {
    var onUpdate: (NavState?) -> Void = { _ in }
    /// Where the rider is and which way they face, for the heading-up route.
    var onPose: (CLLocation, Double?) -> Void = { _, _ in }
    /// A new route after the rider left the old one, for the map to redraw.
    var onReroute: (RoutePlan) -> Void = { _ in }
    private var destination: MKMapItem?
    private var offRouteFixes = 0
    private var lastReroute = Date.distantPast
    /// Further than this from the route, for `offRouteNeeded` fixes in a row, means the
    /// rider took another way: more than GPS error on a sidewalk beside the road.
    static let offRouteMetres = 35.0
    static let offRouteNeeded = 4
    private var compass: Double?

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

    /// Every cycling route MapKit will offer, for the rider to choose between before
    /// setting off. Nothing starts here: asking is separate from going.
    func plans(to destination: MKMapItem) async throws -> [RoutePlan] {
        self.destination = destination
        let name = destination.name ?? "Destination"
        // Apple has no cycling directions for some places; walking routes follow
        // sidewalks and paths a bike can use, which beats no route at all.
        var lastError: Error?
        for mode in [MKDirectionsTransportType.cycling, .walking] {
            let req = MKDirections.Request()
            req.source = .forCurrentLocation()
            req.destination = destination
            req.transportType = mode
            req.requestsAlternateRoutes = true
            do {
                let routes = try await MKDirections(request: req).calculate().routes
                if !routes.isEmpty {
                    return routes.enumerated().map { RoutePlan(id: $0.offset, route: $0.element, destination: name) }
                }
            } catch { lastError = error }
        }
        throw lastError ?? MKError(.directionsNotFound)
    }

    /// Commit to one of them and begin following it.
    func start(_ plan: RoutePlan) {
        steps = plan.steps
        load(points: plan.coordinates.map { MKMapPoint($0) }, stepDistances: steps.map(\.distance))
        location.startUpdatingLocation()
        location.startUpdatingHeading()
        if let loc = location.location { update(with: loc) } else { onUpdate(state(at: 0)) }
    }

    /// GPS course while moving; it is undefined at a standstill, so below about walking
    /// pace the compass takes over.
    private func heading(for loc: CLLocation) -> Double? {
        loc.speed > 1.5 && loc.course >= 0 ? loc.course : compass
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
        location.stopUpdatingHeading()
        steps = []
        onUpdate(nil)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.update(with: loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let degrees = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        Task { @MainActor in
            self.compass = degrees
            if let loc = self.location.location { self.onPose(loc, self.heading(for: loc)) }
        }
    }

    private func update(with loc: CLLocation) {
        onPose(loc, heading(for: loc))
        guard !steps.isEmpty else { return }
        let p = MKMapPoint(loc.coordinate)
        var nav = state(at: progress(of: p))
        nav.offRoute = offRoute(p)
        nav.accuracy = loc.horizontalAccuracy
        onUpdate(nav)
        offRouteFixes = offRoute(p) > Self.offRouteMetres && loc.horizontalAccuracy < 25 ? offRouteFixes + 1 : 0
        if offRouteFixes >= Self.offRouteNeeded, Date().timeIntervalSince(lastReroute) > 15, let destination {
            lastReroute = Date()
            offRouteFixes = 0
            Task {
                guard let plan = try? await plans(to: destination).first else { return }
                start(plan)
                onReroute(plan)
            }
        }
    }

    /// Metres from the rider to the nearest point of the route.
    func offRoute(_ p: MKMapPoint) -> Double {
        var best = Double.infinity
        for i in 1..<max(points.count, 1) {
            let a = points[i - 1], b = points[i]
            let abx = b.x - a.x, aby = b.y - a.y, len2 = abx * abx + aby * aby
            let t = len2 > 0 ? min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / len2, 0), 1) : 0
            best = min(best, p.distance(to: MKMapPoint(x: a.x + abx * t, y: a.y + aby * t)))
        }
        return best
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
