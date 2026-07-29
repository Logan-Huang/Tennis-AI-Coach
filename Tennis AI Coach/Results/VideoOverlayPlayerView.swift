//
//  VideoOverlayPlayerView.swift
//  Tennis AI Coach
//
//  AVPlayer with a live two-tone skeleton (hitting-arm chain in clay, body in
//  court-light — broadcast style), stroke markers on the scrubber, and a
//  floating glass transport with frame-step and slow-motion for form review.
//  The player container is constrained to the video's aspect ratio so the
//  overlay maps normalized joints onto the displayed frame with no letterbox math.
//

import SwiftUI
import AVFoundation

struct VideoOverlayPlayerView: View {
    let playback: PlaybackModel
    /// Stroke peak times for scrubber markers (empty = no markers).
    var strokeTimes: [Double] = []
    /// Embedded = card inside the Session Report (no filler background).
    var embedded: Bool = false

    @State private var showSkeleton = true

    var body: some View {
        let aspect = max(0.1, playback.videoSize.width / playback.videoSize.height)
        let pose = playback.currentPose()
        let frame = playback.currentFrame()

        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ZStack {
                    Color.black
                    VideoPlayerLayer(player: playback.player)
                    if showSkeleton {
                        SkeletonOverlay(pose: pose, hittingArm: playback.hittingArm)
                    }
                    if let frame {
                        hudChips(frame)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(Theme.Spacing.s + 2)
                    }
                }
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)

                transport
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.s + 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: embedded ? Theme.Radius.card : 0, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session video with skeleton overlay")
    }

    // MARK: - HUD

    /// Two compact chips: time, and the frame's key form angles. No px/s.
    private func hudChips(_ frame: FrameMetrics) -> some View {
        HStack(spacing: Theme.Spacing.s - 2) {
            Text(Fmt.time(frame.timeS))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs)
                .foregroundStyle(.white)
                .background(.black.opacity(0.45), in: Capsule())
            if frame.kneeMin.isFinite || frame.torsoLean.isFinite {
                Text("knee \(Fmt.deg(frame.kneeMin)) · lean \(Fmt.deg(frame.torsoLeanAbs))")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xs)
                    .foregroundStyle(.white.opacity(0.9))
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Glass transport

    private var transport: some View {
        GlassEffectContainer(spacing: Theme.Spacing.s) {
            VStack(spacing: Theme.Spacing.xs) {
                scrubber

                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        playback.stepFrame(by: -1)
                    } label: {
                        Image(systemName: "backward.frame.fill")
                            .font(.footnote)
                    }
                    .accessibilityLabel("Step one frame back")

                    Button {
                        playback.togglePlay()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 28)
                    }
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                    Button {
                        playback.stepFrame(by: 1)
                    } label: {
                        Image(systemName: "forward.frame.fill")
                            .font(.footnote)
                    }
                    .accessibilityLabel("Step one frame forward")

                    Text("\(Fmt.time(playback.currentTime)) / \(Fmt.time(playback.duration))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Time \(Fmt.time(playback.currentTime)) of \(Fmt.time(playback.duration))")

                    Spacer(minLength: 0)

                    Menu {
                        ForEach([0.25 as Float, 0.5, 1.0], id: \.self) { rate in
                            Button {
                                playback.playbackRate = rate
                            } label: {
                                if playback.playbackRate == rate {
                                    Label(rateLabel(rate), systemImage: "checkmark")
                                } else {
                                    Text(rateLabel(rate))
                                }
                            }
                        }
                    } label: {
                        Text(rateLabel(playback.playbackRate))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Playback speed \(rateLabel(playback.playbackRate))")

                    Button {
                        withAnimation(.smooth) { showSkeleton.toggle() }
                    } label: {
                        Image(systemName: showSkeleton ? "figure.stand" : "figure.stand.dress.line.vertical.figure")
                            .font(.footnote)
                    }
                    .accessibilityLabel(showSkeleton ? "Hide skeleton" : "Show skeleton")
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s + 2)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card))
        }
        .tint(Theme.court)
        .sensoryFeedback(.selection, trigger: playback.playbackRate)
    }

    /// Slider with stroke tick markers overlaid above the track.
    private var scrubber: some View {
        VStack(spacing: 2) {
            if !strokeTimes.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        ForEach(Array(strokeTimes.enumerated()), id: \.offset) { _, t in
                            Capsule()
                                .fill(Theme.clay)
                                .frame(width: 3, height: 6)
                                .offset(x: markerX(t, width: geo.size.width))
                        }
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }

            Slider(
                value: Binding(
                    get: { min(playback.currentTime, max(0.1, playback.duration)) },
                    set: { playback.seek(to: $0) }),
                in: 0...max(0.1, playback.duration),
                onEditingChanged: { editing in playback.isScrubbing = editing }
            )
            .tint(Theme.court)
            .accessibilityLabel("Video position")
        }
    }

    private func markerX(_ t: Double, width: CGFloat) -> CGFloat {
        guard playback.duration > 0 else { return 0 }
        return max(0, min(width - 3, width * CGFloat(t / playback.duration)))
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "1×" : (rate == 0.5 ? "½×" : "¼×")
    }
}

// MARK: - Skeleton overlay (two-tone broadcast style)

struct SkeletonOverlay: View {
    let pose: PoseFrame?
    var hittingArm: HittingArm = .right

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            // One renderer everywhere: live overlay, MP4 export, share cards.
            context.withCGContext { cg in
                PoseDrawing.draw(pose: pose, in: cg, size: size,
                                 hittingArm: hittingArm, scale: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Skeleton overlay: body pose with the \(hittingArm.displayName.lowercased()) hitting arm highlighted")
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
