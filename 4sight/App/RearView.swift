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
    @State private var savedBrightness: CGFloat = 1
    /// Dimming is explained before it happens, never sprung on the rider: the card says
    /// what it does, and a tap on the dimmed screen brightens it for a while.
    @AppStorage("rearDim") private var dimWhenMounted = true
    @State private var mountCard = true
    @State private var awakeUntil = Date.distantPast
    static let wakeSeconds = 15.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                chips
                RearPreview(session: nil, image: pipeline.previewImage, tracks: pipeline.overlay)
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 520)
                    .background(Theme.ground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(summary)
                    .font(.system(size: 13, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textDim)
                controls
                diagnosticsSection
                if let e = pipeline.error {
                    Text(e).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.red)
                }
            }
            .padding(16)
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

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
    }

    /// The frame's own shape, so the preview is as large as the screen allows.
    private var aspect: CGFloat {
        guard let img = pipeline.previewImage, img.height > 0 else { return 4 / 3 }
        return CGFloat(img.width) / CGFloat(img.height)
    }

    private var summary: String {
        String(format: "%d fps · %.0f ms · %d tracking · %@", pipeline.fps, pipeline.inferenceMs,
               pipeline.trackCount, pipeline.thermal.rawValue)
    }

    // MARK: - Status

    private var chips: some View {
        let front: (Color, String) = switch pipeline.peerState {
        case .connected: (Theme.green, "Connected")
        case .connecting: (Theme.amber, "Connecting")
        case .browsing: (Theme.red, "Not found")
        }
        let grips: (Color, String) = pipeline.haptics.state == .connected
            ? (Theme.green, "Paired") : (Theme.red, "Searching")
        let gps: (Color, String) = switch pipeline.gpsAccuracy {
        case nil: (Theme.red, "No fix")
        case let a? where a <= 15: (Theme.green, String(format: "±%.0f m", a))
        case let a?: (Theme.amber, String(format: "±%.0f m", a))
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chipRow(front, grips, gps) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { chip("Front", front); chip("Grips", grips) }
                HStack(spacing: 8) { chip("GPS", gps); if pipeline.logging { chip("Video", (Theme.red, "Rec")) } }
            }
        }
    }

    @ViewBuilder
    private func chipRow(_ front: (Color, String), _ grips: (Color, String), _ gps: (Color, String)) -> some View {
        chip("Front", front)
        chip("Grips", grips)
        chip("GPS", gps)
        if pipeline.logging { chip("Video", (Theme.red, "Rec")) }
    }

    private func chip(_ label: String, _ state: (Color, String)) -> some View {
        HStack(spacing: 6) {
            Circle().fill(state.0).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Theme.textDim)
            Text(state.1).foregroundStyle(Theme.text).fontWeight(.semibold)
        }
        .font(.system(size: 13.5, design: .rounded))
        .padding(.horizontal, 11).frame(height: 32)
        .background(Theme.ground, in: Capsule())
        .fixedSize()
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            option("Count people and bikes",
                   "Pedestrians and cyclists can trigger alerts too. For demos; on the road only vehicles do.",
                   isOn: $pipeline.demoMode)
            Divider().overlay(Theme.line)
            option("Dim screen when mounted",
                   "Saves battery and heat. Tap the screen to brighten it for \(Int(Self.wakeSeconds)) s.",
                   isOn: $dimWhenMounted)
            Divider().overlay(Theme.line)
            option("Record video",
                   "GPS and near misses are always logged. Video files are large; record only test rides.",
                   isOn: $pipeline.logging)
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
                    GridRow { stat("inference", String(format: "%.1f ms", pipeline.inferenceMs)); stat("tracks", "\(pipeline.trackCount)") }
                    GridRow {
                        stat("lens", String(format: "f %.0f px %@", pipeline.focal, pipeline.focalFromLens ? "" : "(guess)"))
                        stat("heading", pipeline.heading < 0 ? "–" : String(format: "%.0f°", pipeline.heading))
                    }
                    GridRow { stat("events", "\(pipeline.eventCount)"); stat("source", pipeline.replayURL?.lastPathComponent ?? "camera") }
                }
                .font(.system(size: 14, design: .rounded).monospacedDigit())
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
