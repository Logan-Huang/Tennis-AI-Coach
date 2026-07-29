//
//  ProgressEngine.swift
//  Tennis AI Coach
//
//  Cross-session aggregates for the Home dashboard.
//
//  The honesty rule that makes trends valid: the cross-session FormTrendScore
//  EXCLUDES the swing-speed component. Pixel speeds scale with resolution,
//  zoom, and camera distance, so they never cross a session boundary — form
//  angles are scale-invariant and do.
//

import Foundation

nonisolated enum ProgressEngine {

    /// One session's point on the Home trend line.
    struct SessionProgress: Identifiable, Sendable {
        let sessionId: UUID
        let date: Date
        /// Speed-excluded form score (median across graded shots); NaN = ungraded session.
        let formScore: Double
        let gradedShots: Int

        var id: UUID { sessionId }
    }

    /// A form component's recent range + latest value, for RangeBandRow.
    struct ComponentTrend: Identifiable, Sendable {
        let kind: ShotScoreComponent.Kind
        /// Fixed display domain for the track.
        let domain: ClosedRange<Double>
        /// Min–max of per-session medians across recent sessions (nil = <2 sessions).
        let range: ClosedRange<Double>?
        /// Latest session's median raw value (NaN = unmeasured).
        let current: Double

        var id: ShotScoreComponent.Kind { kind }
    }

    // MARK: - Form score (speed-excluded)

    /// Per-shot form-only score: surviving components minus swing speed,
    /// weights renormalized. NaN when the shot is ungraded.
    static func formOnlyScore(_ shot: ShotScore) -> Double {
        guard shot.isGraded else { return .nan }
        let surviving = shot.components.filter { $0.kind != .swingSpeed && $0.score.isFinite }
        let weightSum = surviving.reduce(0) { $0 + $1.weight }
        guard weightSum > 0, surviving.count >= 2 else { return .nan }
        return surviving.reduce(0) { $0 + $1.score * $1.weight } / weightSum
    }

    /// Session-level form trend score: median of per-shot form-only scores.
    static func formTrendScore(shots: [ShotScore]) -> Double {
        NanStats.nanMedian(shots.map(formOnlyScore))
    }

    // MARK: - Trend series

    /// Oldest-first trend points for the Home chart.
    static func trend(sessions: [(id: UUID, date: Date, shots: [ShotScore])]) -> [SessionProgress] {
        sessions
            .map { SessionProgress(sessionId: $0.id, date: $0.date,
                                   formScore: formTrendScore(shots: $0.shots),
                                   gradedShots: $0.shots.filter(\.isGraded).count) }
            .sorted { $0.date < $1.date }
    }

    /// Latest-vs-previous delta over sessions that actually graded.
    /// nil when there's no previous graded session to compare against.
    static func latestDelta(_ trend: [SessionProgress]) -> Double? {
        let graded = trend.filter { $0.formScore.isFinite }
        guard graded.count >= 2 else { return nil }
        return graded[graded.count - 1].formScore - graded[graded.count - 2].formScore
    }

    // MARK: - Component ranges

    private static let trackedKinds: [(ShotScoreComponent.Kind, ClosedRange<Double>)] = [
        (.kneeBend, 80...180),
        (.torsoStability, 0...45),
        (.elbowExtension, 50...180),
    ]

    /// Recent min–max band + latest value per form component (raw units).
    /// `sessions` oldest-first; uses up to the last `window` sessions.
    static func componentTrends(sessions: [(id: UUID, date: Date, shots: [ShotScore])],
                                window: Int = 10) -> [ComponentTrend] {
        let ordered = sessions.sorted { $0.date < $1.date }.suffix(window)

        return trackedKinds.map { kind, domain in
            // Per-session median raw value for this component.
            let medians: [Double] = ordered.map { session in
                NanStats.nanMedian(session.shots.compactMap { shot in
                    shot.components.first { $0.kind == kind }?.rawValue
                })
            }.filter { $0.isFinite }

            let current = medians.last ?? .nan
            var range: ClosedRange<Double>?
            if medians.count >= 2, let lo = medians.min(), let hi = medians.max(), lo < hi {
                range = lo...hi
            }
            return ComponentTrend(kind: kind, domain: domain, range: range, current: current)
        }
    }
}
