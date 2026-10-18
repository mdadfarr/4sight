import CoreLocation
import Foundation
import Protocol

/// Logs one ride for Toronto's public close-pass map: GPS at most 1 Hz and each
/// vehicle's worst moment. Nothing is kept unless the rider left sharing on (role screen).
/// The trimming and one-per-vehicle rule live in `RideLog` (FourSightKit), checked there.
final class RideRecorder {
    private var log: RideLog?
    private var demo = false
    private var fix: CLLocation?

    func begin() {
        let share = UserDefaults.standard.object(forKey: "shareNearMisses") as? Bool ?? true
        log = share ? RideLog() : nil
        #if targetEnvironment(simulator)
        demo = true
        #else
        demo = false
        #endif
    }

    func pose(_ loc: CLLocation) {
        fix = loc
        log?.add(t: loc.timestamp.timeIntervalSince1970, lat: loc.coordinate.latitude,
                 lon: loc.coordinate.longitude, speed: max(loc.speed, 0))
    }

    /// `scripted`: the synthetic ride or a preview lap, never real traffic.
    func frame(_ f: FrameMessage, scripted: Bool) {
        guard log != nil else { return }
        demo = demo || f.demo || scripted
        guard let fix else { return }                    // an event needs a place
        let t = Date().timeIntervalSince1970
        for tr in f.tracks where tr.level >= 2 {
            log?.add(track: tr.id, RideUpload.Event(
                t: t, lat: fix.coordinate.latitude, lon: fix.coordinate.longitude, cls: tr.cls,
                level: tr.level, side: tr.grip, gapM: tr.gapPred,
                ttcS: tr.invTTC > 0 ? 1 / tr.invTTC : nil,
                speed: fix.speed >= 0 ? fix.speed : f.speed))
        }
    }

    /// Ends the ride and hands it to the outbox. Safe to call twice: the second is a no-op.
    func finish() {
        defer { log = nil; fix = nil }
        let ups = log?.uploads(install: CityUploader.install, app: CityUploader.app, demo: demo) ?? []
        if !ups.isEmpty { CityUploader.shared.submit(ups) }
    }
}
