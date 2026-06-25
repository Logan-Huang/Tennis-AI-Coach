//
//  CoachingEngine.swift
//  Tennis AI Coach
//
//  Exact port of the notebook's cell 14 — summarize_metrics + the rule-based
//  generate_suggestions. Thresholds are verbatim; the prose is faithful to the
//  notebook's coaching cues.
//

import Foundation

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
            if knee > 155 {
                focus.append("Bend your knees more during the loading phase — aim for a lower, athletic base (often around 120–145° at contact).")
            } else if knee < 110 {
                focus.append("You get very low on some swings. Keep the knee bend but stay stacked over your base so you don't lose balance.")
            } else {
                good.append("Knee bend looks generally athletic on many swings.")
            }
        }

        // Stance width (at-stroke median, fall back to global).
        let stance = summary.stanceStrokeMed.isFinite ? summary.stanceStrokeMed : summary.stanceGlobalMed
        if stance.isFinite {
            if stance < 0.95 {
                focus.append("Your base looks narrow. A slightly wider stance will improve balance and let you transfer more power into the shot.")
            } else if stance > 1.9 {
                focus.append("Your base can get very wide. A more balanced width keeps you mobile and recovering between shots.")
            } else {
                good.append("Stance width looks balanced most of the time.")
            }
        }

        // Torso lean (at-stroke median, fall back to global).
        let lean = summary.leanAbsStrokeMed.isFinite ? summary.leanAbsStrokeMed : summary.leanAbsGlobalMed
        if lean.isFinite {
            if lean > 22 {
                focus.append("You lean your torso a lot through contact. Staying more centered and rotating from your core adds consistency.")
            } else {
                good.append("Torso stays relatively centered on many swings.")
            }
        }

        // Hitting-arm elbow (at-stroke median only — no global fallback).
        let elbow = summary.elbowStrokeMed
        if elbow.isFinite {
            let arm = hittingArm.displayName.lowercased()
            if elbow < 75 {
                focus.append("Your \(arm) hitting-arm elbow looks quite bent. Create space and extend through contact instead of collapsing the arm.")
            } else if elbow > 155 {
                focus.append("Your \(arm) hitting arm can look very straight. Keep a relaxed arm with smooth extension rather than locking it out.")
            } else {
                good.append("Hitting-arm elbow position looks reasonable on many swings.")
            }
        }

        if summary.strokesDetected < 4 {
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
        lines.append("# Tennis AI Coaching Report")
        lines.append("")
        lines.append("**Duration:** \(fmt(summary.durationS))s  •  **Frames analyzed:** \(summary.framesProcessed)  •  **Strokes detected:** \(summary.strokesDetected)")
        lines.append("")
        lines.append("## Snapshot (medians)")
        lines.append("- Knee (more-bent): \(fmt(summary.kneeMinStrokeMed.isFinite ? summary.kneeMinStrokeMed : summary.kneeMinGlobalMed))°")
        lines.append("- Torso lean (abs): \(fmt(summary.leanAbsStrokeMed.isFinite ? summary.leanAbsStrokeMed : summary.leanAbsGlobalMed))°")
        lines.append("- Stance width ratio: \(fmt(summary.stanceStrokeMed.isFinite ? summary.stanceStrokeMed : summary.stanceGlobalMed))")
        lines.append("- Hitting-arm (\(hittingArm.displayName)) elbow: \(fmt(summary.elbowStrokeMed))°")
        lines.append("- Peak wrist speed: \(fmt(summary.peakSpeedMed, decimals: 0)) px/s")
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
