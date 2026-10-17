import Links
import Perception
import Protocol
import SwiftUI
import UIKit

/// Rear-phone role: preview, numbers, toggles. The pipeline runs while this view is on screen.
struct RearView: View {
    @StateObject private var pipeline = RearPipeline()
    @State private var bench = false
    @State private var showPicker = false
    @State private var savedBrightness: CGFloat = 1
    /// "threat" | "danger"; `-engine danger` at launch overrides the stored value while present.
    @AppStorage("engine") private var engineName = Engine.threat.rawValue

    var body: some View {
        VStack(spacing: 12) {
            StatusStripView(fps: pipeline.fps, temp: pipeline.thermal.rawValue, speed: pipeline.speed, link: link)
            RearPreview(session: pipeline.captureSession, image: pipeline.previewImage, tracks: pipeline.overlay)
                .frame(height: 200)
                .background(Theme.ground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            if bench {
                Text(String(format: "%.1f ms", pipeline.benchMs))
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.text)
                Text("10 s rolling average per inference")
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textDim)
            }
            stats
            toggles
            if let e = pipeline.error {
                Text(e).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.red).padding(.horizontal)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            savedBrightness = screen?.brightness ?? 1
            screen?.brightness = 0.2
            pipeline.engine = Engine(rawValue: engineName) ?? .threat
            pipeline.start()
        }
        .onChange(of: engineName) { _, new in pipeline.engine = Engine(rawValue: new) ?? .threat }
        .onDisappear {
            pipeline.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            screen?.brightness = savedBrightness
        }
        .sheet(isPresented: $showPicker) { ReplayPicker { pipeline.setReplay($0) } }
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
    }

    private var link: LinkState {
        switch pipeline.peerState {
        case .connected: .connected
        case .connecting: .searching
        case .browsing: .lost
        }
    }

    private var stats: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
            GridRow { stat("inference", String(format: "%.1f ms", pipeline.inferenceMs)); stat("tracks", "\(pipeline.trackCount)") }
            GridRow { stat("BLE", "\(pipeline.haptics.state)"); stat("peer", "\(pipeline.peerState)") }
            GridRow {
                stat("heading", pipeline.heading < 0 ? "–" : String(format: "%.0f°", pipeline.heading))
                stat("source", pipeline.replayURL?.lastPathComponent ?? "camera")
            }
            GridRow { stat("events", "\(pipeline.eventCount)") }
        }
        .font(.system(size: 14, design: .rounded).monospacedDigit())
        .padding(.horizontal, 16)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(Theme.textDim)
            Text(value).foregroundStyle(Theme.text).lineLimit(1)
        }
    }

    private var toggles: some View {
        VStack(spacing: 2) {
            Toggle("Demo mode (bikes and people are threats)", isOn: $pipeline.demoMode)
            Toggle("Bench (10 s average)", isOn: $bench)
            Toggle("Log ride (video + GPS to Documents)", isOn: $pipeline.logging)
            Picker("Engine", selection: $engineName) {
                Text("Threat (metric gap)").tag(Engine.threat.rawValue)
                Text("Danger (frame TTC)").tag(Engine.danger.rawValue)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Replay file…") { showPicker = true }
                if pipeline.replayURL != nil { Button("Camera") { pipeline.setReplay(nil) } }
                Spacer()
                ShareLink("Share events", item: EventLogger.url)
            }
            .padding(.top, 4)
        }
        .font(.system(size: 14, design: .rounded))
        .foregroundStyle(Theme.text)
        .tint(Theme.amber)
        .padding(.horizontal, 16)
    }
}
