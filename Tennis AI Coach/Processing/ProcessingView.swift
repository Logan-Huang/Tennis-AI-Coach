//
//  ProcessingView.swift
//  Tennis AI Coach
//
//  Runs the analysis off the main thread, shows progress, and on success
//  replaces the stack with the Results screen.
//

import SwiftUI
import UIKit

@Observable
@MainActor
final class ProcessingModel {
    var progress: Double = 0
    var failure: AnalysisError?
}

struct ProcessingView: View {
    let videoURL: URL

    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var store
    @Environment(\.analysisEngine) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var model = ProcessingModel()
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 28) {
            if let failure = model.failure {
                failureView(failure)
            } else {
                progressView
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Analyzing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task(id: attempt) { await runAnalysis() }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Theme.court.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: max(0.02, model.progress))
                    .stroke(Theme.court.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: model.progress)
                VStack(spacing: 4) {
                    Image(systemName: "figure.tennis")
                        .font(.title)
                        .foregroundStyle(Theme.court)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    Text("\(Int(model.progress * 100))%")
                        .font(.stat)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                }
            }
            .frame(width: 180, height: 180)

            VStack(spacing: 6) {
                Text(stageTitle)
                    .font(.headline)
                    .contentTransition(.opacity)
                    .animation(.smooth(duration: 0.3), value: stageTitle)
                Text("Everything runs on this phone — the video never leaves it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Cancel").frame(maxWidth: 200)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Progress-staged copy: the ring moves and the words move with it.
    private var stageTitle: String {
        switch model.progress {
        case ..<0.15: return "Reading your video…"
        case ..<0.80: return "Tracking body pose…"
        case ..<0.95: return "Measuring your form…"
        default: return "Writing up coaching…"
        }
    }

    // MARK: - Failure

    private func failureView(_ failure: AnalysisError) -> some View {
        VStack(spacing: 18) {
            ContentUnavailableView {
                Label("Couldn't analyze this clip", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(failure.errorDescription ?? "Something went wrong.")
            }
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Back").frame(maxWidth: .infinity)
                }
                .secondaryActionButton()

                Button {
                    attempt += 1
                } label: {
                    Text("Retry").frame(maxWidth: .infinity)
                }
                .primaryActionButton()
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Work

    private func runAnalysis() async {
        model.progress = 0
        model.failure = nil
        let model = model
        do {
            let result = try await engine.analyze(
                videoURL: videoURL,
                config: .default,
                progress: { p in
                    Task { @MainActor in model.progress = p }
                })
            let session = store.addSession(sourceVideoURL: videoURL, result: result)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            router.showResults(session.id)
        } catch is CancellationError {
            // View was dismissed; nothing to do.
        } catch let error as AnalysisError {
            if case .cancelled = error { return }
            model.failure = error
        } catch {
            model.failure = .decodeFailed(error.localizedDescription)
        }
    }
}
