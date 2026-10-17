import Foundation
import Protocol
import ThreatEngine

/// ThreatEngine + DangerEngine fused (Fusion.swift). Danger never alerts alone; it can
/// only confirm, sharpen or rescue what the metric engine already sees.
func runFusionChecks(_ check: (Bool, String) -> Void) {
    // z 20 m closing at 1/TTC 0.2: gap -0.8 is a threat (2), gap -1.2 is caution (1).
    func track(_ gap: Double) -> TrackState { TrackState(id: 1, cls: .car, z: 20, gap: gap, invTTC: 0.2) }
    func frames(_ n: Int, corroborated: Set<Int>) -> Int? {
        let e = ThreatEngine()
        var last: Decision?
        for i in 0..<n {
            last = e.update(tracks: [track(-0.8)], bikeSpeed: 5, demoMode: false,
                            now: Double(i) * 0.1, corroborated: corroborated).first
        }
        return last?.level
    }
    let urgent = DangerVote(level: .urgent, side: .left)

    // Debounce: 4 frames alone, 2 when Danger agrees.
    check(frames(3, corroborated: []) == 1 && frames(4, corroborated: []) == 2,
          "fusion: threat alone confirms after 4 frames")
    check(frames(1, corroborated: [1]) == 1 && frames(2, corroborated: [1]) == 2,
          "fusion: Danger agreeing shortens the debounce to 2 frames")
    check(Fusion.corroborated([1: DangerVote(level: .warning, side: .left),
                               2: DangerVote(level: .gentle, side: .left)]) == [1],
          "fusion: warning or worse corroborates, gentle does not")

    // Agreement escalates.
    let threat2 = Decision(id: 1, level: 2, grip: "L", gapPred: 0.8)
    check(Fusion.fuse([threat2], votes: [1: urgent], states: [track(-0.8)]) == [Decision(id: 1, level: 3, grip: "L", gapPred: 0.8)],
          "fusion: threat 2 + Danger urgent -> 3")
    check(Fusion.fuse([threat2], votes: [:], states: [track(-0.8)]) == [threat2],
          "fusion: threat alone still alerts")
    check(Fusion.fuse([threat2], votes: [1: DangerVote(level: .warning, side: .left)], states: [track(-0.8)]) == [threat2],
          "fusion: Danger warning does not escalate")

    // Danger alone stays silent.
    let quiet = Decision(id: 1, level: 0, grip: "-", gapPred: 3)
    check(Fusion.fuse([quiet], votes: [1: urgent], states: [track(-3)]) == [quiet],
          "fusion: Danger urgent with threat 0 stays silent")
    check(Fusion.fuse([], votes: [9: urgent], states: []).isEmpty,
          "fusion: Danger urgent on a track the threat engine skipped stays silent")

    // Rescue: metric range unsure (caution band), Danger urgent -> 2, grip from the gap.
    let caution = Decision(id: 1, level: 1, grip: "-", gapPred: 1.2)
    check(Fusion.fuse([caution], votes: [1: urgent], states: [track(-1.2)]).first?.level == 2
          && Fusion.fuse([caution], votes: [1: urgent], states: [track(-1.2)]).first?.grip == "L",
          "fusion: threat 1 + Danger urgent -> 2 on the left grip")
    check(Fusion.fuse([caution], votes: [1: urgent], states: [track(1.2)]).first?.grip == "R",
          "fusion: rescued track on the right gets the right grip")
    check(Fusion.fuse([caution], votes: [1: DangerVote(level: .urgent, side: .right)], states: [track(0.1)]).first?.grip == "R"
          && Fusion.fuse([caution], votes: [1: DangerVote(level: .urgent, side: .both)], states: [track(0.1)]).first?.grip == "L",
          "fusion: dead-centre gap falls back to Danger's side, behind -> left")
}
