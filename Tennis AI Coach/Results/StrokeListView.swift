//
//  StrokeListView.swift
//  Tennis AI Coach
//

import SwiftUI

struct StrokeListView: View {
    let result: AnalysisResult
    let onSeek: (Double) -> Void

    var body: some View {
        if result.strokes.isEmpty {
            EmptyStateView(
                systemImage: "list.bullet.rectangle",
                title: "No strokes detected",
                message: "No clear swing moments were found. Film side-on with your full body visible to capture more strokes.")
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(result.strokes) { stroke in
                        Button {
                            onSeek(stroke.peakTime)
                        } label: {
                            strokeRow(stroke)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private func strokeRow(_ stroke: Stroke) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.court.opacity(0.15))
                Text("\(stroke.id)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.court)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Swing at \(Fmt.time(stroke.peakTime))")
                        .font(.subheadline.weight(.semibold))
                    ScoreBadge(text: "\(Fmt.speed(stroke.peakSpeed)) px/s", tint: Theme.clay)
                }
                HStack(spacing: 12) {
                    miniMetric("Knee", Fmt.deg(stroke.minKnee))
                    miniMetric("Elbow", Fmt.deg(stroke.elbowMed))
                    miniMetric("Lean", Fmt.deg(stroke.leanAbsMed))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.court)
        }
        .cardStyle()
    }

    private func miniMetric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium))
        }
    }
}
