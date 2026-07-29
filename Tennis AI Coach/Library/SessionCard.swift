//
//  SessionCard.swift
//  Tennis AI Coach
//

import SwiftUI
import AVFoundation

struct SessionCard: View {
    let session: Session
    /// Session score from the library cache (NaN = ungraded).
    var score: Double = .nan

    @State private var thumbnail: Image?

    private var strokeCount: Int { session.result.strokes.count }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            thumbnailView

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(relativeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(strokeCount == 1 ? "1 SWING" : "\(strokeCount) SWINGS")
                    .microLabel()
            }

            Spacer(minLength: 0)

            ScoreRing(score: score, size: .row)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .interactiveCardStyle()
        .task(id: session.id) { await loadThumbnail() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var relativeTitle: String {
        let relative = session.createdAt.formatted(.relative(presentation: .named))
        return relative.prefix(1).uppercased() + relative.dropFirst()
    }

    private var accessibilityText: String {
        let scorePart = score.isFinite
            ? "form score \(Int(score.rounded())), \(ScoreBand(score: score).label)"
            : "not graded"
        return "Session \(relativeTitle), \(strokeCount) swings, \(scorePart)"
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                .fill(Theme.courtDeep.opacity(0.12))
            if let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .redacted(reason: .placeholder)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
        .animation(.smooth(duration: 0.25), value: thumbnail == nil)
        .accessibilityHidden(true)
    }

    private func loadThumbnail() async {
        let asset = AVURLAsset(url: session.videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 256, height: 256)
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        if let cgImage = try? await generator.image(at: time).image {
            thumbnail = Image(decorative: cgImage, scale: 1)
        }
    }
}
