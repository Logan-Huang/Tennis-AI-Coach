//
//  ExportSheet.swift
//  Tennis AI Coach
//
//  Renders an annotated MP4 (skeleton + metrics burned in) and offers share /
//  save-to-Photos.
//

import SwiftUI
import Photos

@Observable
@MainActor
final class ExportModel {
    enum Phase: Equatable {
        case idle
        case exporting
        case done(URL)
        case failed(String)
    }
    var phase: Phase = .idle
    var progress: Double = 0
    var saveMessage: String?
}

struct ExportSheet: View {
    let session: Session

    @Environment(\.analysisEngine) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var model = ExportModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                switch model.phase {
                case .idle:
                    idleView
                case .exporting:
                    exportingView
                case .done(let url):
                    doneView(url)
                case .failed(let message):
                    failedView(message)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Annotated Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 52))
                .foregroundStyle(Theme.court.gradient)
            Text("Create an annotated clip")
                .font(.title3.weight(.semibold))
            Text("We'll render your video with the skeleton and live metrics drawn on top, ready to share.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                startExport()
            } label: {
                Label("Render video", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.court)
            Spacer()
        }
    }

    private var exportingView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: model.progress)
                .tint(Theme.court)
            Text("Rendering… \(Int(model.progress * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
        }
    }

    private func doneView(_ url: URL) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.good)
            Text("Your annotated video is ready")
                .font(.headline)
                .multilineTextAlignment(.center)

            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.court)

            Button {
                saveToPhotos(url)
            } label: {
                Label("Save to Photos", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(Theme.court)

            if let saveMessage = model.saveMessage {
                Text(saveMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            EmptyStateView(
                systemImage: "exclamationmark.triangle.fill",
                title: "Export failed",
                message: message)
            Button("Try again") { startExport() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.court)
            Spacer()
        }
    }

    // MARK: - Work

    private func startExport() {
        model.phase = .exporting
        model.progress = 0
        model.saveMessage = nil
        let model = model
        Task {
            do {
                let url = try await engine.exportAnnotatedVideo(
                    result: session.result,
                    sourceURL: session.videoURL,
                    progress: { p in Task { @MainActor in model.progress = p } })
                model.phase = .done(url)
            } catch {
                model.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func saveToPhotos(_ url: URL) {
        let model = model
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in model.saveMessage = "Photos access was denied." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { success, error in
                Task { @MainActor in
                    model.saveMessage = success ? "Saved to Photos." : (error?.localizedDescription ?? "Couldn't save.")
                }
            }
        }
    }
}
