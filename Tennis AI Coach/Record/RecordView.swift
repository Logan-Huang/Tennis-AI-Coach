//
//  RecordView.swift
//  Tennis AI Coach
//

import SwiftUI
import AVFoundation
import UIKit

struct RecordView: View {
    let onRecorded: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = CameraController()
    @State private var reviewURL: URL?

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
    }

    // MARK: - Camera

    private var cameraUI: some View {
        ZStack {
            CameraPreview(session: controller.session)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if controller.isRecording {
                    Text(Fmt.time(controller.elapsed))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(.red.opacity(0.85), in: Capsule())
                }
                Spacer()
                recordControls
            }
            .padding()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            Spacer()
            Button {
                controller.toggleCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .disabled(controller.isRecording)
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
    }

    // MARK: - Review

    private func reviewOverlay(_ url: URL) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.courtLight)
            Text("Recording ready")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Analyze this clip, or record another take.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            VStack(spacing: 12) {
                Button {
                    onRecorded(url)
                } label: {
                    Text("Analyze video").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.court)

                Button {
                    reviewURL = nil
                    controller.resetForRetake()
                    controller.startSession()
                } label: {
                    Text("Retake").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Denied

    private var deniedUI: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                systemImage: "camera.fill",
                title: "Camera access is off",
                message: "Enable camera and microphone access in Settings to record your sessions.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.court)
            Button("Close") { dismiss() }
                .tint(.white)
        }
        .padding()
    }
}
