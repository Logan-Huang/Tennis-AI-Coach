//
//  RecordView.swift
//  Tennis AI Coach
//

import SwiftUI
import AVFoundation
import AVKit
import UIKit

struct RecordView: View {
    let onRecorded: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = CameraController()
    @State private var reviewURL: URL?
    @AppStorage("showFramingGuide") private var showFramingGuide = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch controller.permission {
            case .authorized:
                if let reviewURL {
                    reviewOverlay(reviewURL)
                } else {
                    cameraUI
                }
            case .denied:
                deniedUI
            case .unknown:
                ProgressView().tint(.white)
            }
        }
        .task { await controller.prepare() }
        .onDisappear { controller.stopSession() }
        .onChange(of: controller.recordedURL) { _, url in
            if let url { reviewURL = url }
        }
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .medium), trigger: controller.isRecording)
    }

    // MARK: - Camera

    private var cameraUI: some View {
        ZStack {
            CameraPreview(session: controller.session)
                .ignoresSafeArea()

            if showFramingGuide && !controller.isRecording {
                framingGuide
            }

            VStack {
                topBar
                Spacer()
                if controller.isRecording {
                    Text(Fmt.time(controller.elapsed))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(.red.opacity(0.85), in: Capsule())
                        .accessibilityLabel("Recording, \(Fmt.time(controller.elapsed))")
                }
                Spacer()
                recordControls
            }
            .padding()
        }
    }

    /// Guidance that directly improves analysis quality: side-on, full body.
    private var framingGuide: some View {
        VStack {
            Spacer()
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "figure.tennis")
                    .accessibilityHidden(true)
                Text("Film side-on to the baseline, whole body in frame")
                    .font(.footnote.weight(.medium))
                Button {
                    withAnimation(.smooth) { showFramingGuide = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .accessibilityLabel("Dismiss framing tip")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s + 2)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 130)
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: Theme.Spacing.s) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Close camera")

                Spacer()

                Button {
                    controller.toggleCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .disabled(controller.isRecording)
                .accessibilityLabel("Switch camera")
            }
        }
    }

    private var recordControls: some View {
        Button {
            if controller.isRecording {
                controller.stopRecording()
            } else {
                controller.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 5)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: controller.isRecording ? 6 : 33, style: .continuous)
                    .fill(.red)
                    .frame(width: controller.isRecording ? 34 : 64,
                           height: controller.isRecording ? 34 : 64)
                    .animation(.easeInOut(duration: 0.2), value: controller.isRecording)
            }
        }
        .accessibilityLabel(controller.isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Review (looping preview of the take)

    private func reviewOverlay(_ url: URL) -> some View {
        ZStack {
            LoopingPlayerView(url: url)
                .ignoresSafeArea()

            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(spacing: Theme.Spacing.m - 4) {
                    Button {
                        onRecorded(url)
                    } label: {
                        Label("Analyze video", systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionButton()

                    Button {
                        reviewURL = nil
                        controller.resetForRetake()
                        controller.startSession()
                    } label: {
                        Text("Retake")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryActionButton()
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.l)
            }
        }
    }

    // MARK: - Denied

    private var deniedUI: some View {
        VStack(spacing: Theme.Spacing.m) {
            PermissionDeniedState()
                .colorScheme(.dark)
            Button("Close") { dismiss() }
                .secondaryActionButton()
        }
        .padding()
    }
}

// MARK: - Looping muted preview

private struct LoopingPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerLoopView {
        let view = PlayerLoopView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: PlayerLoopView, context: Context) {}

    final class PlayerLoopView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var looper: AVPlayerLooper?

        func configure(url: URL) {
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: item)
            let layer = self.layer as! AVPlayerLayer
            layer.player = player
            layer.videoGravity = .resizeAspect
            player.play()
        }
    }
}
