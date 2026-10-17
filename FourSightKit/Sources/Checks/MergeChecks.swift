import Foundation
import Protocol
import ThreatEngine

/// Merge-check button logic. Every uncertainty must answer blocked: a green light
/// here sends a rider into a traffic lane, so these cases are the safety net.
func runMergeChecks(_ check: (Bool, String) -> Void) {
    func t(_ id: Int, gap: Double, z: Double, invTTC: Double = 0,
           cls: VehicleClass = .car, frames: Int = 10) -> TrackState {
        TrackState(id: id, cls: cls, z: z, gap: gap, invTTC: invTTC, framesSeen: frames)
    }

    // Empty road.
    check(mergeCheck(side: .left, tracks: []).clear, "merge: nothing behind -> clear")

    // A car in the lane we want, close behind, not closing: still blocks.
    let alongside = mergeCheck(side: .left, tracks: [t(1, gap: -2.5, z: 4)])
    check(!alongside.clear && alongside.blockedBy == 1, "merge: car alongside in the left lane -> blocked")

    // Same car, same place, but we asked about the other lane.
    check(mergeCheck(side: .right, tracks: [t(1, gap: -2.5, z: 4)]).clear,
          "merge: left-lane car does not block a right merge")

    // Far back and closing fast enough to arrive inside the move.
    check(!mergeCheck(side: .left, tracks: [t(2, gap: -2.5, z: 40, invTTC: 0.3)]).clear,
          "merge: car 40 m back closing at 1/TTC 0.3 (3.3 s) -> blocked")

    // Far back and closing slowly: 1/TTC 0.1 is 10 s away, longer than the move.
    check(mergeCheck(side: .left, tracks: [t(3, gap: -2.5, z: 40, invTTC: 0.1)]).clear,
          "merge: car 40 m back 10 s away -> clear")

    // Falling behind.
    check(mergeCheck(side: .left, tracks: [t(4, gap: -2.5, z: 30, invTTC: -0.2)]).clear,
          "merge: car dropping back -> clear")

    // Straddling the line, directly behind the rider, counts as in the way.
    check(!mergeCheck(side: .left, tracks: [t(5, gap: -0.2, z: 5)]).clear,
          "merge: vehicle straddling the line behind -> blocked")

    // Far outside the target lane (two lanes over) is not our problem.
    check(mergeCheck(side: .left, tracks: [t(6, gap: -7.0, z: 5)]).clear,
          "merge: vehicle two lanes over -> clear")

    // A track seen once has no trustworthy velocity.
    let fresh = mergeCheck(side: .left, tracks: [t(7, gap: -2.5, z: 30, invTTC: -0.5, frames: 1)])
    check(!fresh.clear && fresh.reason.contains("unconfirmed"),
          "merge: single-frame track -> blocked, not trusted")

    // A stalled pipeline cannot answer at all, even with an empty track list.
    let stale = mergeCheck(side: .left, tracks: [], age: 2.0)
    check(!stale.clear && stale.reason == "no fresh view",
          "merge: stale frame -> blocked regardless of tracks")
    check(mergeCheck(side: .left, tracks: [], age: 0.5).clear,
          "merge: 0.5 s old frame still answers")

    // The nearest blocker is the one reported, so the front can mark it.
    let two = mergeCheck(side: .right, tracks: [t(8, gap: 2.0, z: 30, invTTC: 0.5),
                                               t(9, gap: 2.0, z: 3)])
    check(!two.clear && two.blockedBy == 8, "merge: reports a blocking track id")

    // Wire format for both answers and both sides.
    check(BLECommand.mergeClear(side: "L").ascii == "GL"
            && BLECommand.mergeBlocked(side: "R").ascii == "NR",
          "merge: GL and NR on the wire")
    check(BLEEvent.parse("ML") == .mergeRequest(side: "L")
            && BLEEvent.parse("MR") == .mergeRequest(side: "R")
            && BLEEvent.parse("junk") == nil,
          "merge: button notify parses, junk ignored")

    // The optional field must survive a round trip and stay absent when unset.
    let msg = FrameMessage(t: 1, fps: 10, temp: .nominal, speed: 5, heading: 90,
                           demo: false, tracks: [],
                           merge: MergeMessage(side: "L", clear: false, blockedBy: 7, t: 0.9))
    if let line = try? msg.encodeLine(), let back = try? FrameMessage.decode(line: line) {
        check(back.merge == msg.merge, "merge: FrameMessage round trip keeps the answer")
        check(String(data: line, encoding: .utf8)?.contains("\"blocked_by\":7") == true,
              "merge: blocked_by is snake_case on the wire")
    } else {
        check(false, "merge: FrameMessage with a merge answer did not round trip")
    }
    let plain = FrameMessage(t: 1, fps: 10, temp: .nominal, speed: 5, heading: 90,
                             demo: false, tracks: [])
    if let line = try? plain.encodeLine() {
        check(String(data: line, encoding: .utf8)?.contains("merge") == false,
              "merge: absent when no answer, old fronts unaffected")
    }
}
