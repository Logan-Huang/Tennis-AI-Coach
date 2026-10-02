//
//  CoachingEngine.swift
//  Tennis AI Coach
//
//  Exact port of the notebook's cell 14 — summarize_metrics + the rule-based
//  generate_suggestions. Thresholds are verbatim; the prose is faithful to the
//  notebook's coaching cues.
//

import Foundation

/// The form thresholds the coaching prose speaks to — extracted so
/// ShotScorer and Narrative use the IDENTICAL numbers (no drifting literals).
///
/// Every standard is absolute: what a well-struck stroke looks like, not
/// this player's best of the day. A ramp's floor is where a first-timer's
/// arm-only swing sits and its top is a sound, committed stroke, so full
/// marks mean the body did its job. The targets come from published tennis
/// biomechanics (Reid, Elliott & Crespo 2013, J Sports Sci Med 12:225 on the
/// forehand; Landlinger et al. 2010, J Sports Sci Med 9:643; trophy-position
/// knee flexion from Frontiers in Sports and Active Living 2024), then were
/// checked on IMG_7145 (a competent player's forehands) and on the same
/// forehand with the body frozen upright and unturned, the way a first-timer
/// swings.
nonisolated enum FormBands {
    /// Knee angle at the deepest point of the load before contact, estimated
    /// from how far the hips sank (SwingKinematics) or measured where the leg
    /// is side-on. Standing tall is 165-180°; a loaded groundstroke 115-140°.
    static let kneeIdeal: ClosedRange<Double> = 115...140
    static let kneeSoft: ClosedRange<Double> = 95...168
    /// A serve sits lower in the trophy position before driving up: skilled
    /// servers flex the front knee 64 ± 10° and the back 67 ± 16°, a knee
    /// angle around 115°.
    static let serveKneeIdeal: ClosedRange<Double> = 105...128
    static let serveKneeSoft: ClosedRange<Double> = 90...160
    /// Hips rising back toward standing height from the load to contact,
    /// fraction of standing height: the legs pushing up into the shot.
    static let legDriveFull: Double = 0.10
    static let serveLegDriveFloor: Double = 0.03
    static let serveLegDriveFull: Double = 0.15
    /// Share of the knee component that is the drive rather than the load.
    static let legDriveShare: Double = 0.25

    /// Degrees the shoulders rotate from the end of the backswing to 0.3 s
    /// after contact. Skilled players coil the shoulders about 110° from
    /// parallel to the baseline (hips about 90°), are square to the net at
    /// contact and keep turning into the finish; IMG_7145's forehands measure
    /// 106-134°. An arm swing barely moves them, and a still player reads 0.
    static let shoulderTurnFloor: Double = 40
    static let shoulderTurnFull: Double = 120
    /// Racquet shoulder's peak speed as a fraction of the hand's: how much of
    /// the swing the trunk drove. Elite forehands move the shoulder at about
    /// 3 m/s, a tenth of racquet speed and so about a fifth of the hand's;
    /// IMG_7145 measures 0.15-0.18 and an arm swing about 0.05.
    static let trunkShareFloor: Double = 0.06
    static let trunkShareFull: Double = 0.20
    /// The shoulder peaking this long after the hand is the arm leading.
    static let lateShoulderS: Double = 0.04
    static let lateShoulderFactor: Double = 0.6

    /// Racquet hand's peak speed, torso lengths per second relative to the
    /// hips, as the app measures it (2D and smoothed, which reads about 0.6 of
    /// the true 3D speed). Racquet heads move at 21-24 m/s for club players
    /// and about 33 m/s for professionals, the hand at about half that; with a
    /// torso of about half a metre, that's 13 and 19 here. IMG_7145's rally
    /// forehands measure 9-16.
    static let speedFloor: Double = 5
    static let speedFull: Double = 18
    static let serveSpeedFloor: Double = 8
    static let serveSpeedFull: Double = 26

    /// The racquet shoulder's dip below the other in the trophy position,
    /// degrees. Skilled servers incline the trunk about 25 ± 7° there; a
    /// level-shouldered serve is all arm.
    static let shoulderTiltFloor: Double = 8
    static let shoulderTiltFull: Double = 25

    static let stanceIdeal: ClosedRange<Double> = 0.95...1.9
    /// An open-stance forehand can legitimately reach 2.5-3 hip widths.
    static let stanceSoft: ClosedRange<Double> = 0.6...3.0
    /// Torso lean the coaching text calls a fault, degrees.
    static let leanMax: Double = 22
    /// Torso lean scores 100 up to `leanFull` and 0 from `leanZero`.
    static let leanFull: Double = 10
    static let leanZero: Double = 35
    /// Hitting elbow at contact. A straight-arm and a bent-arm forehand are
    /// both sound (about 130° with an Eastern grip, 100° with a Western); an
    /// arm jammed against the body is the fault.
    static let elbowIdeal: ClosedRange<Double> = 95...178
    static let elbowSoft: ClosedRange<Double> = 70...180
    /// A serve is struck with the arm close to straight.
    static let serveElbowIdeal: ClosedRange<Double> = 150...180
    static let serveElbowSoft: ClosedRange<Double> = 110...180
    /// Serve reach: the hand's height above the shoulders at contact, in
    /// torso lengths. A fully extended arm puts it about 1.1-1.3 above; the
    /// labelled serves measured 0.82-1.13.
    static let reachIdeal: Double = 1.05
    static let reachFloor: Double = 0.5
    /// Groundstroke finish: the hand's highest point in the half second after
    /// contact, torso lengths above the shoulders. A finish over the shoulder
    /// puts the racquet wrist at or above shoulder height (-0.15-0.45 on the
    /// labelled strokes); a swing that stops at the chest or the waist
    /// doesn't get there.
    static let finishIdeal: Double = 0.1
    static let finishFloor: Double = -0.6
    /// Below this stroke count, session-level conclusions are provisional.
    static let minStrokesForConfidence = 4
}

