import Links
import SwiftUI
import UIKit

/// Rear-phone role, mounted on the bike: the camera's view edge to edge, and two quiet
/// circles in the bottom corners, whether the handlebar phone is connected and Screen off.
/// Recording, demo mode and pairing live in the Settings app. The pipeline runs while
/// this is on screen.
struct RearView: View {
    @StateObject private var pipeline = RearPipeline()
    @State private var savedBrightness: CGFloat = 1
    /// "Screen off" that keeps everything running: iOS stops the camera when the display
    /// truly sleeps, but an OLED pixel drawing black is off, so this looks and costs like
    /// a screen that is off. Any tap brings it back.
    @State private var blackout = false
    @State private var blackoutHint = false
    @State private var blackoutAt = Date.distantPast

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RearPreview(session: nil, image: pipeline.previewImage, tracks: pipeline.overlay)
                .aspectRatio(aspect, contentMode: .fit)
            if pipeline.previewImage == nil {
                Text(pipeline.error ?? "Starting the camera\u{2026}")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(32)
            }
        }
        .overlay(alignment: .topLeading) { if pipeline.logging { recording } }
        .overlay(alignment: .bottom) {
            HStack {
                frontIndicator
                Spacer()
                Button(action: screenOff) { circle("moon.fill") }
                    .accessibilityLabel("Screen off")
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .overlay {
            if blackout {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Text("Tap anywhere to turn the screen back on")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .opacity(blackoutHint ? 1 : 0)
                }
                .allowsHitTesting(false)
            }
        }
        .statusBarHidden(blackout)
        .persistentSystemOverlays(blackout ? .hidden : .automatic)
        .simultaneousGesture(TapGesture().onEnded {
            // The tap on the button itself also lands here; it must not undo it.
            guard blackout, Date().timeIntervalSince(blackoutAt) > 0.5 else { return }
            blackout = false
            screen?.brightness = savedBrightness
        })
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            OrientationLock.set(.allButUpsideDown)
            savedBrightness = screen?.brightness ?? 1
            pipeline.start()
        }
        .onDisappear {
            pipeline.stop()
            OrientationLock.set(.portrait)
            UIApplication.shared.isIdleTimerDisabled = false
            screen?.brightness = savedBrightness
        }
    }

    /// Connected or not, nothing in between: "connecting" reads as not yet.
    private var frontIndicator: some View {
        let connected = pipeline.peerState == .connected
        return circle(connected ? "iphone" : "iphone.slash", dimmed: !connected)
            .overlay(alignment: .topTrailing) {
                if connected {
                    Circle().fill(Theme.green).frame(width: 10, height: 10).offset(x: -4, y: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(connected ? "Handlebar phone connected" : "Handlebar phone not connected")
    }

    private func circle(_ symbol: String, dimmed: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.white.opacity(dimmed ? 0.5 : 0.9))
            .frame(width: 52, height: 52)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }

    private var recording: some View {
        Circle().fill(Theme.red).frame(width: 10, height: 10)
            .padding(20)
            .accessibilityLabel("Recording video")
    }

    private func screenOff() {
        blackout = true
        blackoutAt = Date()
        blackoutHint = true
        screen?.brightness = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(.easeOut(duration: 0.6)) { blackoutHint = false } }
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
    }

    /// The frame's own shape, so the preview is as large as the screen allows.
    private var aspect: CGFloat {
        guard let img = pipeline.previewImage, img.height > 0 else { return 4 / 3 }
        return CGFloat(img.width) / CGFloat(img.height)
    }
}
