import CoreLocation
import Foundation
import Protocol

/// `-previewRide YES`: a pretend ride around the Pan Am Sports Centre, so the LIVE
/// front view can be watched in the simulator without anyone on a bike.
///
/// Laps a real 1.45 km loop of OpenStreetMap streets (Military Trail, Ellesmere Rd,
/// Morningside Ave) at 4 m/s with 1 Hz, 2–3 m-jittered GPS fixes, through the same
/// `FrontModel.pose` real fixes take. Tracks come from the scripted feed, but wrapped,
/// so `FrontModel.scripted` stays false and the live renderer draws them.
final class PreviewRide: TrackFeed {
    /// Closed loop, clockwise, starting where Pan Am Drive meets Military Trail.
    /// From OSM ways 227679317…227679318, Douglas–Peucker at 2 m.
    static let loop: [CLLocationCoordinate2D] = [
        .init(latitude: 43.787814, longitude: -79.190621),
        .init(latitude: 43.786577, longitude: -79.188271),
        .init(latitude: 43.785740, longitude: -79.191643),
        .init(latitude: 43.785346, longitude: -79.193357),
        .init(latitude: 43.785793, longitude: -79.193518),
        .init(latitude: 43.786206, longitude: -79.193593),
        .init(latitude: 43.787402, longitude: -79.193636),
        .init(latitude: 43.788094, longitude: -79.193852),
        .init(latitude: 43.789271, longitude: -79.194323),
        .init(latitude: 43.788829, longitude: -79.192991),
        .init(latitude: 43.788385, longitude: -79.191811),
        .init(latitude: 43.788215, longitude: -79.191394),
        .init(latitude: 43.787814, longitude: -79.190621),
    ]

    /// MKRoute-shaped: each step is announced at its start and lasts `distance` metres.
    static let steps: [NavStep] = [
        NavStep(instruction: "Head southeast on Military Trail", symbol: "arrow.up", distance: 234, street: "Military Trail"),
        NavStep(instruction: "Turn right onto Ellesmere Road", symbol: "arrow.turn.up.right", distance: 431, street: "Ellesmere Road"),
        NavStep(instruction: "Turn right onto Morningside Avenue", symbol: "arrow.turn.up.right", distance: 446, street: "Morningside Avenue"),
        NavStep(instruction: "Turn right onto Military Trail", symbol: "arrow.turn.up.right", distance: 340, street: "Military Trail"),
        NavStep(instruction: "Arrive", symbol: "flag.checkered", distance: 0, street: "Pan Am Drive"),
    ]

    static let speed = 4.0

    var frames: AsyncStream<FrameMessage> { cars.frames }
    /// Called on the main actor once a second with the fix, its course, the route ahead
    /// and the nav state, in the order a real ride delivers them.
    var onFix: (CLLocation, Double, [CLLocationCoordinate2D], NavState) -> Void = { _, _, _, _ in }

    private let cars = SyntheticFeed(freeze: nil, demo: true)
    private var task: Task<Void, Never>?
    private let cumulative: [Double]

    init() {
        var acc = [0.0]
        for i in 1..<Self.loop.count { acc.append(acc[i - 1] + Self.metres(Self.loop[i - 1], Self.loop[i])) }
        cumulative = acc
    }

    var length: Double { cumulative.last ?? 0 }

    func start() {
        cars.start()
        let origin = Date()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                fix(along: Date().timeIntervalSince(origin) * Self.speed)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() { cars.stop(); task?.cancel() }

    @MainActor private func fix(along s: Double) {
        let (coord, course, i) = point(at: s)
        // GPS noise: a few metres of position, a few degrees of course.
        let jittered = LiveRoute.offset(coord, x: .random(in: -2.5...2.5), z: .random(in: -2.5...2.5), heading: 0)
        let c = (course + .random(in: -3...3) + 360).truncatingRemainder(dividingBy: 360)
        let loc = CLLocation(coordinate: jittered, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                             course: c, courseAccuracy: 5, speed: Self.speed, speedAccuracy: 0.5,
                             timestamp: Date())
        let ahead = [coord] + Self.loop[(i + 1)...] + Self.loop[1..<(i + 1)]
        onFix(loc, c, Array(ahead), nav(at: s.truncatingRemainder(dividingBy: length)))
    }

    /// Position, course and segment index `s` metres round the loop.
    func point(at s: Double) -> (CLLocationCoordinate2D, Double, Int) {
        let d = s.truncatingRemainder(dividingBy: length)
        let i = max(cumulative.lastIndex { $0 <= d } ?? 0, 0)
        let a = Self.loop[i], b = Self.loop[min(i + 1, Self.loop.count - 1)]
        let f = (d - cumulative[i]) / max(cumulative[min(i + 1, cumulative.count - 1)] - cumulative[i], 0.001)
        let coord = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                           longitude: a.longitude + (b.longitude - a.longitude) * f)
        return (coord, Self.bearing(a, b), i)
    }

    /// Same rule as NavRouter.state: the current step is the first whose end is ahead.
    func nav(at along: Double) -> NavState {
        var acc = 0.0
        let ends = Self.steps.map { acc += $0.distance; return acc }
        let i = ends.firstIndex { $0 > along } ?? Self.steps.count - 1
        return NavState(steps: Self.steps, currentIndex: i,
                        distanceToManoeuvre: max(ends[i] - along, 0),
                        remaining: max(length - along, 0))
    }

    static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
        let dy = b.latitude - a.latitude
        return (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
