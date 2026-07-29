//
//  ChartsView.swift
//  Tennis AI Coach
//

import SwiftUI
import Charts

private struct SeriesPoint: Identifiable {
    let id = UUID()
    let t: Double
    let v: Double
    let segment: Int
}

struct ChartsView: View {
    let result: AnalysisResult
    let playback: PlaybackModel
    var shotScores: [ShotScore] = []

    private var maxTime: Double { result.frames.last?.timeS ?? 1 }

    /// Band color per stroke id — chart markers carry score semantics.
    private var bandById: [Int: Color] {
        Dictionary(uniqueKeysWithValues: shotScores.map { ($0.strokeId, $0.band.color) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                chartCard(
                    title: "Wrist speed (\(result.hittingArm.displayName) arm)",
                    subtitle: "Marker color is that swing's score band. Values are relative — pixel units, not real speed.",
                    points: speedPoints,
                    color: Theme.court,
                    markers: result.strokes.map { ($0.peakTime, $0.peakSpeed, bandById[$0.id] ?? Theme.clay) },
                    unit: "relative")

                chartCard(
                    title: "Knee bend over time",
                    subtitle: "Lower = more bend. Green band is the athletic range.",
                    points: kneePoints,
                    color: Theme.clay,
                    band: FormBands.kneeIdeal,
                    unit: "°")
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Metric explorer")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Chart card

    @ViewBuilder
    private func chartCard(title: String, subtitle: String,
                           points: [SeriesPoint], color: Color,
                           markers: [(Double, Double, Color)] = [],
                           band: ClosedRange<Double>? = nil,
                           unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)

            if points.count < 2 {
                ContentUnavailableView {
                    Label("Not enough tracking data", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("This metric couldn't be measured across enough frames.")
                }
                .frame(height: 220)
            } else {
            Chart {
                if let band {
                    RectangleMark(
                        xStart: .value("Start", 0),
                        xEnd: .value("End", maxTime),
                        yStart: .value("Low", band.lowerBound),
                        yEnd: .value("High", band.upperBound))
                        .foregroundStyle(Theme.good.opacity(0.12))
                }

                ForEach(points) { p in
                    LineMark(
                        x: .value("Time", p.t),
                        y: .value("Value", p.v),
                        series: .value("seg", p.segment))
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                }

                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    PointMark(
                        x: .value("Time", marker.0),
                        y: .value("Value", marker.1))
                        .foregroundStyle(marker.2)
                        .symbolSize(70)
                }

                RuleMark(x: .value("Now", min(playback.currentTime, maxTime)))
                    .foregroundStyle(Theme.court.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(Fmt.time(playback.currentTime))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.s - 2)
                            .padding(.vertical, 2)
                            .background(Theme.court.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.court)
                    }
            }
            .chartXAxisLabel("seconds")
            .chartYAxisLabel(unit)
            .frame(height: 220)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let x = value.location.x - geo[plotFrame].origin.x
                                    if let t = proxy.value(atX: x, as: Double.self) {
                                        playback.seek(to: min(max(0, t), maxTime))
                                    }
                                })
                }
            }
            }
        }
        .cardStyle()
    }

    // MARK: - Series building (NaN-segmented so gaps render as breaks)

    private var speedPoints: [SeriesPoint] {
        segmented(result.frames.map { ($0.timeS, $0.wristSpeed(for: result.hittingArm)) })
    }

    private var kneePoints: [SeriesPoint] {
        segmented(result.frames.map { ($0.timeS, $0.kneeMin) })
    }

    private func segmented(_ series: [(Double, Double)]) -> [SeriesPoint] {
        var points: [SeriesPoint] = []
        var segment = 0
        var prevFinite = false
        for (t, v) in series {
            if v.isFinite {
                if !prevFinite && !points.isEmpty { segment += 1 }
                points.append(SeriesPoint(t: t, v: v, segment: segment))
                prevFinite = true
            } else {
                prevFinite = false
            }
        }
        return points
    }
}
