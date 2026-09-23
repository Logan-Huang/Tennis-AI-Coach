//
//  StrokeDetector.swift
//  Tennis AI Coach
//
//  Finds the moments the player hit the ball, then measures each one.
//
//  Two sources of evidence, neither enough alone:
//
//  * The wrists (WristMotion): a swing is the one thing a player does that
//    moves a hand several torso lengths a second relative to their own hips.
//    That says a swing happened, and roughly when — but the take-back and the
//    follow-through are fast too, and on a player filmed from across the court
//    one of them can out-measure the swing itself.
//  * The soundtrack (AudioOnsets): ball on strings is a sharp, loud click that
//    fixes contact to a few hundredths of a second — but a bounce, the
//    hitting partner and the next court all click too.
//
//  So a sound is a stroke only when the player is mid-swing around it and
//  their hand is moving at the sound itself, and a fast wrist with no sound
//  near it (a clip with no audio, a quiet mis-hit, music over the top) is
//  still a stroke, timed from the wrist.
//
//  The sounds that fool it are the ball's two bounces either side of the
//  player's own hit: the incoming ball landing while they take the racquet
//  back, and their shot landing on the far side while they recover. Both are
//  within half a second of a real swing. Filmed from the far end, the second
//  one can be the loudest sound in the rally.
//
//  Measured against 33 hand-labelled contacts in seven clips (two players,
//  serves, forehands, one- and two-handed backhands, near and far camera):
//  the old detector found 5 of them and reported 15 swings that didn't happen;
//  this finds 32 with none. Wrist alone finds 24 with 6. Constants below were
//  chosen from the middle of the range where that result holds, not at its
//  edge; ranges are noted where they were measured. Re-measure any change with
//  Scripts/detection-eval.
//
//  Every threshold is in torso lengths per second (see WristMotion) or
//  seconds, so none of it depends on resolution, frame rate or how far away
//  the camera was.
//

import Foundation

