//
//  ShotScorer.swift
//  Tennis AI Coach
//
//  Per-shot 0–100 form scoring over the existing analysis data. Pure compute,
//  lazily invoked at display time — nothing here is persisted.
//
//  Design rules (see plan):
//  - Speed is scored ONLY relative to this session's fastest swing of the
//    same kind (a backhand against the session's forehands would always look
//    slow; a serve against them, always fast). Never across sessions.
//  - Angle bands reuse FormBands — the same thresholds CoachingEngine speaks to.
//  - What a stroke is scored on depends on what it was: a serve on its leg
//    load, reach and arm extension, a groundstroke on its base, balance and
//    finish. Sessions from before strokes had a kind keep exactly the six
//    components and weights they were scored with.
//  - Missing data (NaN) drops a component; weights renormalize over survivors.
//  - Tracking gate: joint coverage < 0.5 or < 3 surviving components → the
//    shot is UNGRADED (overall = NaN) rather than a made-up number.
//

import Foundation

nonisolated enum ShotScorer {

    // Nominal component weights (renormalized over surviving components).
    // `W` is the original set, still used for strokes saved without a kind.
    private enum W {
        static let speed = 0.28
        static let knee = 0.18
        static let torso = 0.18
        static let elbow = 0.12
        static let stance = 0.10
        static let prep = 0.14
    }

    private enum Groundstroke {
        static let speed = 0.24
        static let knee = 0.16
        static let torso = 0.14
        static let elbow = 0.10
        static let stance = 0.10
        static let prep = 0.12
        static let finish = 0.14
    }

    private enum Serve {
        static let speed = 0.24
        static let knee = 0.18
        static let reach = 0.22
        static let elbow = 0.18
        static let prep = 0.18
    }

    private static let minSurvivingComponents = 3
    private static let coverageGate = 0.5

    // MARK: - Public API

    static func score(result: AnalysisResult) -> [ShotScore] {
        let frames = result.frames
        let poses = result.poses
        guard !result.strokes.isEmpty, !frames.isEmpty else { return [] }

        // Session-best speed reference: robust p95 over detected strokes of
        // the same kind, or over all of them when a kind has only one. With
        // < 2 strokes there is no meaningful "session best" — the lone stroke
        // would always score 100 — so the component is dropped.
        func reference(_ strokes: [Stroke]) -> Double {
            strokes.count >= 2 ? NanStats.nanPercentile(strokes.map(\.peakSpeed), 95) : .nan
        }
        let overallRef = reference(result.strokes)
        func speedRef(for stroke: Stroke) -> Double {
            guard let kind = stroke.kind else { return overallRef }
            let sameKind = reference(result.strokes.filter { $0.kind == kind })
            if sameKind.isFinite { return sameKind }
            // A lone forehand can still be measured against the backhands; a
            // lone serve against nothing — serves and groundstrokes aren't the
            // same motion, and Vision loses the wrist overhead more often.
            guard kind != .serve else { return .nan }
            return reference(result.strokes.filter { $0.kind != nil && $0.kind != .serve })
        }

        // Same window the detector used: ±0.25 s in processed-frame steps.
        let win = max(1, NanStats.pythonRound(
            0.25 * result.meta.fps / Double(max(1, result.meta.sampleStride))))

        // Stroke.peakFrame is an ORIGINAL video frame index; map it back to
        // its position in the processed-frames array.
        var indexByFrame: [Int: Int] = [:]
        for (i, f) in frames.enumerated() { indexByFrame[f.frameIndex] = i }

        return result.strokes.map { stroke in
            scoreStroke(stroke,
                        frames: frames,
                        poses: poses,
                        peakIndex: indexByFrame[stroke.peakFrame],
                        win: win,
                        speedRef: speedRef(for: stroke),
                        hittingArm: result.hittingArm)
        }
    }

    static func sessionScore(_ shots: [ShotScore]) -> SessionScore {
        let graded = shots.filter(\.isGraded)
        let overalls = graded.map(\.overall)

        var consistency = Double.nan
        if overalls.count >= 2 {
            let mean = overalls.reduce(0, +) / Double(overalls.count)
            let variance = overalls.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(overalls.count)
            // 0 spread → 100; ~40-point spread → 0.
            consistency = max(0, min(100, 100 - 2.5 * variance.squareRoot()))
        }

        let best = graded.max { $0.overall < $1.overall }
        let worst = graded.min { $0.overall < $1.overall }

        return SessionScore(
            overall: NanStats.nanMedian(overalls),
            consistency: consistency,
            gradedShots: graded.count,
            totalShots: shots.count,
            best: best?.overall ?? .nan,
            average: overalls.isEmpty ? .nan : overalls.reduce(0, +) / Double(overalls.count),
            worst: worst?.overall ?? .nan,
            bestShotId: best?.strokeId,
            worstShotId: worst?.strokeId)
    }

    // MARK: - Per-stroke

    private static func scoreStroke(_ stroke: Stroke,
                                    frames: [FrameMetrics],
                                    poses: [PoseFrame],
                                    peakIndex: Int?,
                                    win: Int,
                                    speedRef: Double,
                                    hittingArm: HittingArm) -> ShotScore {
        // Window bounds in processed-frame space (clamped like StrokeDetector).
        let p = peakIndex ?? 0
        let a = max(0, p - win)
        let b = min(frames.count - 1, p + win)

        // Tracking coverage: mean fraction of the 12 joints present per
        // window frame. Poses parallel frames; guard against length drift.
        var coverage = 0.0
        if peakIndex != nil, a <= b, !poses.isEmpty {
            var total = 0.0
            var count = 0
            for i in a...b where i < poses.count {
                let joints = poses[i].points.compactMap { $0 }.count
                total += Double(joints) / Double(BodyJoint.allCases.count)
                count += 1
            }
            coverage = count > 0 ? total / Double(count) : 0
        }

        let prep = prepFollowComponent(frames: frames, poses: poses,
                                       peakIndex: peakIndex, win: win,
                                       hittingArm: hittingArm)
        let components: [ShotScoreComponent]
        switch stroke.kind {
        case nil:
            components = [
                speedComponent(stroke: stroke, ref: speedRef, weight: W.speed),
                kneeComponent(stroke.minKnee, weight: W.knee),
                torsoComponent(stroke: stroke, weight: W.torso),
                elbowComponent(stroke.elbowMed, weight: W.elbow),
                stanceComponent(stroke: stroke, weight: W.stance),
                prep.weighted(W.prep),
            ]
        case .serve?:
            components = [
                speedComponent(stroke: stroke, ref: speedRef, weight: Serve.speed),
                kneeComponent(stroke.loadKnee ?? .nan, weight: Serve.knee),
                reachComponent(stroke: stroke, weight: Serve.reach),
                elbowComponent(stroke.contactElbow ?? .nan, weight: Serve.elbow,
                               ideal: FormBands.serveElbowIdeal, soft: FormBands.serveElbowSoft),
                prep.weighted(Serve.prep),
            ]
        case .forehand?, .backhand?, .groundstroke?:
            components = [
                speedComponent(stroke: stroke, ref: speedRef, weight: Groundstroke.speed),
                kneeComponent(stroke.minKnee, weight: Groundstroke.knee),
                torsoComponent(stroke: stroke, weight: Groundstroke.torso),
                elbowComponent(stroke.elbowMed, weight: Groundstroke.elbow),
                stanceComponent(stroke: stroke, weight: Groundstroke.stance),
                prep.weighted(Groundstroke.prep),
                finishComponent(stroke: stroke, weight: Groundstroke.finish),
            ]
        }

        let surviving = components.filter { $0.score.isFinite }
        var overall = Double.nan
        if coverage >= coverageGate, surviving.count >= minSurvivingComponents {
            let weightSum = surviving.reduce(0) { $0 + $1.weight }
            if weightSum > 0 {
                overall = surviving.reduce(0) { $0 + $1.score * $1.weight } / weightSum
            }
        }

        return ShotScore(
            strokeId: stroke.id,
            overall: overall,
            trackingCoverage: coverage,
            confidence: ConfidenceLevel(coverage: coverage),
            components: components,
            strokeKind: stroke.kind,
            timing: stroke.timing)
    }

    // MARK: - Components

    private static func speedComponent(stroke: Stroke, ref: Double, weight: Double) -> ShotScoreComponent {
        var score = Double.nan
        var ratio = Double.nan
        if ref.isFinite, ref > 0, stroke.peakSpeed.isFinite {
            ratio = stroke.peakSpeed / ref
            // Session-relative: 40% of session best → 0, at/above best → 100.
            score = clamp01((ratio - 0.40) / 0.60) * 100
        }
        return ShotScoreComponent(kind: .swingSpeed, score: score,
                                  weight: weight, rawValue: ratio)
    }

    private static func kneeComponent(_ knee: Double, weight: Double) -> ShotScoreComponent {
        ShotScoreComponent(kind: .kneeBend,
                           score: bandScore(knee,
                                            ideal: FormBands.kneeIdeal,
                                            soft: FormBands.kneeSoft),
                           weight: weight, rawValue: knee)
    }

    private static func torsoComponent(stroke: Stroke, weight: Double) -> ShotScoreComponent {
        let lean = stroke.leanAbsMed
        var score = Double.nan
        if lean.isFinite {
            // ≤8° quiet torso → 100; ≥30° → 0; linear between.
            score = clamp01((30 - lean) / (30 - 8)) * 100
        }
        return ShotScoreComponent(kind: .torsoStability, score: score,
                                  weight: weight, rawValue: lean)
    }

    private static func elbowComponent(_ elbow: Double, weight: Double,
                                       ideal: ClosedRange<Double> = FormBands.elbowIdeal,
                                       soft: ClosedRange<Double> = FormBands.elbowSoft) -> ShotScoreComponent {
        ShotScoreComponent(kind: .elbowExtension,
                           score: bandScore(elbow, ideal: ideal, soft: soft),
                           weight: weight, rawValue: elbow)
    }

    private static func stanceComponent(stroke: Stroke, weight: Double) -> ShotScoreComponent {
        ShotScoreComponent(kind: .stanceWidth,
                           score: bandScore(stroke.stanceMed,
                                            ideal: FormBands.stanceIdeal,
                                            soft: FormBands.stanceSoft),
                           weight: weight, rawValue: stroke.stanceMed)
    }

    /// Serves: 100 at `reachIdeal` torso lengths above the shoulders or
    /// higher, 0 at `reachFloor`.
    private static func reachComponent(stroke: Stroke, weight: Double) -> ShotScoreComponent {
        let reach = stroke.reach ?? .nan
        return ShotScoreComponent(kind: .reach,
                                  score: rampScore(reach, from: FormBands.reachFloor, to: FormBands.reachIdeal),
                                  weight: weight, rawValue: reach)
    }

    /// Groundstrokes: 100 when the hand finishes at shoulder height or above.
    private static func finishComponent(stroke: Stroke, weight: Double) -> ShotScoreComponent {
        let finish = stroke.finish ?? .nan
        return ShotScoreComponent(kind: .finish,
                                  score: rampScore(finish, from: FormBands.finishFloor, to: FormBands.finishIdeal),
                                  weight: weight, rawValue: finish)
    }

    /// Prep = fraction of pre-peak steps accelerating toward the peak (a clean
    /// load, not stop-start). Follow-through = tracked, gradually-decaying
    /// post-peak window. Both are within-shot and unit-free.
    private static func prepFollowComponent(frames: [FrameMetrics],
                                            poses: [PoseFrame],
                                            peakIndex: Int?,
                                            win: Int,
                                            hittingArm: HittingArm) -> ShotScoreComponent {
        guard let p = peakIndex else {
            return ShotScoreComponent(kind: .prepFollowThrough, score: .nan,
                                      weight: 0, rawValue: .nan)
        }
        let speeds = frames.map { $0.wristSpeed(for: hittingArm) }
        let peakSpeed = speeds[p]

        // Preparation: rising fraction over [p-win, p].
        var rising = 0, prePairs = 0
        var i = max(0, p - win)
        while i < p {
            if speeds[i].isFinite && speeds[i + 1].isFinite {
                prePairs += 1
                if speeds[i + 1] >= speeds[i] { rising += 1 }
            }
            i += 1
        }

        // Follow-through: tracked fraction + gradual decay over (p, p+win].
        let end = min(frames.count - 1, p + win)
        var tracked = 0, postCount = 0
        var framesUntilHalf = 0
        var reachedHalf = false
        if end > p {
            for j in (p + 1)...end {
                postCount += 1
                if j < poses.count, poses[j].hasAnyJoint { tracked += 1 }
                if !reachedHalf {
                    if speeds[j].isFinite, peakSpeed.isFinite, speeds[j] < 0.5 * peakSpeed {
                        reachedHalf = true
                    } else {
                        framesUntilHalf += 1
                    }
                }
            }
        }

        guard prePairs >= 2, postCount >= 2 else {
            return ShotScoreComponent(kind: .prepFollowThrough, score: .nan,
                                      weight: 0, rawValue: .nan)
        }

        let prepScore = Double(rising) / Double(prePairs)
        let trackedFrac = Double(tracked) / Double(postCount)
        let decayScore = min(1.0, Double(framesUntilHalf) / Double(win))
        let followScore = 0.5 * trackedFrac + 0.5 * decayScore
        let combined = (prepScore + followScore) / 2 * 100

        return ShotScoreComponent(kind: .prepFollowThrough, score: combined,
                                  weight: 0, rawValue: prepScore)
    }

    // MARK: - Helpers

    /// 100 inside `ideal`, tapering linearly to 0 at the `soft` bounds.
    static func bandScore(_ x: Double,
                          ideal: ClosedRange<Double>,
                          soft: ClosedRange<Double>) -> Double {
        guard x.isFinite else { return .nan }
        if ideal.contains(x) { return 100 }
        if x < ideal.lowerBound {
            let span = ideal.lowerBound - soft.lowerBound
            guard span > 0 else { return 0 }
            return clamp01((x - soft.lowerBound) / span) * 100
        } else {
            let span = soft.upperBound - ideal.upperBound
            guard span > 0 else { return 0 }
            return clamp01((soft.upperBound - x) / span) * 100
        }
    }

    /// 0 at `from`, 100 at `to` and beyond, linear between; NaN stays NaN.
    static func rampScore(_ x: Double, from: Double, to: Double) -> Double {
        guard x.isFinite, to != from else { return .nan }
        return clamp01((x - from) / (to - from)) * 100
    }

    private static func clamp01(_ x: Double) -> Double {
        min(1, max(0, x))
    }
}

nonisolated private extension ShotScoreComponent {
    func weighted(_ w: Double) -> ShotScoreComponent {
        var c = self
        c.weight = w
        return c
    }
}
