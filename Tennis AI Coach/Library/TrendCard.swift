//
//  TrendCard.swift
//  Tennis AI Coach
//
//  Home's progress story: form-score trend line across sessions plus
//  range-band rows for the key form components. Low-data states are hedged
//  ("record another session to unlock your trend"), never hidden.
//

import SwiftUI
import Charts

struct TrendCard: View {
    let trend: [ProgressEngine.SessionProgress]
    let componentTrends: [ProgressEngine.ComponentTrend]

    private var graded: [ProgressEngine.SessionProgress] {
        trend.filter { $0.formScore.isFinite }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Form over time")

            if graded.count >= 2 {
                chart
            } else {
                Text(graded.count == 1
                     ? "One session scored — record another to unlock your trend."
                     : "Your form trend will appear once sessions can be scored.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if componentTrends.contains(where: { $0.current.isFinite }) {
                VStack(spacing: Theme.Spacing.m - 4) {
                    ForEach(componentTrends) { item in
                        RangeBandRow(
                            label: item.kind.displayName,
                            domain: item.domain,
                            range: item.range,
                            current: item.current,
                            currentText: currentText(item))
                    }
                }
            }

            Text("Trend uses form only — swing speed isn't comparable across differently filmed sessions.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
    }

    private var chart: some View {
        Chart {
            ForEach(graded) { point in
                LineMark(
                    x: .value("Session", point.date),
                    y: .value("Form", point.formScore))
                    .foregroundStyle(Theme.court)
                    .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Session", point.date),
                    y: .value("Form", point.formScore))
                    .foregroundStyle(point.id == graded.last?.id ? Theme.clay : Theme.court)
                    .symbolSize(point.id == graded.last?.id ? 80 : 40)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) {
                AxisGridLine().foregroundStyle(Color(.separator))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                    .font(.caption2)
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Form score trend across \(graded.count) sessions, latest \(Fmt.score(graded.last?.formScore ?? .nan))")
    }

    private func currentText(_ item: ProgressEngine.ComponentTrend) -> String {
        guard item.current.isFinite else { return "—" }
        switch item.kind {
        case .kneeBend, .torsoStability, .elbowExtension: return Fmt.deg(item.current)
        case .stanceWidth: return String(format: "%.2f×", item.current)
        default: return Fmt.score(item.current)
        }
    }
}