nonisolated enum CoachingEngine {

    static func summarize(frames: [FrameMetrics], strokes: [Stroke]) -> AnalysisSummary {
        let duration = frames.last?.timeS ?? 0
        let kneeMinEach = NanStats.elementwiseNanMin(frames.map(\.kneeL), frames.map(\.kneeR))

        var summary = AnalysisSummary(
            durationS: duration,
            framesProcessed: frames.count,
            strokesDetected: strokes.count,
            kneeMinGlobalMed: NanStats.nanMedian(kneeMinEach),
            leanAbsGlobalMed: NanStats.nanMedian(frames.map(\.torsoLeanAbs)),
            stanceGlobalMed: NanStats.nanMedian(frames.map(\.stanceRatio)),
            kneeMinStrokeMed: .nan,
            leanAbsStrokeMed: .nan,
            stanceStrokeMed: .nan,
            elbowStrokeMed: .nan,
            peakSpeedMed: .nan)

        if !strokes.isEmpty {
            summary.kneeMinStrokeMed = NanStats.nanMedian(strokes.map(\.minKnee))
            summary.leanAbsStrokeMed = NanStats.nanMedian(strokes.map(\.leanAbsMed))
            summary.stanceStrokeMed = NanStats.nanMedian(strokes.map(\.stanceMed))
            summary.elbowStrokeMed = NanStats.nanMedian(strokes.map(\.elbowMed))
            summary.peakSpeedMed = NanStats.nanMedian(strokes.map(\.peakSpeed))
        }
        return summary
    }

    static func generate(summary: AnalysisSummary, hittingArm: HittingArm) -> CoachingReport {
        var good: [String] = []
        var focus: [String] = []

        // Knee (at-stroke median, fall back to global).
        let knee = summary.kneeMinStrokeMed.isFinite ? summary.kneeMinStrokeMed : summary.kneeMinGlobalMed
        if knee.isFinite {
            if knee > FormBands.kneeIdeal.upperBound {
                focus.append("Bend your knees more during the loading phase — aim for a lower, athletic base (often around 120–145° at contact).")
            } else if knee < FormBands.kneeIdeal.lowerBound {
                focus.append("You get very low on some swings. Keep the knee bend but stay stacked over your base so you don't lose balance.")
            } else {
                good.append("Knee bend looks generally athletic on many swings.")
            }
        }

        // Stance width (at-stroke median, fall back to global).
        let stance = summary.stanceStrokeMed.isFinite ? summary.stanceStrokeMed : summary.stanceGlobalMed
        if stance.isFinite {
            if stance < FormBands.stanceIdeal.lowerBound {
                focus.append("Your base looks narrow. A slightly wider stance will improve balance and let you transfer more power into the shot.")
            } else if stance > FormBands.stanceIdeal.upperBound {
                focus.append("Your base can get very wide. A more balanced width keeps you mobile and recovering between shots.")
            } else {
                good.append("Stance width looks balanced most of the time.")
            }
        }

        // Torso lean (at-stroke median, fall back to global).
        let lean = summary.leanAbsStrokeMed.isFinite ? summary.leanAbsStrokeMed : summary.leanAbsGlobalMed
        if lean.isFinite {
            if lean > FormBands.leanMax {
                focus.append("You lean your torso a lot through contact. Staying more centered and rotating from your core adds consistency.")
            } else {
                good.append("Torso stays relatively centered on many swings.")
            }
        }

        // Hitting-arm elbow (at-stroke median only — no global fallback).
        let elbow = summary.elbowStrokeMed
        if elbow.isFinite {
            let arm = hittingArm.displayName.lowercased()
            if elbow < FormBands.elbowIdeal.lowerBound {
                focus.append("Your \(arm) hitting-arm elbow looks quite bent. Create space and extend through contact instead of collapsing the arm.")
            } else if elbow > FormBands.elbowIdeal.upperBound {
                focus.append("Your \(arm) hitting arm can look very straight. Keep a relaxed arm with smooth extension rather than locking it out.")
            } else {
                good.append("Hitting-arm elbow position looks reasonable on many swings.")
            }
        }

        if summary.strokesDetected < FormBands.minStrokesForConfidence {
            focus.append("Only a few swing moments were detected. Film from the side with your full body visible to capture more strokes.")
        }
        focus.append("For more accurate feedback, film with your full body visible, good lighting, and the camera roughly side-on to the baseline.")

        let markdown = buildMarkdown(summary: summary, hittingArm: hittingArm, good: good, focus: focus)
        return CoachingReport(good: good, focus: focus, markdown: markdown)
    }

    // MARK: - Markdown report

    private static func fmt(_ x: Double, decimals: Int = 1) -> String {
        guard x.isFinite else { return "n/a" }
        return String(format: "%.\(decimals)f", x)
    }

    private static func buildMarkdown(summary: AnalysisSummary,
                                      hittingArm: HittingArm,
                                      good: [String],
                                      focus: [String]) -> String {
        var lines: [String] = []
        lines.append("# Tennis Strokedex Coaching Report")
        lines.append("")
        lines.append("**Duration:** \(fmt(summary.durationS))s  •  **Frames analyzed:** \(summary.framesProcessed)  •  **Strokes detected:** \(summary.strokesDetected)")
        lines.append("")
        lines.append("## Snapshot (medians)")
        lines.append("- Knee (more-bent): \(fmt(summary.kneeMinStrokeMed.isFinite ? summary.kneeMinStrokeMed : summary.kneeMinGlobalMed))°")
        lines.append("- Torso lean (abs): \(fmt(summary.leanAbsStrokeMed.isFinite ? summary.leanAbsStrokeMed : summary.leanAbsGlobalMed))°")
        lines.append("- Stance width ratio: \(fmt(summary.stanceStrokeMed.isFinite ? summary.stanceStrokeMed : summary.stanceGlobalMed))")
        lines.append("- Hitting-arm (\(hittingArm.displayName)) elbow: \(fmt(summary.elbowStrokeMed))°")
        // Wrist speed is uncalibrated pixels — reported as an internal index only.
        lines.append("- Peak wrist speed (relative index): \(fmt(summary.peakSpeedMed, decimals: 0))")
        lines.append("")
        lines.append("## What looks good")
        if good.isEmpty {
            lines.append("- n/a (insufficient landmarks/visibility in video)")
        } else {
            good.forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Focus next")
        focus.forEach { lines.append("- \($0)") }
        return lines.joined(separator: "\n")
    }
}
