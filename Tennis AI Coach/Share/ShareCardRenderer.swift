//
//  ShareCardRenderer.swift
//  Tennis AI Coach
//
//  Grabs the best-shot frame, draws the skeleton on it (PoseDrawing — same
//  renderer as the live overlay and MP4 export), and renders a share card
//  to a temp PNG for ShareLink.
//

import SwiftUI
import AVFoundation

@MainActor
enum ShareCardRenderer {

    /// Best-shot frame with skeleton, oriented and full-resolution.
    static func annotatedFrame(session: Session, at time: Double) async -> UIImage? {
        let asset = AVURLAsset(url: session.videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: cm).image else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        // Nearest analyzed pose to the requested time.
        let result = session.result
        guard let nearest = result.frames.enumerated().min(by: {
            abs($0.element.timeS - time) < abs($1.element.timeS - time)
        }), nearest.offset < result.poses.count else {
            return UIImage(cgImage: cgImage)
        }
        let pose = result.poses[nearest.offset]

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            PoseDrawing.draw(pose: pose, in: ctx.cgContext, size: size,
                             hittingArm: result.hittingArm,
                             scale: max(0.5, size.height / 1080))
        }
    }

    /// Renders the session card to a shareable PNG URL.
    static func renderSessionCard(session: Session,
                                  score: SessionScore,
                                  headline: String) async -> URL? {
        // Frame of the best swing (fall back to the first stroke, then t=0.2).
        let bestStroke = session.result.strokes.first { $0.id == score.bestShotId }
            ?? session.result.strokes.first
        let time = bestStroke?.peakTime ?? 0.2
        let frame = await annotatedFrame(session: session, at: time)

        let card = SessionShareCard(session: score, headline: headline,
                                    date: session.createdAt, frame: frame)
        return render(card, named: "session-report")
    }

    private static func render(_ view: some View, named name: String) -> URL? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(ShareCardMetrics.size)
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TennisAICoach-\(name).png")
        try? FileManager.default.removeItem(at: url)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
