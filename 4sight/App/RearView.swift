import Links
import Perception
import Protocol
import SwiftUI
import UIKit

/// Rear-phone role, seen while mounting the bike: is everything awake (front phone,
/// grips, GPS), is the camera seeing the road, and the two choices a rider makes.
/// Engineering numbers sit under Diagnostics. The pipeline runs while this is on screen.
struct RearView: View {
    @StateObject private var pipeline = RearPipeline()
    @State private var bench = false
    @State private var showPicker = false
    @State private var diagnostics = false
    @State private var showDiagnostics = false
    @State private var savedBrightness: CGFloat = 1
    /// Dimming is explained before it happens, never sprung on the rider: the card says
    /// what it does, and a tap on the dimmed screen brightens it for a while.
    @AppStorage("rearDim") private var dimWhenMounted = true
    // `-skipMountCard YES` for simulator screenshots of the page behind it.
    @State private var mountCard = !UserDefaults.standard.bool(forKey: "skipMountCard")
    @State private var awakeUntil = Date.distantPast
    static let wakeSeconds = 15.0

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height { landscape(geo.size) } else { portrait }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .overlay { if mountCard { mountPrompt } }
        .simultaneousGesture(TapGesture().onEnded { wake() })
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            savedBrightness = screen?.brightness ?? 1
            pipeline.start()
        }
        .onChange(of: dimWhenMounted) { applyBrightness() }
        .onDisappear {
            pipeline.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            screen?.brightness = savedBrightness
        }
        .sheet(isPresented: $showPicker) { ReplayPicker { pipeline.setReplay($0) } }
    }

    // MARK: - Dimming

    private var mountPrompt: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text("Ready to mount?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Once it\u{2019}s on the rack, the screen dims to save battery and keep the phone cool. The camera keeps running.")
                    .font(.system(size: 16, design: .rounded)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tap the screen any time to brighten it for \(Int(Self.wakeSeconds)) seconds.")
                    .font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    dimWhenMounted = true; mountCard = false; awakeUntil = .distantPast; applyBrightness()
                } label: {
                    Text("Dim and start")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.amber, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 6)
                Button {
                    dimWhenMounted = false; mountCard = false; applyBrightness()
                } label: {
                    Text("Keep bright for now")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .foregroundStyle(Theme.text)
            .padding(22)
            .background(Theme.ground, in: RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: 460)
            .padding(.horizontal, 22)
        }
    }

    /// A tap on a dimmed screen brightens it, then it dims again on its own.
    private func wake() {
        guard dimWhenMounted, !mountCard else { return }
        awakeUntil = Date().addingTimeInterval(Self.wakeSeconds)
        applyBrightness()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeSeconds + 0.1) { applyBrightness() }
    }

    private func applyBrightness() {
        let dim = dimWhenMounted && !mountCard && Date() >= awakeUntil
        screen?.brightness = dim ? 0.2 : savedBrightness
    }

    private var portrait: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                chips
                preview.frame(maxWidth: .infinity, maxHeight: 520)
                statusLine
                controls
                diagnosticsSection
                errorText
            }
            .padding(16)
        }
    }

    /// Mounted sideways the whole page fits without scrolling: the camera on top, where
    /// it shows through the mount, status beside it, the few controls in one row below.
    private func landscape(_ size: CGSize) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                preview.frame(maxHeight: size.height - 76)
                VStack(alignment: .leading, spacing: 10) {
                    statusGrid
                    statusLine
                    errorText
                }
                .frame(width: min(260, size.width * 0.3))
            }
            HStack(spacing: 10) {
                Toggle(isOn: $dimWhenMounted) {
                    Text("Dim when mounted").font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .tint(Theme.amber)
                .padding(.horizontal, 14).frame(height: 50)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
                ShareLink(items: GPSLog.shareable) {
                    Label("Share ride data · \(pipeline.eventCount)", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14).frame(height: 50)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
                }
                Button { showDiagnostics = true } label: {
                    Label("Diagnostics", systemImage: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14).frame(height: 50)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .sheet(isPresented: $showDiagnostics) {
            ScrollView { diagnosticsSection.padding(20) }
                .background(Theme.bg)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
    }

    private var preview: some View {
        RearPreview(session: nil, image: pipeline.previewImage, tracks: pipeline.overlay)
            .aspectRatio(aspect, contentMode: .fit)
            .background(Theme.ground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topLeading) {
                if pipeline.logging {
                    Label("REC", systemImage: "circle.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.red, in: Capsule())
                        .padding(10)
                }
            }
    }

    @ViewBuilder private var errorText: some View {
        if let e = pipeline.error {
            Text(e).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.red)
        }
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
    }

    /// The frame's own shape, so the preview is as large as the screen allows.
    private var aspect: CGFloat {
        guard let img = pipeline.previewImage, img.height > 0 else { return 4 / 3 }
        return CGFloat(img.width) / CGFloat(img.height)
    }

    /// One plain sentence about the camera, instead of engineering numbers.
    private var statusLine: some View {
        let hot = pipeline.thermal == .serious || pipeline.thermal == .critical
        let (icon, text, colour): (String, String, Color) =
            pipeline.previewImage == nil ? ("hourglass", "Starting the camera…", Theme.textDim)
            : hot ? ("thermometer.sun.fill", "Phone is hot, so it checks less often to cool down. Shade it if you can.", Theme.amber)
            : ("eye.fill", "Watching the road behind you", Theme.green)
        return Label(text, systemImage: icon)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Status

    private var frontState: (Color, String) {
        switch pipeline.peerState {
        case .connected: (Theme.green, "Connected")
        case .connecting: (Theme.amber, "Connecting")
        case .browsing: (Theme.red, "Not found")
        }
    }
    private var gripsState: (Color, String) {
        pipeline.haptics.state == .connected ? (Theme.green, "Paired") : (Theme.red, "Searching")
    }
    private var gpsState: (Color, String) {
        switch pipeline.gpsAccuracy {
        case nil: (Theme.red, "No fix")
        case let a? where a <= 15: (Theme.green, String(format: "±%.0f m", a))
        case let a?: (Theme.amber, String(format: "±%.0f m", a))
        }
    }

    // One row of four, label over value, so it never wraps to a second line.
    private var chips: some View {
        HStack(spacing: 0) {
            cell("Front", frontState)
            divider
            cell("Grips", gripsState)
            divider
            cell("GPS", gpsState)
            divider
            cell("Battery", battery)
        }
        .padding(.vertical, 10)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The same four, two by two, for the narrow column beside the landscape preview.
    private var statusGrid: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 12) {
            GridRow { cell("Front", frontState); cell("Grips", gripsState) }
            GridRow { cell("GPS", gpsState); cell("Battery", battery) }
        }
        .padding(.vertical, 12)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 30) }

    private func cell(_ label: String, _ state: (Color, String)) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(state.0).frame(width: 7, height: 7)
                Text(label).foregroundStyle(Theme.textDim)
            }
            .font(.system(size: 12, design: .rounded))
            Text(state.1).font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// This phone runs the camera the whole ride, so its battery is the one that runs out.
    private var battery: (Color, String) {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return (Theme.textDim, "–") }
        let pct = Int((level * 100).rounded())
        return (pct < 20 ? Theme.amber : Theme.green, "\(pct)%")
    }


    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            option("Dim screen when mounted",
                   "Saves battery and heat. Tap the screen to brighten it for \(Int(Self.wakeSeconds)) s.",
                   isOn: $dimWhenMounted)
            Divider().overlay(Theme.line)
            ShareLink(items: GPSLog.shareable) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share ride data")
                    Spacer()
                    Text("\(pipeline.eventCount) near misses").foregroundStyle(Theme.textDim)
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 16))
        .tint(Theme.amber)
        .foregroundStyle(Theme.text)
    }

    private func option(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(detail).font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        DisclosureGroup(isExpanded: $diagnostics) {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    GridRow { stat("detection", "\(pipeline.fps) fps"); stat("thermal", pipeline.thermal.rawValue) }
                    GridRow { stat("inference", String(format: "%.1f ms", pipeline.inferenceMs)); stat("tracks", "\(pipeline.trackCount)") }
                    GridRow {
                        stat("lens", String(format: "f %.0f px %@", pipeline.focal, pipeline.focalFromLens ? "" : "(guess)"))
                        stat("heading", pipeline.heading < 0 ? "–" : String(format: "%.0f°", pipeline.heading))
                    }
                    GridRow { stat("events", "\(pipeline.eventCount)"); stat("source", pipeline.replayURL?.lastPathComponent ?? "camera") }
                }
                .font(.system(size: 14, design: .rounded).monospacedDigit())
                // Developer tools: off for real rides. People count for indoor demos;
                // video is for collecting test footage (GPS and near misses always log).
                Toggle("Demo: people and bikes trigger alerts", isOn: $pipeline.demoMode).tint(Theme.amber)
                Toggle("Record video to Documents", isOn: $pipeline.logging).tint(Theme.amber)
                Toggle("Bench (10 s average)", isOn: $bench).tint(Theme.amber)
                if bench {
                    Text(String(format: "%.1f ms", pipeline.benchMs))
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                }
                HStack {
                    Button("Replay file…") { showPicker = true }
                    if pipeline.replayURL != nil { Button("Back to camera") { pipeline.setReplay(nil) } }
                }
            }
            .padding(.top, 10)
        } label: {
            Text("Diagnostics").font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .font(.system(size: 14, design: .rounded))
        .foregroundStyle(Theme.text)
        .tint(Theme.textDim)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(Theme.textDim)
            Text(value).foregroundStyle(Theme.text).lineLimit(1)
        }
    }
}
