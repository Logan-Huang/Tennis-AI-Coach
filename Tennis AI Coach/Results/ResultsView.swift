//
//  ResultsView.swift
//  Tennis AI Coach
//
//  Container for the five result sections. Owns the shared PlaybackModel.
//

import SwiftUI

enum ResultSection: String, CaseIterable, Identifiable {
    case overview, video, charts, strokes, coaching
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .video: return "Video"
        case .charts: return "Charts"
        case .strokes: return "Strokes"
        case .coaching: return "Coaching"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "rosette"
        case .video: return "play.rectangle"
        case .charts: return "chart.xyaxis.line"
        case .strokes: return "list.bullet.rectangle"
        case .coaching: return "checkmark.bubble"
        }
    }
}

struct ResultsView: View {
    let session: Session

    @State private var playback: PlaybackModel
    @State private var section: ResultSection = .overview
    @State private var showExport = false

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
    }

    private var result: AnalysisResult { session.result }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(ResultSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(session: session)
        }
        .onDisappear { playback.cleanup() }
    }

    @ViewBuilder
    private var content: some View {
        if !result.isUsable && section != .video {
            EmptyStateView(
                systemImage: "person.fill.questionmark",
                title: "Couldn't track a player",
                message: "No clear body pose was detected. Film side-on with your full body in frame and good lighting, then try again.")
        } else {
            switch section {
            case .overview:
                OverviewView(result: result)
            case .video:
                VideoOverlayPlayerView(playback: playback)
            case .charts:
                ChartsView(result: result, playback: playback)
            case .strokes:
                StrokeListView(result: result) { time in
                    playback.seek(to: time)
                    section = .video
                }
            case .coaching:
                CoachingView(report: result.coaching, summary: result.summary,
                             hittingArm: result.hittingArm)
            }
        }
    }
}
