//
//  CompareEngine.swift
//  Tennis AI Coach
//
//  Before/after session comparison. Speed is EXCLUDED throughout — pixel
//  speeds don't survive a change of camera position, so only scale-invariant
//  form components cross the session boundary.
//

import Foundation

nonisolated enum CompareEngine {

    struct SideSummary: Sendable {
        let formScore: Double        // speed-excluded; NaN = ungraded
        let best: Double
        let average: Double
        let worst: Double
        let gradedShots: Int
        let totalShots: Int
    }

    struct ComponentPair: Identifiable, Sendable {
        let kind: ShotScoreComponent.Kind
        let beforeScore: Double      // median component score (0–100, NaN)
        let afterScore: Double
        let beforeRaw: Double        // median raw value
        let afterRaw: Double

        var id: ShotScoreComponent.Kind { kind }
        var delta: Double? {
            beforeScore.isFinite && afterScore.isFinite ? afterScore - beforeScore : nil
        }
    }

    struct FindingTransition: Identifiable, Sendable {
        let kind: ShotScoreComponent.Kind
        let text: String             // "Torso leaning past 22°"
        let beforeAffected: Int
        let beforeTotal: Int
        let afterAffected: Int
        let afterTotal: Int

        var id: ShotScoreComponent.Kind { kind }
        var improved: Bool {
            guard beforeTotal > 0, afterTotal > 0 else { return false }
            return Double(afterAffected) / Double(afterTotal) <
                   Double(beforeAffected) / Double(beforeTotal)
        }
    }

    struct CompareReport: Sendable {
        let before: SideSummary
        let after: SideSummary
        let components: [ComponentPair]
        let transitions: [FindingTransition]

        var formDelta: Double? {
            before.formScore.isFinite && after.formScore.isFinite
                ? after.formScore - before.formScore : nil
        }
    }

    // MARK: - Build

    static func report(before: [ShotScore], after: [ShotScore]) -> CompareReport {
        CompareReport(
            before: side(before),
            after: side(after),
            components: componentPairs(before: before, after: after),
            transitions: transitions(before: before, after: after))
    }

    private static func side(_ shots: [ShotScore]) -> SideSummary {
        let formScores = shots.map(ProgressEngine.formOnlyScore).filter(\.isFinite)
        return SideSummary(
            formScore: NanStats.nanMedian(formScores),
            best: formScores.max() ?? .nan,
            average: formScores.isEmpty ? .nan : formScores.reduce(0, +) / Double(formScores.count),
            worst: formScores.min() ?? .nan,
            gradedShots: shots.filter(\.isGraded).count,
            totalShots: shots.count)
    }

    private static func componentPairs(before: [ShotScore], after: [ShotScore]) -> [ComponentPair] {
        ShotScoreComponent.Kind.allCases
            .filter { $0 != .swingSpeed }
            .compactMap { kind in
                let b = medians(for: kind, in: before)
                let a = medians(for: kind, in: after)
                guard b.score.isFinite || a.score.isFinite else { return nil }
                return ComponentPair(kind: kind,
                                     beforeScore: b.score, afterScore: a.score,
                                     beforeRaw: b.raw, afterRaw: a.raw)
            }
    }

    private static func medians(for kind: ShotScoreComponent.Kind,
                                in shots: [ShotScore]) -> (score: Double, raw: Double) {
        let graded = shots.filter(\.isGraded)
        let scores = graded.compactMap { $0.components.first { $0.kind == kind }?.score }
        let raws = graded.compactMap { $0.components.first { $0.kind == kind }?.rawValue }
        return (NanStats.nanMedian(scores), NanStats.nanMedian(raws))
    }

    private static func transitions(before: [ShotScore], after: [ShotScore]) -> [FindingTransition] {
        let beforeCounts = Narrative.findingCounts(shots: before)
        let afterCounts = Narrative.findingCounts(shots: after)
        let beforeGraded = before.filter(\.isGraded).count
        let afterGraded = after.filter(\.isGraded).count

        // Union of kinds flagged on either side.
        var kinds: [ShotScoreComponent.Kind] = []
        for f in beforeCounts + afterCounts where !kinds.contains(f.kind) {
            kinds.append(f.kind)
        }

        return kinds.map { kind in
            let b = beforeCounts.first { $0.kind == kind }
            let a = afterCounts.first { $0.kind == kind }
            return FindingTransition(
                kind: kind,
                text: (b ?? a)!.text,
                beforeAffected: b?.affectedShots ?? 0,
                beforeTotal: b?.totalGradedShots ?? beforeGraded,
                afterAffected: a?.affectedShots ?? 0,
                afterTotal: a?.totalGradedShots ?? afterGraded)
        }
    }
}
