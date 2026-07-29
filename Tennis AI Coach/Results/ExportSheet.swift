//
//  ExportSheet.swift
//  Tennis AI Coach
//
//  The Share hub. Summary card first (near-instant, share-worthy), the
//  annotated MP4 render second. clay/court, skeleton-on-frame, honest copy.
//

import SwiftUI
import Photos

@Observable
@MainActor
final class ExportModel {
    enum VideoPhase: Equatable {
        case idle
        case exporting
        case done(URL)
        case failed(String)
    }
    var videoPhase: VideoPhase = .idle
    var progress: Double = 0
    var saveMessage: String?

    var cardURL: URL?
    var cardFailed = false
}

struct ExportSheet: View {
    let session: Session

    enum Tab: String, CaseIterable, Identifiable {
        case card = "Summary card"
        case video = "Annotated video"
        var id: String { rawValue }
    }

    @Environment(\.analysisEngine) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var model = ExportModel()
    @State private var tab: Tab = .card

    // Computed once for the card.
    private let sessionScore: SessionScore
    private let headline: String

    init(session: Session) {
        self.session = session
        let shots = ShotScorer.score(result: session.result)
        let rollup = ShotScorer.sessionScore(shots)
        self.sessionScore = rollup
        self.headline = Narrative.headline(session: rollup, shots: shots)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.m) {
                Picker("Share as", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch tab {
                case .card: cardTab
                case .video: videoTab
                }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.selection, trigger: tab)
        .task { await renderCard() }
    }

    // MARK: - Summary card

    @ViewBuilder
    private var cardTab: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                if let url = model.cardURL, let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .accessibilityLabel("Session summary card preview")

                    ShareLink(item: url, preview: SharePreview("Session report", image: Image(uiImage: image))) {
                        Label("Share card", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionButton()
                    .padding(.horizontal)

                    Button {
                        saveImageToPhotos(url)
                    } label: {
                        Label("Save to Photos", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryActionButton()
                    .padding(.horizontal)

                    if let saveMessage = model.saveMessage {
                        Label(saveMessage,
                              systemImage: saveMessage.hasPrefix("Saved") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(saveMessage.hasPrefix("Saved") ? Theme.good : Theme.focus)
                    }

                    if sessionScore.isProvisional && sessionScore.overall.isFinite {
                        Text("Provisional — based on \(sessionScore.gradedShots) swings.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else if model.cardFailed {
                    ContentUnavailableView {
                        Label("Couldn't build the card", systemImage: "photo.badge.exclamationmark")
                    } description: {
                        Text("The video frame couldn't be read.")
                    } actions: {
                        Button("Try again") { Task { await renderCard() } }
                            .secondaryActionButton()
                    }
                } else {
                    ProgressView("Building your card…")
                        .padding(.top, Theme.Spacing.xl)
                }
            }
        }
    }

    private func renderCard() async {
        model.cardFailed = false
        let url = await ShareCardRenderer.renderSessionCard(
            session: session, score: sessionScore, headline: headline)
        model.cardURL = url
        model.cardFailed = (url == nil)
    }

    // MARK: - Annotated video

    @ViewBuilder
    private var videoTab: some View {
        switch model.videoPhase {
        case .idle:
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "film.stack")
                    .font(.title)
                    .foregroundStyle(Theme.court)
                    .accessibilityHidden(true)
                Text("Render the full clip with the skeleton, form HUD, and per-swing score badges burned in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
                Button {
                    startExport()
                } label: {
                    Label("Render video", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .primaryActionButton()
                .padding(.horizontal)
            }
            .padding(.top, Theme.Spacing.l)

        case .exporting:
            VStack(spacing: Theme.Spacing.m) {
                ProgressView(value: model.progress)
                    .tint(Theme.court)
                    .padding(.horizontal)
                Text("Rendering… \(Int(model.progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.top, Theme.Spacing.xl)

        case .done(let url):
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.good)
                    .symbolEffect(.bounce, options: .nonRepeating)
                    .accessibilityHidden(true)
                Text("Your annotated video is ready")
                    .font(.headline)

                ShareLink(item: url) {
                    Label("Share video", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .primaryActionButton()
                .padding(.horizontal)

                Button {
                    saveVideoToPhotos(url)
                } label: {
                    Label("Save to Photos", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .secondaryActionButton()
                .padding(.horizontal)

                if let saveMessage = model.saveMessage {
                    Label(saveMessage,
                          systemImage: saveMessage.hasPrefix("Saved") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(saveMessage.hasPrefix("Saved") ? Theme.good : Theme.focus)
                }
            }
            .padding(.top, Theme.Spacing.l)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .sensoryFeedback(.success, trigger: model.videoPhase)

        case .failed(let message):
            ExportFailedState(message: message, onRetry: { startExport() })
        }
    }

    // MARK: - Work

    private func startExport() {
        let model = model
        withAnimation(.snappy) { model.videoPhase = .exporting }
        model.progress = 0
        model.saveMessage = nil
        Task {
            do {
                let url = try await engine.exportAnnotatedVideo(
                    result: session.result,
                    sourceURL: session.videoURL,
                    progress: { p in Task { @MainActor in model.progress = p } })
                withAnimation(.snappy) { model.videoPhase = .done(url) }
            } catch {
                withAnimation(.snappy) { model.videoPhase = .failed(error.localizedDescription) }
            }
        }
    }

    private func saveVideoToPhotos(_ url: URL) {
        saveToPhotos { request in
            request.addResource(with: .video, fileURL: url, options: nil)
        }
    }

    private func saveImageToPhotos(_ url: URL) {
        saveToPhotos { request in
            request.addResource(with: .photo, fileURL: url, options: nil)
        }
    }

    private func saveToPhotos(_ configure: @escaping @Sendable (PHAssetCreationRequest) -> Void) {
        let model = model
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in model.saveMessage = "Photos access was denied." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                configure(PHAssetCreationRequest.forAsset())
            } completionHandler: { success, error in
                Task { @MainActor in
                    model.saveMessage = success ? "Saved to Photos." : (error?.localizedDescription ?? "Couldn't save.")
                }
            }
        }
    }
}
