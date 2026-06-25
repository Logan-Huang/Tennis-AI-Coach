//
//  SessionCard.swift
//  Tennis AI Coach
//

import SwiftUI
import AVFoundation

struct SessionCard: View {
    let session: Session
    @State private var thumbnail: Image?

    private var strokeCount: Int { session.result.strokes.count }

    var body: some View {
        HStack(spacing: 14) {
            thumbnailView
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    ScoreBadge(text: "\(strokeCount) strokes", tint: Theme.court)
                    ScoreBadge(text: "\(session.result.hittingArm.displayName) arm", tint: Theme.clay)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
        .task(id: session.id) { await loadThumbnail() }
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.courtDeep.opacity(0.15))
            if let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "figure.tennis")
                    .font(.title2)
                    .foregroundStyle(Theme.court)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
