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
                        Text("\(stroke.kind?.displayName ?? "Swing") \(stroke.id) · \(Fmt.time(stroke.peakTime))")
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
        let name = "\(stroke.kind?.displayName ?? "Swing") \(stroke.id)"
        if shot.isGraded {
            return "\(name), score \(Int(shot.overall.rounded())), \(shot.band.label), at \(Fmt.time(stroke.peakTime))"
        }
        return "\(name), not graded, low tracking, at \(Fmt.time(stroke.peakTime))"
    }
}

/// How each kind of stroke went: count and median score per kind, so a strong
/// forehand can't hide a weak backhand in the session's single number.
struct StrokeMixCard: View {
    let mix: [Narrative.KindSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "By stroke")
            HStack(spacing: 0) {
                ForEach(Array(mix.enumerated()), id: \.element.id) { i, item in
                    if i > 0 {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 0.5, height: 44)
                    }
                    column(item)
                }
            }
        }
        .cardStyle()
    }

    private func column(_ item: Narrative.KindSummary) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(Fmt.score(item.median))
                .font(.stat)
                .monospacedDigit()
                .foregroundStyle(ScoreBand(score: item.median).color)
            Text(item.kind.pluralName)
                .microLabel()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(item.count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.count) \(item.count == 1 ? item.kind.displayName : item.kind.pluralName)")
        .accessibilityValue(item.median.isFinite ? "median score \(Int(item.median.rounded()))" : "not graded")
    }
}
