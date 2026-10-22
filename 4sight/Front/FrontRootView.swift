import MapKit
import Protocol
import SwiftUI

/// The front phone, start to finish: pick somewhere at a standstill, choose how to get
/// there, ride with the follow view, and see what happened on arrival.
///
/// Everything before `riding` is done stopped, so those screens are ordinary iOS —
/// sheets, lists, taps. Only the riding phase is designed to be read at speed.
struct FrontRootView: View {
    @StateObject private var model = FrontModel()
    @StateObject private var flow = RideFlow()
    @State private var router = NavRouter()
    @State private var plans: [RoutePlan] = []
    @State private var chosen: RoutePlan?
    @State private var destination = ""
    @State private var routing = false
    @State private var rideStarted = Date()
    @State private var wheelWarned = false
    private let args = LaunchArgs()

    var body: some View {
        ZStack {
            switch flow.phase {
            case .home:
                PassiveHomeView(model: model, flow: flow, onPick: preview, onDemo: startDemo)
            case .preview:
                RoutePreviewView(model: model, plans: plans, destination: destination,
                                 chosen: $chosen, onStart: start, onCancel: { flow.phase = .home })
            case .riding:
                ride
            case let .arrived(summary):
                RideSummaryView(summary: summary, onDone: { flow.phase = .home })
            }
            if routing { RoutePreviewSkeleton() }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: begin)
        .alert("Rear camera can\u{2019}t see enough", isPresented: wheelAlert) {
            Button("OK") {}
        } message: {
            Text("Your back wheel fills too much of the rear camera\u{2019}s view, so cars behind you "
                 + "could be missed. Mount the rear phone higher or tilt it up, then tap "
                 + "\u{201C}Forget wheel position\u{201D} on the rear phone.")
        }
    }

    /// Once per launch, and never mid-ride: a modal over the nav would hide the road.
    private var wheelAlert: Binding<Bool> {
        Binding(get: {
            if case .riding = flow.phase { return false }
            return !wheelWarned && model.frame?.wheelBlocksView == true
        }, set: { if !$0 { wheelWarned = true } })
    }

    private var ride: some View {
        ZStack {
            SurroundView(model: model)
            NavHUDView(model: model, onExit: exitRide)
            AlertOverlay(model: model)
            TurnWarningBanner(model: model)
            MergeBannerView(model: model)
        }
        .ignoresSafeArea()
        // Auto-lock would stop GPS and the nav mid-ride.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Flow

    private func begin() {
        model.freeze = args.freeze
        router.onUpdate = advance
        router.onPose = { model.pose($0, heading: $1) }
        router.onReroute = { model.route.coordinates = $0.coordinates }
        if args.mockRoute { model.nav = .mock }
        if args.previewRide { return startPreviewRide() }
        // The scripted ride and the frozen screenshots start mid-ride; a real launch
        // starts stopped, with nowhere to go yet.
        if args.synthetic || args.mockRoute {
            flow.phase = .riding
            model.beginRide()
        } else {
            router.requestAuthorization()
        }
        model.start(feed: args.synthetic
                    ? SyntheticFeed(freeze: args.freeze, demo: args.demo)
                    : PeerFeed())
    }

    /// The same ride `--synthetic --demo --mockroute` starts, reachable on an untethered
    /// phone. Relaunch the app to get back to the live link.
    private func startDemo() {
        model.nav = .mock
        model.beginRide()
        model.start(feed: SyntheticFeed(freeze: nil, demo: true))
        flow.phase = .riding
    }

    /// `-previewRide`: the live renderer on a pretend lap, for the simulator. Fixes go
    /// through `model.pose` exactly as NavRouter's do; nav is set directly so the lap
    /// never counts as an arrival.
    private func startPreviewRide() {
        let ride = PreviewRide(tracks: args.replayRear.map { RearReplayFeed(file: $0) as TrackFeed } ?? SyntheticFeed(freeze: nil, demo: true))
        ride.onFix = { loc, course, ahead, nav in
            model.pose(loc, heading: course)
            // Only when the segment changes, as a real route is set once, not every fix.
            if model.route.coordinates.first?.latitude != ahead.first?.latitude { model.route.coordinates = ahead }
            model.nav = nav
        }
        model.beginRide()
        model.start(feed: ride)
        flow.phase = .riding
    }

    /// Ends the ride and goes home. Leaving the scripted ride also puts the real link
    /// back, so the home screen's pair strip is not reporting a script as a rear phone.
    private func exitRide() {
        router.stop()
        model.nav = nil
        model.route = LiveRoute()
        if model.scripted { model.start(feed: PeerFeed()) }
        flow.phase = .home
    }

    private func preview(_ item: MKMapItem) {
        destination = item.name ?? "Destination"
        flow.remember(item)
        routing = true
        Task {
            defer { routing = false }
            guard let found = try? await router.plans(to: item), !found.isEmpty else { return }
            plans = found
            chosen = found.first
            flow.phase = .preview(found[0])
        }
    }

    private func start(_ plan: RoutePlan) {
        rideStarted = Date()
        model.beginRide()
        model.route = LiveRoute()                         // no trail left from the last ride
        model.route.coordinates = plan.coordinates
        router.start(plan)
        flow.phase = .riding
    }

    /// Route progress, and the one place the ride ends.
    private func advance(_ state: NavState?) {
        model.nav = state
        guard case .riding = flow.phase, let state else { return }
        guard state.remaining <= RideFlow.arrivalRadius else { return }
        flow.phase = .arrived(RideSummary(
            destination: destination,
            seconds: Date().timeIntervalSince(rideStarted),
            metres: chosen?.metres ?? 0,
            closePasses: model.closePasses,
            imminent: model.imminent))
        router.stop()
    }
}
