//
//  ShotDetailView.swift
//  Tennis AI Coach
//
//  Per-shot report: score ring + band, tracking confidence, component
//  breakdown bars with raw values, and an honesty footer. Pushed from a shot
//  card with a zoom transition; "Watch this swing" pops back and seeks.
//

import SwiftUI

struct ShotDetailView: View {
    let shots: [ShotScore]           // all shots, for the pager
    let strokes: [Stroke]
    @State private var index: Int
    let onWatch: (Stroke) -> Void

    @Environment(\.dismiss) private var dismiss

    init(shots: [ShotScore], strokes: [Stroke], initialIndex: Int,
         onWatch: @escaping (Stroke) -> Void) {
        self.shots = shots
        self.strokes = strokes
        _index = State(initialValue: initialIndex)
        self.onWatch = onWatch
    }

    private var shot: ShotScore { shots[index] }
    private var stroke: Stroke? {
        strokes.first { $0.id == shot.strokeId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header

                VStack(spacing: Theme.Spacing.m) {
                    ForEach(shot.components) { component in
                        ComponentBarRow(
                            name: component.kind.displayName,
                            score: component.score,
                            rawText: rawText(component))
                    }
                }
                .cardStyle()

                if !shot.isGraded {
                    Text("Not enough tracking on this swing to grade it — the skeleton was missing for too much of the window.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let stroke {
                    Button {
                        onWatch(stroke)
                        dismiss()
                    } label: {
                        Label("Watch this swing", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionButton()
                }

                // Honesty footer — the numbers are indicative, not measured truth.
                Text("Scores are a 2D estimate from a side-on camera — indicative, not a measurement. Swing speed is relative to your fastest swing this session.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Swing \(shot.strokeId)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { index = max(0, index - 1) }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                .accessibilityLabel("Previous swing")

                Button {
                    withAnimation(.snappy) { index = min(shots.count - 1, index + 1) }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == shots.count - 1)
                .accessibilityLabel("Next swing")
            }
        }
        .sensoryFeedback(.selection, trigger: index)
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            ScoreRing(score: shot.overall, size: .hero, showBandLabel: true)
            HStack(spacing: Theme.Spacing.s) {
                if let stroke {
                    Text("SWING \(shot.strokeId) · \(Fmt.time(stroke.peakTime))")
                        .microLabel()
                }
                if shot.confidence != .high {
                    ConfidenceChip(level: shot.confidence)
                }
            }
            Text("Shot \(index + 1) of \(shots.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func rawText(_ c: ShotScoreComponent) -> String {
        guard c.rawValue.isFinite else { return "—" }
        switch c.kind {
        case .swingSpeed: return Fmt.relSpeed(c.rawValue)
        case .kneeBend, .torsoStability, .elbowExtension: return Fmt.deg(c.rawValue)
        case .stanceWidth: return String(format: "%.2f× hips", c.rawValue)
        case .prepFollowThrough: return "\(Int((c.rawValue * 100).rounded()))% smooth"
        }
    }
}
