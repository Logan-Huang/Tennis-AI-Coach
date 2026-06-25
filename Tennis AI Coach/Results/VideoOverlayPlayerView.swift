//
//  VideoOverlayPlayerView.swift
//  Tennis AI Coach
//
//  AVPlayer with a live skeleton + metric HUD drawn on top, plus transport.
//  The player container is constrained to the video's aspect ratio so the
//  overlay maps normalized joints onto the displayed frame with no letterbox math.
//

import SwiftUI
import AVFoundation

struct VideoOverlayPlayerView: View {
    let playback: PlaybackModel

    var body: some View {
        let aspect = max(0.1, playback.videoSize.width / playback.videoSize.height)
        let pose = playback.currentPose()
        let frame = playback.currentFrame()

        VStack(spacing: 0) {
            ZStack {
                Color.black
                VideoPlayerLayer(player: playback.player)
                SkeletonOverlay(pose: pose)
                if let frame {
                    hud(frame)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(10)
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)

            transport
                .padding()
            Spacer(minLength: 0)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func hud(_ frame: FrameMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("t \(Fmt.time(frame.timeS))")
            Text("knee \(Fmt.deg(frame.kneeMin))")
            Text("lean \(Fmt.deg(frame.torsoLean))")
            Text("wrist \(Fmt.speed(frame.wristSpeed(for: playback.hittingArm))) px/s")
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlay()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.court)
            }

            Text(Fmt.time(playback.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { min(playback.currentTime, max(0.1, playback.duration)) },
                    set: { playback.seek(to: $0) }),
                in: 0...max(0.1, playback.duration),
                onEditingChanged: { editing in playback.isScrubbing = editing }
            )
            .tint(Theme.court)

            Text(Fmt.time(playback.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Skeleton overlay

struct SkeletonOverlay: View {
    let pose: PoseFrame?

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            let points: [CGPoint?] = pose.points.map { normalized in
                normalized.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            }

            var bonePath = Path()
            for (a, b) in JointMapping.boneIndices {
                guard a < points.count, b < points.count,
                      let pa = points[a], let pb = points[b] else { continue }
                bonePath.move(to: pa)
                bonePath.addLine(to: pb)
            }
            context.stroke(bonePath, with: .color(Theme.courtLight),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            for case let point? in points {
                let r: CGFloat = 4
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                    with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Player layer

struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