nonisolated enum StrokeDetector {

    /// A wrist-only stroke needs a peak at least this fast. (6-7 hold the
    /// result above; 8 starts dropping real backhands, which are the slowest
    /// strokes and lose their wrists to the other hand.)
    static let swingSpeed = 7.0
    /// A sound is a hit when a wrist reaches this speed within `heardBefore`
    /// before it to `heardAfter` after it — there's a swing around it —
    static let heardSwingSpeed = 6.0
    static let heardBeforeS = 0.25
    static let heardAfterS = 0.25
    /// — and the hand is moving at least this fast within `heardAtS` of the
    /// sound itself. A racquet can't strike a ball while the hand holding it
    /// is still; a ball can bounce while the player waits for it or lands on
    /// the far side while they recover, and both happen within a quarter
    /// second of a swing. On the labelled clips every hit had the hand at
    /// 3.7 torso lengths/s or more at the sound, and every bounce but one
    /// (see `contacts`) at 3.2 or less; 3.0-4.0 give the same result.
    static let heardHandSpeed = 3.5
    static let heardAtS = 0.08
    /// One player cannot hit twice within this. A rally sends the ball across
    /// the court and back between two of their shots; the fastest exchange at
    /// the net still takes longer than this.
    static let separationS = 1.0
    /// A wrist peak this close to a heard hit is that hit's take-back or
    /// follow-through.
    static let sameSwingS = 0.9
    /// A wrist-only stroke is timed at the hitting wrist's fastest moment
    /// within this of the peak that found it.
    static let localizeS = 0.45
    /// Stroke measurements are taken over contact ± this.
    static let measureWindowS = 0.25
    /// "How fast was this swing" is the fastest wrist in this window.
    static let speedBeforeS = 0.15
    static let speedAfterS = 0.10

    /// Percentile at which the two wrists are compared to find the racquet arm.
    /// See `pickHittingArm`.
    private static let swingPercentile = 98.0

    /// Which wrist swings the racquet, for a player who hasn't said: the one
    /// whose speed distribution has the faster top end. Compared on image
    /// speeds over whatever frames each wrist survived, at the 98th
    /// percentile, where two Vision runs over the same clip agree; the 90th
    /// compares idling, not swinging. Only used without a profile's
    /// handedness — for a player filmed from across the court it is not much
    /// better than a coin: Vision can't reliably tell their wrists apart.
    static func pickHittingArm(leftSpeeds l: [Double], rightSpeeds r: [Double]) -> HittingArm {
        let l = l.filter(\.isFinite), r = r.filter(\.isFinite)
        if l.isEmpty && r.isEmpty { return .right }
        let lTop = l.isEmpty ? -1 : NanStats.nanPercentile(l, swingPercentile)
        let rTop = r.isEmpty ? -1 : NanStats.nanPercentile(r, swingPercentile)
        return lTop > rTop ? .left : .right
    }

    static func pickHittingArm(frames: [FrameMetrics]) -> HittingArm {
        pickHittingArm(leftSpeeds: frames.map(\.wristSpeedL), rightSpeeds: frames.map(\.wristSpeedR))
    }

    // MARK: - Contacts

    struct Contact: Equatable {
        /// Index into the processed frames.
        var index: Int
        var timing: ContactTiming
    }

    /// When the player hit the ball, in processed-frame indices.
    static func contacts(frames: [FrameMetrics],
                         hittingArm: HittingArm,
                         onsets: [AudioOnset]) -> [Contact] {
        let n = frames.count
        guard n > 2 else { return [] }
        let times = frames.map(\.timeS)
        let either = frames.map { NanStats.pairNanMax($0.wristSpeedL, $0.wristSpeedR) }
        let hitting = frames.map { $0.wristSpeed(for: hittingArm) }

        func indices(from a: Double, to b: Double) -> ClosedRange<Int>? {
            let lo = firstIndex(times, atOrAfter: a)
            let hi = lastIndex(times, atOrBefore: b)
            guard let lo, let hi, lo <= hi else { return nil }
            return lo...hi
        }
        func peak(_ x: [Double], in range: ClosedRange<Int>?) -> (index: Int, value: Double)? {
            guard let range else { return nil }
            var best: (Int, Double)?
            for i in range where x[i].isFinite && (best == nil || x[i] > best!.1) { best = (i, x[i]) }
            return best
        }

        // 1. Heard hits, loudest first; a quieter sound within `separationS`
        //    of an accepted one is its bounce or its echo. Loudest, not
        //    sharpest: the bounce of the incoming ball can start as sharply as
        //    the hit that follows it, but a racquet striking a ball is louder
        //    than the ball striking the court from the same distance. (A bounce
        //    much nearer the phone can still be louder — the hand-speed test
        //    is what rules that one out.)
        var heard: [Contact] = []
        for onset in onsets.sorted(by: { ($0.peak, $0.strength) > ($1.peak, $1.strength) }) {
            guard let swing = peak(either, in: indices(from: onset.timeS - heardBeforeS,
                                                       to: onset.timeS + heardAfterS)),
                  swing.value >= heardSwingSpeed,
                  let hand = peak(either, in: indices(from: onset.timeS - heardAtS,
                                                      to: onset.timeS + heardAtS)),
                  hand.value >= heardHandSpeed else { continue }
            guard let at = nearestIndex(times, to: onset.timeS) else { continue }
            if heard.contains(where: { abs(times[$0.index] - times[at]) < separationS }) { continue }
            heard.append(Contact(index: at, timing: .heard))
        }

        // 2. Wrist peaks, fastest first, one per `separationS`.
        var peaks: [Int] = []
        for i in 1..<(n - 1) where either[i].isFinite && either[i] >= swingSpeed
            && either[i] >= (either[i - 1].isFinite ? either[i - 1] : 0)
            && either[i] >= (either[i + 1].isFinite ? either[i + 1] : 0) {
            peaks.append(i)
        }
        peaks.sort { either[$0] > either[$1] }
        var kept: [Int] = []
        for p in peaks where !kept.contains(where: { abs(times[$0] - times[p]) < separationS }) {
            kept.append(p)
        }

        // 3. Peaks no sound explains: timed at the hitting wrist's own peak
        //    nearby (the peak that found them may be the other hand).
        var estimated: [Contact] = []
        for p in kept.sorted(by: { either[$0] > either[$1] }) {
            if heard.contains(where: { abs(times[$0.index] - times[p]) < sameSwingS }) { continue }
            let at = peak(hitting, in: indices(from: times[p] - localizeS, to: times[p] + localizeS))?.index ?? p
            if heard.contains(where: { abs(times[$0.index] - times[at]) < sameSwingS }) { continue }
            if estimated.contains(where: { abs(times[$0.index] - times[at]) < separationS }) { continue }
            estimated.append(Contact(index: at, timing: .estimated))
        }
        return (heard + estimated).sorted { $0.index < $1.index }
    }

    // MARK: - Strokes

    /// Contacts measured into strokes.
    static func detect(frames: [FrameMetrics],
                       hittingArm: HittingArm,
                       fps: Double,
                       sampleStride: Int,
                       onsets: [AudioOnset] = []) -> [Stroke] {
        guard !frames.isEmpty else { return [] }
        let samplesPerSecond = fps / Double(max(1, sampleStride))
        let win = NanStats.pythonRound(measureWindowS * samplesPerSecond)
        let before = NanStats.pythonRound(speedBeforeS * samplesPerSecond)
        let after = NanStats.pythonRound(speedAfterS * samplesPerSecond)
        let either = frames.map { NanStats.pairNanMax($0.wristSpeedL, $0.wristSpeedR) }

        return contacts(frames: frames, hittingArm: hittingArm, onsets: onsets)
            .enumerated().map { number, contact in
                let p = contact.index
                let seg = Array(frames[max(0, p - win)...min(frames.count - 1, p + win)])
                let kneeMinEach = NanStats.elementwiseNanMin(seg.map(\.kneeL), seg.map(\.kneeR))
                let speeds = Array(either[max(0, p - before)...min(frames.count - 1, p + after)])
                var stroke = Stroke(
                    id: number + 1,
                    peakTime: frames[p].timeS,
                    peakFrame: frames[p].frameIndex,
                    hittingArm: hittingArm,
                    peakSpeed: NanStats.nanMax(speeds),
                    minKnee: NanStats.nanMin(kneeMinEach),
                    stanceMed: NanStats.nanMedian(seg.map(\.stanceRatio)),
                    leanAbsMed: NanStats.nanMedian(seg.map(\.torsoLeanAbs)),
                    elbowMed: NanStats.nanMedian(seg.map { $0.elbow(for: hittingArm) }))
                stroke.timing = contact.timing
                return stroke
            }
    }

    // MARK: - Index helpers (times ascending)

    private static func firstIndex(_ t: [Double], atOrAfter x: Double) -> Int? {
        var lo = 0, hi = t.count
        while lo < hi { let m = (lo + hi) / 2; if t[m] < x { lo = m + 1 } else { hi = m } }
        return lo < t.count ? lo : nil
    }

    private static func lastIndex(_ t: [Double], atOrBefore x: Double) -> Int? {
        guard let first = firstIndex(t, atOrAfter: x) else { return t.isEmpty ? nil : t.count - 1 }
        if t[first] == x { return first }
        return first > 0 ? first - 1 : nil
    }

    private static func nearestIndex(_ t: [Double], to x: Double) -> Int? {
        guard !t.isEmpty else { return nil }
        guard let i = firstIndex(t, atOrAfter: x) else { return t.count - 1 }
        if i == 0 { return 0 }
        return abs(t[i] - x) < abs(t[i - 1] - x) ? i : i - 1
    }
}
