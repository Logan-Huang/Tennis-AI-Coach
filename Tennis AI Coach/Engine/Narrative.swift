//
//  Narrative.swift
//  Tennis AI Coach
//
//  Turns scores into coach-voice copy. Voice rules: real sentences with real
//  numbers, one priority at a time, no exclamation marks, and honest framing —
//  "at contact" only when the contact was heard, "around your fastest wrist
//  moment" when it was estimated from the wrist. All thresholds come from
//  FormBands.
//
//  Coaching is per stroke where the strokes have kinds: a serve and a forehand
//  are not the same movement, and "bend your knees more" is only useful if it
//  says on which one.
//

import Foundation

nonisolated enum Narrative {

    // MARK: - Headline

    /// One-sentence session takeaway for the hero card.
    static func headline(session: SessionScore, shots: [ShotScore]) -> String {
        guard session.overall.isFinite else {
            return "Not enough tracking to grade this session — keep your whole body in frame and the camera steady."
        }
        let byKind = kindMedians(shots)
        if byKind.count >= 2, let best = byKind.first, let worst = byKind.last,
           best.median - worst.median >= 5 {
            return "Your \(best.kind.pluralName.lowercased()) led at \(Int(best.median.rounded())); \(worst.kind.pluralName.lowercased()) trailed at \(Int(worst.median.rounded())) — that's where the work is."
        }
        let strongest = medianStrongestFormComponent(shots)
        if let bestId = session.bestShotId, session.best.isFinite {
            let bestKind = shots.first { $0.strokeId == bestId }?.strokeKind
            let name = bestKind.map { "\($0.displayName) \(bestId)" } ?? "Swing \(bestId)"
            if let strongest {
                return "\(name) was your best at \(Int(session.best.rounded())) — \(strongest.displayName.lowercased()) was your steadiest strength."
            }
            return "\(name) was your best at \(Int(session.best.rounded()))."
        }
        return "Median form score \(Int(session.overall.rounded())) across \(session.gradedShots) graded swings."
    }

    // MARK: - Stroke mix

    struct KindSummary: Identifiable, Sendable {
        var kind: StrokeKind
        var count: Int          // all strokes of this kind
        var graded: Int
        var median: Double      // NaN when none graded
        var id: StrokeKind { kind }
    }

    /// Per-kind counts and median scores, in a fixed reading order. Empty for
    /// sessions from before strokes had kinds.
    static func strokeMix(_ shots: [ShotScore]) -> [KindSummary] {
        StrokeKind.allCases.compactMap { kind in
            let mine = shots.filter { $0.strokeKind == kind }
            guard !mine.isEmpty else { return nil }
            let graded = mine.filter(\.isGraded)
            return KindSummary(kind: kind, count: mine.count, graded: graded.count,
                               median: NanStats.nanMedian(graded.map(\.overall)))
        }
    }

    /// Kinds with at least two graded strokes, best median first.
    private static func kindMedians(_ shots: [ShotScore]) -> [(kind: StrokeKind, median: Double)] {
        strokeMix(shots)
            .filter { $0.graded >= 2 && $0.median.isFinite && $0.kind != .groundstroke }
            .map { ($0.kind, $0.median) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Focus next

    /// A weakest component scoring at least this is in range, not a fault.
    static let inRangeScore = 85.0
    static let prepFaultScore = 70.0

    /// Whether a raw median sits inside the target the focus pill would show.
    /// Scores ramp toward the edges of a band, so "lowest score" and "outside
    /// the target" are not the same thing, and only the second is a fault.
    static func isInRange(_ kind: ShotScoreComponent.Kind, raw: Double, stroke: StrokeKind?) -> Bool {
        guard raw.isFinite else { return false }
        switch kind {
        case .kneeBend: return FormBands.kneeIdeal.contains(raw)
        case .torsoStability: return raw <= FormBands.leanMax
        case .elbowExtension:
            return stroke == .serve ? FormBands.serveElbowIdeal.contains(raw) : FormBands.elbowIdeal.contains(raw)
        case .stanceWidth: return FormBands.stanceIdeal.contains(raw)
        case .reach: return raw >= FormBands.reachIdeal
        case .finish: return raw >= FormBands.finishIdeal
        case .prepFollowThrough, .swingSpeed: return false
        }
    }

    struct Focus {
        var kind: ShotScoreComponent.Kind
        var sentence: String        // one priority, coach voice
        var targetText: String      // "110–155°"
        var youText: String         // "162°"
        /// The stroke this is about, when it's about one.
        var strokeKind: StrokeKind? = nil
    }

    /// The single weakest form component — one priority, not ten. Swing speed
    /// is excluded (session-relative, not actionable form). When strokes have
    /// kinds it's the weakest component on any one kind of stroke, since a
    /// fault on every backhand is diluted to nothing by a session of good
    /// forehands.
    static func focusNext(shots: [ShotScore]) -> Focus? {
        let graded = shots.filter(\.isGraded)
        guard !graded.isEmpty else { return nil }

        let kinds = Set(graded.compactMap(\.strokeKind))
        // Every graded swing together, plus each kind of stroke there are at
        // least two of: one serve is an anecdote, not a pattern.
        var groups: [(StrokeKind?, [ShotScore])] = [(nil, graded)]
        for k in kinds {
            let mine = graded.filter { $0.strokeKind == k }
            if mine.count >= 2, mine.count < graded.count { groups.append((k, mine)) }
        }
        if kinds.count == 1, let only = kinds.first { groups[0].0 = only }

        struct Candidate {
            var stroke: StrokeKind?
            var kind: ShotScoreComponent.Kind
            var median: Double
            var raw: Double
            var heard: Bool
            var faulty: Bool
        }
        var candidates: [Candidate] = []
        for (stroke, group) in groups {
            let heard = group.filter { $0.timing == .heard }.count * 2 > group.count
            for kind in ShotScoreComponent.Kind.allCases where kind != .swingSpeed {
                let measured = group.compactMap { shot in
                    shot.components.first { $0.kind == kind && $0.score.isFinite }
                }
                guard measured.count >= min(2, group.count) else { continue }
                let med = NanStats.nanMedian(measured.map(\.score))
                guard med.isFinite else { continue }
                let raw = NanStats.nanMedian(measured.map(\.rawValue))
                // Prep has no band to be outside of; only call it a fault
                // when it's clearly rough (its score is the noisiest one).
                let faulty = kind == .prepFollowThrough
                    ? med < prepFaultScore
                    : !isInRange(kind, raw: raw, stroke: stroke)
                candidates.append(Candidate(stroke: stroke, kind: kind, median: med,
                                            raw: raw, heard: heard, faulty: faulty))
            }
        }
        // The worst actual fault; failing any, the part closest to one.
        let faults = candidates.filter(\.faulty)
        guard let w = (faults.isEmpty ? candidates : faults).min(by: { $0.median < $1.median }) else { return nil }
        var focus = focus(for: w.kind, rawMedian: w.raw, stroke: w.stroke, heard: w.heard)
        if faults.isEmpty {
            // Nothing is actually wrong. Say so, rather than dressing the
            // least-good part up as a problem.
            focus.sentence = "Every part of your form we could measure was in range — the closest to the edge was \(w.kind.displayName.lowercased()), at \(focus.youText)."
        }
        // Name the stroke only when there's more than one kind to tell apart.
        if !faults.isEmpty, let stroke = w.stroke, kinds.count > 1, stroke != .groundstroke,
           graded.contains(where: { $0.strokeKind != stroke }) {
            focus.sentence = "On your \(stroke.pluralName.lowercased()): " + lowercasedFirst(focus.sentence)
        }
        focus.strokeKind = w.stroke
        return focus
    }

    private static func focus(for kind: ShotScoreComponent.Kind, rawMedian raw: Double,
                              stroke: StrokeKind?, heard: Bool) -> Focus {
        let moment = heard ? "at contact" : "around your fastest wrist moment"
        switch kind {
        case .kneeBend:
            let you = raw.isFinite ? "\(Int(raw.rounded()))°" : "—"
            let target = "\(Int(FormBands.kneeIdeal.lowerBound))–\(Int(FormBands.kneeIdeal.upperBound))°"
            if stroke == .serve {
                let sentence = raw.isFinite && raw > FormBands.kneeIdeal.upperBound
                    ? "Your knees only bent to \(you) while loading — sit into your legs in the trophy position, then drive up into the ball."
                    : "Your knees bent to \(you) while loading — keep that load but stay balanced over your front foot."
                return Focus(kind: kind, sentence: sentence, targetText: target, youText: you)
            }
            let sentence = raw.isFinite && raw > FormBands.kneeIdeal.upperBound
                ? "Your knees averaged \(you) \(moment) — sink into a lower, athletic base."
                : "Knee bend averaged \(you) — keep the bend but stay stacked over your base."
            return Focus(kind: kind, sentence: sentence, targetText: target, youText: you)
        case .torsoStability:
            let you = raw.isFinite ? "\(Int(raw.rounded()))°" : "—"
            return Focus(kind: kind,
                         sentence: "Torso lean averaged \(you) through your swings — stay centered and rotate from the core.",
                         targetText: "under \(Int(FormBands.leanMax))°",
                         youText: you)
        case .elbowExtension:
            let you = raw.isFinite ? "\(Int(raw.rounded()))°" : "—"
            if stroke == .serve {
                return Focus(kind: kind,
                             sentence: "Your hitting elbow was \(you) \(moment) — reach up and strike with the arm close to straight.",
                             targetText: "\(Int(FormBands.serveElbowIdeal.lowerBound))°+",
                             youText: you)
            }
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
        case .reach:
            let you = raw.isFinite ? String(format: "%.1f×", raw) : "—"
            return Focus(kind: kind,
                         sentence: "At contact your hand was \(you) your torso length above your shoulders — toss a little higher and hit at full stretch.",
                         targetText: String(format: "%.1f×+", FormBands.reachIdeal),
                         youText: you)
        case .finish:
            return Focus(kind: kind,
                         sentence: "Your finish stopped around \(handHeight(raw)) — let the racquet carry on over your shoulder instead of stopping the swing.",
                         targetText: "over the shoulder",
                         youText: handHeight(raw))
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
        case .reach: return "Serve contact below full reach"
        case .finish: return "Finish stopping below the shoulder"
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

    private static func lowercasedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        // Leave "I" and acronyms alone; everything the focus sentences start
        // with is an ordinary capitalised word.
        return first.lowercased() + s.dropFirst()
    }
}

nonisolated extension Narrative {
    /// A hand height above the shoulders (torso lengths) in words. The number
    /// behind it is a 2D estimate; the words are as precise as it deserves.
    static func handHeight(_ x: Double) -> String {
        guard x.isFinite else { return "—" }
        if x >= 0.2 { return "above the shoulder" }
        if x >= -0.15 { return "shoulder height" }
        if x >= -0.55 { return "chest height" }
        return "waist height"
    }
}
