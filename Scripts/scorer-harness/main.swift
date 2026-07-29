// ShotScorer verification harness — runs the pure engine on macOS against
// the real IMG_7145 fixture. Mirrors the planned XCTest assertions.
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if cond { print("  ✓ \(name)") } else { failures += 1; print("  ✗ FAIL: \(name)") }
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try Data(contentsOf: url)
let result = try AnalysisCoders.makeDecoder().decode(AnalysisResult.self, from: data)
print("Fixture: \(result.frames.count) frames, \(result.strokes.count) strokes, arm=\(result.hittingArm.rawValue)")

// 1. Every detected stroke yields a ShotScore.
let shots = ShotScorer.score(result: result)
check(shots.count == result.strokes.count, "one ShotScore per stroke (\(shots.count))")

// 2. Every graded shot is in 0...100 with a sane component set.
for s in shots {
    if s.isGraded {
        check((0...100).contains(s.overall), "shot \(s.strokeId) overall \(String(format: "%.1f", s.overall)) in 0...100")
    }
    check(s.components.count == 6, "shot \(s.strokeId) has 6 components")
    check((0...1).contains(s.trackingCoverage), "shot \(s.strokeId) coverage \(String(format: "%.2f", s.trackingCoverage)) in 0...1")
    for c in s.components where c.score.isFinite {
        check((0...100).contains(c.score), "shot \(s.strokeId) \(c.kind.rawValue) in 0...100")
    }
}
let gradedCount = shots.filter(\.isGraded).count
print("Graded: \(gradedCount)/\(shots.count)")
check(gradedCount > 0, "fixture yields at least one graded shot")

// 3. Weight renormalization under NaN injection: stance stripped from every stroke.
var stanceless = result
stanceless.strokes = result.strokes.map { var s = $0; s.stanceMed = .nan; return s }
let shots2 = ShotScorer.score(result: stanceless)
for s in shots2 where s.isGraded {
    let stance = s.components.first { $0.kind == .stanceWidth }!
    check(!stance.score.isFinite, "shot \(s.strokeId): stance dropped")
    check((0...100).contains(s.overall), "shot \(s.strokeId): still graded after drop (\(String(format: "%.1f", s.overall)))")
}
check(shots2.filter(\.isGraded).count == gradedCount, "same graded count after single-component drop")

// 4. Joint-stripped copy → everything ungraded (tracking gate).
var stripped = result
stripped.poses = result.poses.map { p in
    var q = p; q.points = Array(repeating: nil, count: p.points.count); return q
}
let shots3 = ShotScorer.score(result: stripped)
check(shots3.allSatisfy { !$0.isGraded }, "joint-stripped fixture is fully ungraded")
check(shots3.allSatisfy { $0.confidence == .low }, "joint-stripped confidence is low")

// 5. Single-stroke result drops the speed component without crashing.
var single = result
single.strokes = Array(result.strokes.prefix(1))
let shots4 = ShotScorer.score(result: single)
check(shots4.count == 1, "single-stroke result scores")
let speedComp = shots4[0].components.first { $0.kind == .swingSpeed }!
check(!speedComp.score.isFinite, "speed dropped when only 1 stroke (no session best)")

// 6. Session best shot's speed component ≈ 100.
if let fastest = shots.max(by: { a, b in
    let sa = a.components.first { $0.kind == .swingSpeed }!.rawValue
    let sb = b.components.first { $0.kind == .swingSpeed }!.rawValue
    return (sa.isFinite ? sa : -1) < (sb.isFinite ? sb : -1)
}) {
    let c = fastest.components.first { $0.kind == .swingSpeed }!
    check(c.score >= 99, "fastest stroke's speed component ≈100 (got \(String(format: "%.1f", c.score)))")
}

// 7. Session rollup sanity.
let session = ShotScorer.sessionScore(shots)
check(session.totalShots == shots.count, "session totalShots")
check(session.gradedShots == gradedCount, "session gradedShots")
if session.overall.isFinite {
    check((0...100).contains(session.overall), "session overall in range")
    check(session.best >= session.worst, "best >= worst")
}
if session.consistency.isFinite { check((0...100).contains(session.consistency), "consistency in range") }

// 8. Empty-poses safety + zero-stroke safety.
var noStrokes = result
noStrokes.strokes = []
check(ShotScorer.score(result: noStrokes).isEmpty, "zero strokes → zero scores")

// 9. Narrative doesn't crash and speaks.
let headline = Narrative.headline(session: session, shots: shots)
check(!headline.isEmpty, "headline: \"\(headline)\"")
if let focus = Narrative.focusNext(shots: shots) {
    check(!focus.sentence.isEmpty, "focusNext: \"\(focus.sentence)\" [target \(focus.targetText), you \(focus.youText)]")
} else {
    check(gradedCount == 0, "focusNext nil only when nothing graded")
}
let findings = Narrative.findingCounts(shots: shots)
for f in findings { print("  finding: \(f.text) — \(f.affectedShots)/\(f.totalGradedShots)") }

// 10. Honesty: no px/s or mph in any narrative output.
let allText = ([headline] + findings.map(\.text) + (Narrative.focusNext(shots: shots).map { [$0.sentence, $0.targetText, $0.youText] } ?? [])).joined(separator: " ")
check(!allText.contains("px/s") && !allText.lowercased().contains("mph"), "no px/s or mph in narrative output")

// Detail dump for eyeballing.
print("\nPer-shot detail:")
for s in shots {
    let comps = s.components.map { c in
        "\(c.kind.rawValue)=\(c.score.isFinite ? String(Int(c.score.rounded())) : "—")"
    }.joined(separator: " ")
    print("  shot \(s.strokeId): overall=\(s.overall.isFinite ? String(Int(s.overall.rounded())) : "—") cov=\(String(format: "%.2f", s.trackingCoverage)) [\(comps)]")
}
print("Session: overall=\(session.overall.isFinite ? String(Int(session.overall.rounded())) : "—") consistency=\(session.consistency.isFinite ? String(Int(session.consistency.rounded())) : "—") provisional=\(session.isProvisional)")

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
