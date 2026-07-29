//
//  OverviewView.swift
//  Tennis AI Coach
//
//  Session medians, folded into the bottom of the Session Report. The old
//  gradient headline is superseded by SessionHeroCard; the six-tile grid
//  shrinks to four form metrics with band tinting through one mapper, and
//  wrist speed is session-relative (never px/s).
//

import SwiftUI

struct MediansSection: View {
    let result: AnalysisResult
    /// Median peak speed relative to the session's fastest (NaN when unknown).
    let relSpeedMedian: Double

    private var s: AnalysisSummary { result.summary }
    private var kneeVal: Double { s.kneeMinStrokeMed.isFinite ? s.kneeMinStrokeMed : s.kneeMinGlobalMed }
    private var leanVal: Double { s.leanAbsStrokeMed.isFinite ? s.leanAbsStrokeMed : s.leanAbsGlobalMed }
    private var stanceVal: Double { s.stanceStrokeMed.isFinite ? s.stanceStrokeMed : s.stanceGlobalMed }

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.m - 2),
                           GridItem(.flexible(), spacing: Theme.Spacing.m - 2)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "Session medians")

            LazyVGrid(columns: columns, spacing: Theme.Spacing.m - 2) {
                MetricCard(title: "Knee bend", value: Fmt.deg(kneeVal),
                           systemImage: "figure.cooldown",
                           tint: bandTint(ShotScorer.bandScore(kneeVal, ideal: FormBands.kneeIdeal, soft: FormBands.kneeSoft)))
                MetricCard(title: "Torso lean", value: Fmt.deg(leanVal),
                           systemImage: "figure.walk.motion",
                           tint: leanVal.isFinite ? (leanVal > FormBands.leanMax ? Theme.focus : Theme.good) : Theme.court)
                MetricCard(title: "Stance width", value: stanceVal.isFinite ? String(format: "%.2f× hips", stanceVal) : "—",
                           systemImage: "arrow.left.and.right",
                           tint: bandTint(ShotScorer.bandScore(stanceVal, ideal: FormBands.stanceIdeal, soft: FormBands.stanceSoft)))
                MetricCard(title: "Elbow (\(result.hittingArm.displayName.lowercased()))",
                           value: Fmt.deg(s.elbowStrokeMed),
                           systemImage: "figure.tennis",
                           tint: bandTint(ShotScorer.bandScore(s.elbowStrokeMed, ideal: FormBands.elbowIdeal, soft: FormBands.elbowSoft)))
            }

            if relSpeedMedian.isFinite {
                MetricCard(title: "Median swing speed", value: Fmt.relSpeed(relSpeedMedian),
                           systemImage: "speedometer", tint: Theme.clay)
            }

            // Duration is context, not a stat worth a card.
            Text("Session length \(Fmt.seconds(s.durationS)) · \(s.framesProcessed) frames analyzed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// One mapper: band score → status tint (fixes the old per-tile logic drift).
    private func bandTint(_ score: Double) -> Color {
        guard score.isFinite else { return Theme.court }
        return ScoreBand(score: score).color
    }
}
