//
//  Narrative.swift
//  Tennis AI Coach
//
//  Turns scores into coach-voice copy. Voice rules: real sentences with real
//  numbers, one priority at a time, no exclamation marks, and honest framing —
//  "around your fastest wrist moment", never "at contact" (there is no ball
//  detection). All thresholds come from FormBands.
//

import Foundation

nonisolated enum Narrative {

    // MARK: - Headline

    /// One-sentence session takeaway for the hero card.
    static func headline(session: SessionScore, shots: [ShotScore]) -> String {
        guard session.overall.isFinite else {
            return "Not enough tracking to grade this session — film side-on with your full body in frame."
        }
        let strongest = medianStrongestFormComponent(shots)
        if let bestId = session.bestShotId, session.best.isFinite {
            if let strongest {
                return "Swing \(bestId) was your best at \(Int(session.best.rounded())) — \(strongest.displayName.lowercased()) was your steadiest strength."
            }
            return "Swing \(bestId) was your best at \(Int(session.best.rounded()))."
        }
        return "Median form score \(Int(session.overall.rounded())) across \(session.gradedShots) graded swings."
    }

    // MARK: - Focus next

    struct Focus {
        var kind: ShotScoreComponent.Kind
        var sentence: String        // one priority, coach voice
        var targetText: String      // "110–155°"
        var youText: String         // "162°"
    }

    /// The single weakest form component across graded shots — one priority,
    /// not ten. Swing speed is excluded (session-relative, not actionable form).
    static func focusNext(shots: [ShotScore]) -> Focus? {
        let graded = shots.filter(\.isGraded)
        guard !graded.isEmpty else { return nil }

        var weakest: (kind: ShotScoreComponent.Kind, median: Double, rawMedian: Double)?
        for kind in ShotScoreComponent.Kind.allCases where kind != .swingSpeed {
            let scores = graded.compactMap { shot in
                shot.components.first { $0.kind == kind }?.score
            }
            let raws = graded.compactMap { shot in
                shot.components.first { $0.kind == kind }?.rawValue
            }
            let med = NanStats.nanMedian(scores)
            guard med.isFinite else { continue }
            if weakest == nil || med < weakest!.median {
                weakest = (kind, med, NanStats.nanMedian(raws))
            }
        }
        guard let w = weakest else { return nil }
        return focus(for: w.kind, rawMedian: w.rawMedian)
    }

    private static func focus(for kind: ShotScoreComponent.Kind, rawMedian raw: Double) -> Focus {
        switch kind {
        case .kneeBend:
            let you = raw.isFinite ? "\(Int(raw.rounded()))°" : "—"
            let sentence = raw.isFinite && raw > FormBands.kneeIdeal.upperBound
                ? "Your knees averaged \(you) around your fastest wrist moment — sink into a lower, athletic base."
                : "Knee bend averaged \(you) — keep the bend but stay stacked over your base."
            return Focus(kind: kind, sentence: sentence,
                         targetText: "\(Int(FormBands.kneeIdeal.lowerBound))–\(Int(FormBands.kneeIdeal.upperBound))°",
                         youText: you)
        case .torsoStability:
            let you = raw.isFinite ? "\(Int(raw.rounded()))°" : "—"
            return Focus(kind: kind,
                         sentence: "Torso lean averaged \(you) through your swings — stay centered and rotate from the core.",
                         targetText: "under \(Int(FormBands.leanMax))°",
                         youText: you)
        case .elbowExtension:
            let you = raw.isFinite ? "\(Int(raw.rounded()))°" : "—"
            let sentence = raw.isFinite && raw < FormBands.elbowIdeal.lowerBound
                ? "Hitting-arm elbow averaged \(you) — create space and extend through the swing."
                : "Hitting-arm elbow averaged \(you) — keep a relaxed arm rather than locking it out."
            return Focus(kind: kind, sentence: sentence,
                         targetText: "\(Int(FormBands.elbowIdeal.lowerBound))–\(Int(FormBands.elbowIdeal.upperBound))°",
                         youText: you)
        case .stanceWidth:
            let you = raw.isFinite ? String(format: "%.2f", raw) : "—"
            let sentence = raw.isFinite && raw < FormBands.stanceIdeal.lowerBound
                ? "Your base measured \(you)× hip width — a slightly wider stance adds balance and power."
                : "Your base measured \(you)× hip width — a more compact width keeps you mobile between shots."
            return Focus(kind: kind, sentence: sentence,
                         targetText: String(format: "%.2f–%.1f", FormBands.stanceIdeal.lowerBound, FormBands.stanceIdeal.upperBound),
                         youText: you)
        case .prepFollowThrough:
            return Focus(kind: kind,
                         sentence: "Your load into the swing is stop-start — build one smooth acceleration into your fastest moment.",
                         targetText: "smooth rise",
                         youText: raw.isFinite ? "\(Int((raw * 100).rounded()))% smooth" : "—")
        case .swingSpeed:
            // Excluded by caller; safe fallback.
            return Focus(kind: kind,
                         sentence: "Commit to full swings — several were well below your fastest of the session.",
                         targetText: "near your best",
                         youText: "—")
        }
    }

    // MARK: - Findings (flaw frequency)

    /// Per-component "outside the band on N of M swings" counts, worst first.
    /// A shot counts as affected when that component scored in the workOn band.
    static func findingCounts(shots: [ShotScore]) -> [FindingCount] {
        let graded = shots.filter(\.isGraded)
        guard !graded.isEmpty else { return [] }

        var findings: [FindingCount] = []
        for kind in ShotScoreComponent.Kind.allCases where kind != .swingSpeed {
            var affected = 0
            var measured = 0
            for shot in graded {
                guard let c = shot.components.first(where: { $0.kind == kind }),
                      c.score.isFinite else { continue }
                measured += 1
                if c.score < 55 { affected += 1 }
            }
            guard measured > 0, affected > 0 else { continue }
            findings.append(FindingCount(
                kind: kind,
                affectedShots: affected,
                totalGradedShots: measured,
                text: findingText(kind: kind, affected: affected, total: measured)))
        }
        return findings.sorted {
            Double($0.affectedShots) / Double($0.totalGradedShots) >
            Double($1.affectedShots) / Double($1.totalGradedShots)
        }
    }

    private static func findingText(kind: ShotScoreComponent.Kind, affected: Int, total: Int) -> String {
        switch kind {
        case .kneeBend: return "Knee bend outside the \(Int(FormBands.kneeIdeal.lowerBound))–\(Int(FormBands.kneeIdeal.upperBound))° band"
        case .torsoStability: return "Torso leaning past \(Int(FormBands.leanMax))°"
        case .elbowExtension: return "Hitting-arm elbow outside its band"
        case .stanceWidth: return "Base too narrow or too wide"
        case .prepFollowThrough: return "Stop-start preparation into the swing"
        case .swingSpeed: return "Well below your fastest swing"
        }
    }

    // MARK: - Helpers

    /// The form component with the highest median score across graded shots.
    private static func medianStrongestFormComponent(_ shots: [ShotScore]) -> ShotScoreComponent.Kind? {
        let graded = shots.filter(\.isGraded)
        guard !graded.isEmpty else { return nil }
        var best: (kind: ShotScoreComponent.Kind, median: Double)?
        for kind in ShotScoreComponent.Kind.allCases where kind != .swingSpeed {
            let med = NanStats.nanMedian(graded.compactMap { shot in
                shot.components.first { $0.kind == kind }?.score
            })
            guard med.isFinite else { continue }
            if best == nil || med > best!.median { best = (kind, med) }
        }
        return best?.kind
    }
}
