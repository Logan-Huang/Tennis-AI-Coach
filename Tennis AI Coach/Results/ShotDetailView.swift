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
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
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

    private var title: String {
        guard let kind = stroke?.kind else { return "Swing \(shot.strokeId)" }
        return "\(kind.displayName) · Swing \(shot.strokeId)"
    }

    private var footnote: String {
        var parts = ["Scores are a 2D estimate from video — indicative, not a measurement. Knee and elbow angles are only graded while that limb faces the camera side-on."]
        switch stroke?.timing {
        case .heard?: parts.append("Contact was timed from the sound of the ball.")
        case .estimated?: parts.append("No ball sound was found, so contact was taken as your fastest wrist moment.")
        case nil: break
        }
        let family = stroke?.kind.map { $0 == .serve ? "serve" : $0.displayName.lowercased() } ?? "swing"
        parts.append("Swing speed is relative to your fastest \(family) this session.")
        return parts.joined(separator: " ")
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            ScoreRing(score: shot.overall, size: .hero, showBandLabel: true)
            HStack(spacing: Theme.Spacing.s) {
                if let stroke {
                    Text("\(stroke.kind?.displayName ?? "Swing") \(shot.strokeId) · \(Fmt.time(stroke.peakTime))")
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
        Fmt.component(c.kind, c.rawValue)
    }
}
