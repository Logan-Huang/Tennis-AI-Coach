//
//  StrokeListView.swift
//  Tennis AI Coach
//
//  Scored shot cards inside the Session Report. Tapping a card opens the
//  per-shot breakdown (zoom transition); the play affordance seeks the
//  inline video instead.
//

import SwiftUI

struct ShotListSection: View {
    let shots: [ShotScore]
    let strokes: [Stroke]
    let namespace: Namespace.ID
    let onOpenDetail: (Int) -> Void      // index into shots
    let onSeek: (Double) -> Void         // peakTime

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "Swings", count: strokes.count)

            ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                if let stroke = strokes.first(where: { $0.id == shot.strokeId }) {
                    shotCard(shot: shot, stroke: stroke, index: index)
                }
            }
        }
    }

    private func shotCard(shot: ShotScore, stroke: Stroke, index: Int) -> some View {
        Button {
            onOpenDetail(index)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                ScoreRing(score: shot.overall, size: .row)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text("SWING \(stroke.id) · \(Fmt.time(stroke.peakTime))")
                            .microLabel()
                        if shot.confidence != .high {
                            ConfidenceChip(level: shot.confidence)
                        }
                    }
                    if shot.isGraded, let weakest = shot.weakestFormComponent {
                        Text("Lowest: \(weakest.kind.displayName.lowercased())")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    } else if !shot.isGraded {
                        Text("Low tracking on this swing")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                // Secondary affordance: jump the inline video to this swing.
                Button {
                    onSeek(stroke.peakTime)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.court)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play swing \(stroke.id) in the video")

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .interactiveCardStyle()
        }
        .buttonStyle(CardButtonStyle())
        .matchedTransitionSource(id: shot.strokeId, in: namespace)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(shot: shot, stroke: stroke))
    }

    private func accessibilityText(shot: ShotScore, stroke: Stroke) -> String {
        if shot.isGraded {
            return "Swing \(stroke.id), score \(Int(shot.overall.rounded())), \(shot.band.label), at \(Fmt.time(stroke.peakTime))"
        }
        return "Swing \(stroke.id), not graded, low tracking, at \(Fmt.time(stroke.peakTime))"
    }
}
