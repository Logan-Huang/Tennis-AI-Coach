//
//  ResultsView.swift
//  Tennis AI Coach
//
//  The Session Report: one scroll telling diagnose → see → act.
//  Hero score → video with skeleton → focus next → scored swings → findings
//  → session medians, with deep analytics (charts) pushed one level down.
//

import SwiftUI

struct ResultsView: View {
    let session: Session

    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var store

    @State private var playback: PlaybackModel
    @State private var showExport = false
    @State private var detailSelection: ShotSelection?

    @Namespace private var shotZoom

    private struct ShotSelection: Identifiable, Hashable {
        let index: Int
        var id: Int { index }
    }

    // Scores computed once at init — lazy, never persisted.
    private let shotScores: [ShotScore]
    private let sessionScore: SessionScore
    private let headline: String
    private let focus: Narrative.Focus?
    private let findings: [FindingCount]

    init(session: Session) {
        self.session = session
        let meta = session.result.meta
        _playback = State(initialValue: PlaybackModel(
            videoURL: session.videoURL,
            frames: session.result.frames,
            poses: session.result.poses,
            videoSize: CGSize(width: meta.width, height: meta.height),
            duration: meta.durationS,
            hittingArm: session.result.hittingArm))

        let shots = ShotScorer.score(result: session.result)
        let rollup = ShotScorer.sessionScore(shots)
        self.shotScores = shots
        self.sessionScore = rollup
        self.headline = Narrative.headline(session: rollup, shots: shots)
        self.focus = Narrative.focusNext(shots: shots)
        self.findings = Narrative.findingCounts(shots: shots)
    }

    private var result: AnalysisResult { session.result }

    /// Median of per-shot speed ratios for the medians section.
    private var relSpeedMedian: Double {
        NanStats.nanMedian(shotScores.compactMap { shot in
            shot.components.first { $0.kind == .swingSpeed }?.rawValue
        })
    }

    /// Debug hooks (Simulator UI verification — taps can't be injected there):
    /// `-reportScrollBottom` anchors the report scrolled to the end;
    /// `-autoOpenShotDetail` opens the first shot's breakdown on appear.
    private var debugScrollBottom: Bool {
        ProcessInfo.processInfo.arguments.contains("-reportScrollBottom")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    if result.isUsable {
                        SessionHeroCard(session: sessionScore, headline: headline)

                        videoCard
                            .id("video")

                        CoachingSection(focus: focus, findings: findings, report: result.coaching)

                        if !shotScores.isEmpty {
                            ShotListSection(
                                shots: shotScores,
                                strokes: result.strokes,
                                namespace: shotZoom,
                                onOpenDetail: { detailSelection = ShotSelection(index: $0) },
                                onSeek: { t in
                                    playback.seek(to: t)
                                    withAnimation(.smooth) { proxy.scrollTo("video", anchor: .top) }
                                })
                        }

                        MediansSection(result: result, relSpeedMedian: relSpeedMedian)

                        NavigationLink {
                            ChartsView(result: result, playback: playback, shotScores: shotScores)
                        } label: {
                            HStack {
                                Label("Explore metrics", systemImage: "chart.xyaxis.line")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .interactiveCardStyle()
                        }
                        .buttonStyle(CardButtonStyle())
                    } else {
                        TrackingFailedState(onShowVideo: {
                            withAnimation(.smooth) { proxy.scrollTo("video", anchor: .top) }
                        })
                        videoCard
                            .id("video")
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(debugScrollBottom ? .bottom : .top)
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-autoOpenShotDetail"),
               !shotScores.isEmpty {
                detailSelection = ShotSelection(index: 0)
            }
            if ProcessInfo.processInfo.arguments.contains("-autoOpenExport") {
                showExport = true
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Session Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sessionScore.overall.isFinite {
                ToolbarItem(placement: .topBarLeading) {
                    // Session score pill — always visible while reading the report.
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(sessionScore.band.color)
                            .frame(width: 8, height: 8)
                        Text(Fmt.score(sessionScore.overall))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Session score \(Fmt.score(sessionScore.overall)), \(sessionScore.band.label)")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share or export")
            }
            if let previous = previousSession {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.showCompare(beforeID: previous.id, afterID: session.id)
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .accessibilityLabel("Compare with previous session")
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(session: session)
        }
        .navigationDestination(item: $detailSelection) { selection in
            ShotDetailView(
                shots: shotScores,
                strokes: result.strokes,
                initialIndex: selection.index,
                onWatch: { stroke in
                    playback.seek(to: stroke.peakTime)
                })
            .navigationTransition(.zoom(sourceID: shotScores[selection.index].strokeId, in: shotZoom))
        }
        .onDisappear { playback.cleanup() }
    }

    private var videoCard: some View {
        VideoOverlayPlayerView(
            playback: playback,
            strokeTimes: result.strokes.map(\.peakTime),
            embedded: true)
    }

    /// The chronologically previous session, if any (sessions are newest-first).
    private var previousSession: Session? {
        store.sessions.first { $0.createdAt < session.createdAt }
    }
}
