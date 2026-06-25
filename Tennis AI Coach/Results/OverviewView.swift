//
//  OverviewView.swift
//  Tennis AI Coach
//

import SwiftUI

struct OverviewView: View {
    let result: AnalysisResult

    private var s: AnalysisSummary { result.summary }
    private var kneeVal: Double { s.kneeMinStrokeMed.isFinite ? s.kneeMinStrokeMed : s.kneeMinGlobalMed }
    private var leanVal: Double { s.leanAbsStrokeMed.isFinite ? s.leanAbsStrokeMed : s.leanAbsGlobalMed }
    private var stanceVal: Double { s.stanceStrokeMed.isFinite ? s.stanceStrokeMed : s.stanceGlobalMed }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headline

                LazyVGrid(columns: columns, spacing: 14) {
                    MetricCard(title: "Knee bend (lowest)", value: Fmt.deg(kneeVal),
                               systemImage: "figure.cooldown",
                               tint: status(kneeVal, good: 110...155))
                    MetricCard(title: "Torso lean", value: Fmt.deg(leanVal),
                               systemImage: "figure.walk.motion",
                               tint: leanVal.isFinite ? (leanVal > 22 ? Theme.focus : Theme.good) : Theme.court)
                    MetricCard(title: "Stance width", value: Fmt.ratio(stanceVal),
                               systemImage: "arrow.left.and.right",
                               tint: status(stanceVal, good: 0.95...1.9))
                    MetricCard(title: "\(result.hittingArm.displayName)-arm elbow",
                               value: Fmt.deg(s.elbowStrokeMed),
                               systemImage: "figure.tennis",
                               tint: status(s.elbowStrokeMed, good: 75...155))
                    MetricCard(title: "Peak wrist speed", value: Fmt.speed(s.peakSpeedMed),
                               unit: "px/s", systemImage: "speedometer", tint: Theme.clay)
                    MetricCard(title: "Duration", value: Fmt.seconds(s.durationS),
                               systemImage: "clock", tint: Theme.court)
                }
            }
            .padding()
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(s.strokesDetected)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(s.strokesDetected == 1 ? "stroke detected" : "strokes detected")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "figure.tennis")
                    .font(.system(size: 50))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(takeaway)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var takeaway: String {
        if let firstFocus = result.coaching.focus.first {
            return firstFocus
        }
        return "Great session — your form looks solid across the board."
    }

    private func status(_ value: Double, good range: ClosedRange<Double>) -> Color {
        guard value.isFinite else { return Theme.court }
        return range.contains(value) ? Theme.good : Theme.watch
    }
}
