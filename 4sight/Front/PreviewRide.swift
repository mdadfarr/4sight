import CoreLocation
import Foundation
import Protocol

/// `-previewRide YES`: a pretend ride around the Pan Am Sports Centre, so the LIVE
/// front view can be watched in the simulator without anyone on a bike.
///
/// Laps a real 1.45 km loop of OpenStreetMap streets (Military Trail, Ellesmere Rd,
/// Morningside Ave) the way a rider would: in the lane the plan picks, 15 km/h on the
/// straights and slower through corners, with 1 Hz fixes whose error drifts slowly as
/// a real receiver's does, through the same `FrontModel.pose` real fixes take. Tracks come from the scripted feed, but wrapped,
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

    var frames: AsyncStream<FrameMessage> { cars.frames }
    /// Called on the main actor once a second with the fix, its course, the route ahead
    /// and the nav state, in the order a real ride delivers them.
    var onFix: (CLLocation, Double, [CLLocationCoordinate2D], NavState) -> Void = { _, _, _, _ in }

    /// The rear camera's tracks: the scripted cars, or a real clip run through the rear
    /// pipeline (`-replayRear`).
    private let cars: TrackFeed
    private var task: Task<Void, Never>?
    private let cumulative: [Double]

    init(tracks: TrackFeed = SyntheticFeed(freeze: nil, demo: true)) {
        cars = tracks
        var acc = [0.0]
        for i in 1..<Self.loop.count { acc.append(acc[i - 1] + Self.metres(Self.loop[i - 1], Self.loop[i])) }
        cumulative = acc
    }

    var length: Double { cumulative.last ?? 0 }

    /// What the rider actually rides: the lane plan's line around the loop (bike lane,
    /// right lane, sidewalk), not the road's centre line the route follows.
    private lazy var path: [CLLocationCoordinate2D] = {
        guard let map = StreetMap.loaded(at: Self.loop.first), let plan = LanePlan(route: Self.loop, map: map) else { return Self.loop }
        return plan.samples.map { map.coordinate(($0.e, $0.n)) }
    }()
    private lazy var pathCumulative: [Double] = {
        var acc = [0.0]
        for i in 1..<path.count { acc.append(acc[i - 1] + Self.metres(path[i - 1], path[i])) }
        return acc
    }()
    /// GPS error, east/north metres: drifts slowly like a real receiver's, not white noise.
    private var gpsError = (0.0, 0.0)
    private var ridden = 0.0

    func start() {
        cars.start()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                let v = speed(at: ridden)
                ridden += v
                fix(along: ridden, speed: v)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() { cars.stop(); task?.cancel() }

    /// 15 km/h on the straight, easing to about 9 km/h through a corner.
    private func speed(at s: Double) -> Double {
        let a = pathPoint(at: s - 10).course, b = pathPoint(at: s + 10).course
        let turn = min(abs(LiveRoute.shortest(b - a)) / 70, 1)
        return 4.2 - 1.7 * turn
    }

    @MainActor private func fix(along s: Double, speed v: Double) {
        let (coord, course) = pathPoint(at: s)
        // Ornstein–Uhlenbeck: pulled back toward zero, nudged a little each second;
        // settles around ±1.5 m and wanders over tens of seconds.
        gpsError.0 = gpsError.0 * 0.8 + Self.gauss() * 0.9
        gpsError.1 = gpsError.1 * 0.8 + Self.gauss() * 0.9
        let shown = LiveRoute.offset(coord, x: gpsError.0, z: -gpsError.1, heading: 0)
        let c = (course + Self.gauss() + 360).truncatingRemainder(dividingBy: 360)
        let loc = CLLocation(coordinate: shown, altitude: 0, horizontalAccuracy: 4, verticalAccuracy: 5,
                             course: c, courseAccuracy: 3, speed: v, speedAccuracy: 0.3, timestamp: Date())
        // The route and nav run on the centre-line loop; the lane path is a few metres
        // off it, so map progress across by fraction of the lap.
        let lap = pathCumulative.last ?? 1
        let along = s.truncatingRemainder(dividingBy: lap) / lap * length
        let i = point(at: along).2
        // The rest of the lap from this segment on, stopping 80 m short of closing the
        // loop: a route that comes back round would be drawn behind the rider.
        var ahead = Array(Self.loop[i...] + Self.loop[1..<(i + 1)])
        var spare = length - 80
        for k in 1..<ahead.count {
            let seg = Self.metres(ahead[k - 1], ahead[k])
            if seg >= spare {
                let f = spare / seg
                ahead[k] = CLLocationCoordinate2D(latitude: ahead[k - 1].latitude + (ahead[k].latitude - ahead[k - 1].latitude) * f,
                                                  longitude: ahead[k - 1].longitude + (ahead[k].longitude - ahead[k - 1].longitude) * f)
                ahead = Array(ahead[...k]); break
            }
            spare -= seg
        }
        onFix(loc, c, ahead, nav(at: along))
    }

    /// Position and direction of travel `s` metres round the ridden path.
    private func pathPoint(at s: Double) -> (CLLocationCoordinate2D, course: Double) {
        let lap = pathCumulative.last ?? 1
        let d = (s.truncatingRemainder(dividingBy: lap) + lap).truncatingRemainder(dividingBy: lap)
        let i = min(max(pathCumulative.lastIndex { $0 <= d } ?? 0, 0), path.count - 2)
        let a = path[i], b = path[i + 1]
        let f = (d - pathCumulative[i]) / max(pathCumulative[i + 1] - pathCumulative[i], 0.001)
        return (CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                       longitude: a.longitude + (b.longitude - a.longitude) * f),
                Self.bearing(path[max(i - 2, 0)], path[min(i + 3, path.count - 1)]))
    }

    private static func gauss() -> Double {
        sqrt(-2 * log(Double.random(in: 1e-9...1))) * cos(2 * .pi * Double.random(in: 0...1))
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
