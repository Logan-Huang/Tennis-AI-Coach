//
//  ProgressEngine.swift
//  Tennis AI Coach
//
//  Cross-session aggregates for the Home dashboard.
//
//  What makes trends valid: every shot is graded against fixed standards, and
//  swing speed is the hand's speed relative to the player's own hips in torso
//  lengths, which doesn't change with resolution, zoom or camera distance. So a
//  shot's score crosses session boundaries as it is. (Sessions analysed before
//  speeds were body-relative get theirs from the saved skeleton.)
//

import Foundation

nonisolated enum ProgressEngine {

    /// One session's point on the Home trend line.
    struct SessionProgress: Identifiable, Sendable {
        let sessionId: UUID
        let date: Date
        /// Median shot score across graded shots; NaN = ungraded session.
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

    // MARK: - Form score

    /// Session-level trend score: the median graded shot score, the same
    /// number the session's own report leads with.
    static func formTrendScore(shots: [ShotScore]) -> Double {
        NanStats.nanMedian(shots.filter(\.isGraded).map(\.overall))
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
        (.swingSpeed, 0...30),
        (.shoulderTurn, 0...90),
        (.kneeBend, 90...180),
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
