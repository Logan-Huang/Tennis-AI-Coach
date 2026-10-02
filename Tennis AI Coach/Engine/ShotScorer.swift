//
//  ShotScorer.swift
//  Tennis AI Coach
//
//  Per-shot 0–100 form scoring over the existing analysis data. Pure compute,
//  lazily invoked at display time — nothing here is persisted, so every saved
//  session is graded by the current rules.
//
//  Design rules:
//  - Fixed standards (FormBands), never this session's own best: an
//    80 means the same thing for every player, every day.
//  - The body's work is what's graded: how far the shoulders turned, how far
//    the legs loaded and drove, how much of the swing the trunk drove, and
//    how fast the hand moved as a result (SwingKinematics). A still, upright,
//    arm-only swing breaks none of the old fault rules, and used to score
//    in the 90s; now it can't run more than `powerMargin` above its power.
//  - What a stroke is scored on depends on what it was: a serve on its leg
//    drive, shoulder tilt, reach and arm extension, a groundstroke on its
//    turn, legs, trunk, finish and base.
//  - Missing data (NaN) drops a component; weights renormalize over survivors.
//  - Tracking gate: joint coverage < 0.5 or < 3 surviving components → the
//    shot is UNGRADED (overall = NaN) rather than a made-up number.
//

import Foundation

