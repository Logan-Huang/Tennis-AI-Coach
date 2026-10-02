//
//  OverviewView.swift
//  Tennis AI Coach
//
//  Session medians, folded into the bottom of the Session Report: the median
//  of each graded part of the swing that matters most, tinted by how it
//  scored, in the units it's judged in.
//

import SwiftUI

struct MediansSection: View {
    let result: AnalysisResult
    let shots: [ShotScore]

    /// The parts shown, most telling first; the first four with data.
    private static let order: [ShotScoreComponent.Kind] = [
        .swingSpeed, .shoulderTurn, .kneeBend, .finish,
        .shoulderTilt, .reach, .kineticChain, .elbowExtension,
    ]

    private struct Tile: Identifiable {
        var kind: ShotScoreComponent.Kind
        var raw: Double
        var score: Double
        var id: ShotScoreComponent.Kind { kind }
    }

    private var tiles: [Tile] {
        let graded = shots.filter(\.isGraded)
        let all = Self.order.compactMap { kind -> Tile? in
            let measured = graded.compactMap { shot in
                shot.components.first { $0.kind == kind && $0.score.isFinite }
            }
            guard !measured.isEmpty else { return nil }
            return Tile(kind: kind,
                        raw: NanStats.nanMedian(measured.map(\.rawValue)),
                        score: NanStats.nanMedian(measured.map(\.score)))
        }
        return Array(all.prefix(4))
    }

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.m - 2),
                           GridItem(.flexible(), spacing: Theme.Spacing.m - 2)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "Session medians")

            if !tiles.isEmpty {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.m - 2) {
                    ForEach(tiles) { tile in
                        MetricCard(title: tile.kind.displayName,
                                   value: tile.kind == .swingSpeed
                                       ? Fmt.speed(tile.raw)
                                       : Fmt.component(tile.kind, tile.raw, compact: true),
                                   systemImage: Self.symbol(tile.kind),
                                   unit: tile.kind == .swingSpeed ? "torso lengths/s" : nil,
                                   tint: ScoreBand(score: tile.score).color)
                    }
                }
            }

            // Duration is context, not a stat worth a card.
            Text("Session length \(Fmt.seconds(result.summary.durationS)) · \(result.summary.framesProcessed) frames analyzed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func symbol(_ kind: ShotScoreComponent.Kind) -> String {
        switch kind {
        case .swingSpeed: return "speedometer"
        case .shoulderTurn: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .kneeBend: return "figure.cooldown"
        case .finish: return "arrow.up.forward"
        case .shoulderTilt: return "angle"
        case .reach: return "arrow.up.to.line"
        case .kineticChain: return "figure.tennis"
        case .elbowExtension: return "figure.tennis"
        case .torsoStability: return "figure.walk.motion"
        case .stanceWidth: return "arrow.left.and.right"
        }
    }
}