nonisolated enum ShotScorer {

    // Nominal component weights (renormalized over surviving components).
    private enum Groundstroke {
        static let speed = 0.20
        static let shoulderTurn = 0.20
        static let knee = 0.16
        static let chain = 0.09
        static let finish = 0.14
        static let elbow = 0.06
        static let torso = 0.08
        static let stance = 0.07
    }

    private enum Serve {
        static let speed = 0.22
        static let knee = 0.22
        static let reach = 0.18
        static let tilt = 0.18
        static let elbow = 0.20
    }

    /// How far a shot's score may sit above the weighted mean of its power
    /// components (`Kind.isPower`).
    static let powerMargin = 12.0
    /// The ceiling when none of the power components could be measured: the
    /// form may be clean, but nothing shows the swing was any good.
    static let unprovenCeiling = 70.0

    private static let minSurvivingComponents = 3
    private static let coverageGate = 0.5

    // MARK: - Public API

    static func score(result: AnalysisResult) -> [ShotScore] {
        let frames = result.frames
        let poses = result.poses
        guard !result.strokes.isEmpty, !frames.isEmpty else { return [] }

        let kinematics = SwingKinematics.measure(result)

        // Same window the detector used: ±0.25 s in processed-frame steps.
        let win = max(1, NanStats.pythonRound(
            0.25 * result.meta.fps / Double(max(1, result.meta.sampleStride))))

        // Stroke.peakFrame is an ORIGINAL video frame index; map it back to
        // its position in the processed-frames array.
        var indexByFrame: [Int: Int] = [:]
        for (i, f) in frames.enumerated() { indexByFrame[f.frameIndex] = i }

        return result.strokes.map { stroke in
            var body = kinematics[stroke.id] ?? SwingKinematics()
            // Before the skeleton could give it (no poses), the detector's own
            // speed, when it's in torso lengths rather than image pixels.
            if !body.handSpeed.isFinite, result.hasBodyRelativeSpeeds {
                body.handSpeed = stroke.peakSpeed
            }
            return scoreStroke(stroke,
                               body: body,
                               poses: poses,
                               peakIndex: indexByFrame[stroke.peakFrame],
                               win: win)
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
                                    body: SwingKinematics,
                                    poses: [PoseFrame],
                                    peakIndex: Int?,
                                    win: Int) -> ShotScore {
        // Window bounds in processed-frame space (clamped like StrokeDetector).
        let p = peakIndex ?? 0
        let a = max(0, p - win)
        let b = min(poses.count - 1, p + win)

        // Tracking coverage: mean fraction of the 12 joints present per
        // window frame.
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

        let components: [ShotScoreComponent]
        if stroke.kind == .serve {
            components = [
                speedComponent(body.handSpeed, floor: FormBands.serveSpeedFloor,
                               full: FormBands.serveSpeedFull, weight: Serve.speed),
                kneeComponent(stroke: stroke, body: body, serve: true, weight: Serve.knee),
                reachComponent(stroke: stroke, weight: Serve.reach),
                ShotScoreComponent(kind: .shoulderTilt,
                                   score: rampScore(body.shoulderTilt, from: FormBands.shoulderTiltFloor,
                                                    to: FormBands.shoulderTiltFull),
                                   weight: Serve.tilt, rawValue: body.shoulderTilt),
                elbowComponent(stroke.contactElbow ?? .nan, weight: Serve.elbow,
                               ideal: FormBands.serveElbowIdeal, soft: FormBands.serveElbowSoft),
            ]
        } else {
            // Forehands, backhands, unplaced groundstrokes, and strokes saved
            // before strokes had kinds.
            components = [
                speedComponent(body.handSpeed, floor: FormBands.speedFloor,
                               full: FormBands.speedFull, weight: Groundstroke.speed),
                ShotScoreComponent(kind: .shoulderTurn,
                                   score: rampScore(body.shoulderTurn, from: FormBands.shoulderTurnFloor,
                                                    to: FormBands.shoulderTurnFull),
                                   weight: Groundstroke.shoulderTurn, rawValue: body.shoulderTurn),
                kneeComponent(stroke: stroke, body: body, serve: false, weight: Groundstroke.knee),
                chainComponent(body, weight: Groundstroke.chain),
                finishComponent(stroke: stroke, weight: Groundstroke.finish),
                elbowComponent(stroke.contactElbow ?? stroke.elbowMed, weight: Groundstroke.elbow),
                torsoComponent(stroke: stroke, weight: Groundstroke.torso),
                stanceComponent(stroke: stroke, weight: Groundstroke.stance),
            ]
        }

        let surviving = components.filter { $0.score.isFinite }
        var overall = Double.nan
        if coverage >= coverageGate, surviving.count >= minSurvivingComponents {
            let mean = weightedMean(surviving)
            let power = weightedMean(surviving.filter(\.kind.isPower))
            overall = power.isFinite ? min(mean, power + powerMargin) : min(mean, unprovenCeiling)
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

    private static func speedComponent(_ speed: Double, floor: Double, full: Double,
                                       weight: Double) -> ShotScoreComponent {
        ShotScoreComponent(kind: .swingSpeed,
                           score: rampScore(speed, from: floor, to: full),
                           weight: weight, rawValue: speed)
    }

    /// The load and the drive out of it. The knee angle is estimated from how
    /// far the hips sank, which every camera angle shows; where the ankles
    /// were out of view, the measured knee angle stands in, when the leg was
    /// side-on enough to measure.
    private static func kneeComponent(stroke: Stroke, body: SwingKinematics,
                                      serve: Bool, weight: Double) -> ShotScoreComponent {
        let ideal = serve ? FormBands.serveKneeIdeal : FormBands.kneeIdeal
        let soft = serve ? FormBands.serveKneeSoft : FormBands.kneeSoft
        var knee = body.kneeEstimate
        var drive = Double.nan
        if knee.isFinite {
            drive = serve
                ? rampScore(body.legDrive, from: FormBands.serveLegDriveFloor, to: FormBands.serveLegDriveFull)
                : rampScore(body.legDrive, from: 0, to: FormBands.legDriveFull)
        } else {
            knee = stroke.loadKnee ?? stroke.minKnee
        }
        let load = bandScore(knee, ideal: ideal, soft: soft)
        let score = drive.isFinite
            ? (1 - FormBands.legDriveShare) * load + FormBands.legDriveShare * drive
            : load
        return ShotScoreComponent(kind: .kneeBend, score: score, weight: weight, rawValue: knee)
    }

    private static func chainComponent(_ body: SwingKinematics, weight: Double) -> ShotScoreComponent {
        var score = rampScore(body.trunkShare, from: FormBands.trunkShareFloor, to: FormBands.trunkShareFull)
        if score.isFinite, body.shoulderLead.isFinite, body.shoulderLead < -FormBands.lateShoulderS {
            score *= FormBands.lateShoulderFactor
        }
        return ShotScoreComponent(kind: .kineticChain, score: score, weight: weight, rawValue: body.trunkShare)
    }

    private static func torsoComponent(stroke: Stroke, weight: Double) -> ShotScoreComponent {
        let lean = stroke.leanAbsMed
        let score = lean.isFinite
            ? clamp01((FormBands.leanZero - lean) / (FormBands.leanZero - FormBands.leanFull)) * 100
            : .nan
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

    /// Groundstrokes: 100 when the hand finishes above shoulder height.
    private static func finishComponent(stroke: Stroke, weight: Double) -> ShotScoreComponent {
        let finish = stroke.finish ?? .nan
        return ShotScoreComponent(kind: .finish,
                                  score: rampScore(finish, from: FormBands.finishFloor, to: FormBands.finishIdeal),
                                  weight: weight, rawValue: finish)
    }

    // MARK: - Helpers

    /// Weighted mean of the components' scores; NaN when there are none.
    static func weightedMean(_ components: [ShotScoreComponent]) -> Double {
        let weightSum = components.reduce(0) { $0 + $1.weight }
        guard weightSum > 0 else { return .nan }
        return components.reduce(0) { $0 + $1.score * $1.weight } / weightSum
    }

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
