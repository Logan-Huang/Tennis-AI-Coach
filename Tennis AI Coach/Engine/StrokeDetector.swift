//
//  StrokeDetector.swift
//  Tennis AI Coach
//
//  Wrist-speed peak detection and per-stroke aggregation (from the notebook's
//  cell 12). Two things here are not the notebook's, both because the notebook's
//  versions were measured to disagree with themselves across two Vision runs of
//  one video: which arm holds the racquet (`pickHittingArm`) and how high a
//  wrist peak has to be (the 0.35 * p95 gate, which sat inside ordinary
//  take-back and reset motion and counted it as extra strokes). A stroke now has
//  to reach a large fraction of the clip's fastest swing, stand clear of how
//  fast the player's arm moves the rest of the time, and be separated from the
//  previous stroke by min_gap and by a return toward rest (hysteresis).
//
//  This file assumes the speed trace it is handed is already free of tracking
//  failures — `WristTrackingGate` (TennisMetrics.swift) drops the joint
//  positions that cause them, upstream of the differencing. It cannot do that
//  job from speeds and must not try: one bad position produces two bad speeds,
//  by which point the evidence that told them apart (where the joint was, how
//  long that made the forearm) is gone. `swingReference` here only guards
//  against a gross survivor.
//
//  Every constant below is a ratio between speeds measured in the same clip or a
//  duration in seconds, so the detector is invariant to resolution, fps and
//  sample stride. The one exception is the absolute floor in `detect`.
//
//  The two speed-statistic paths are deliberately asymmetric (hitting-arm drops
//  NaN; threshold zero-fills) — do not unify.
//

import Foundation

nonisolated enum StrokeDetector {

    /// Percentile at which the two wrists are compared to find the racquet arm.
    /// See `pickHittingArm`.
    private static let swingPercentile = 98.0

    /// Fraction of the clip's fastest swing a wrist peak must reach to count.
    /// Once the speeds are honest this is not a delicate number: on both runs of
    /// the ground-truth clip anything from 0.40 to 0.80 returns exactly the
    /// three real contacts, so this sits in the middle of that range and leans
    /// low, because the cost of being too high is a missed stroke and the cost
    /// of being slightly low is caught by the gates below.
    private static let peakFraction = 0.55

    /// A stroke also has to be this many times the clip's median wrist speed.
    /// This is the scale-invariant version of the absolute floor below: on a
    /// clip with no stroke in it, `peakFraction * reference` is just a fraction
    /// of the noise and would promote the loudest noise to a stroke. It is
    /// deliberately low enough to stay out of the way on real clips, because on
    /// a clip trimmed to a couple of seconds around one stroke the median itself
    /// is swing motion: at 6x, four real single-stroke windows out of eight
    /// dropped to zero strokes.
    private static let quietMultiple = 4.0

    /// How far the fastest sample may tower over the rest of the clip before it
    /// is read as mis-tracking rather than as a swing. Across a whole session
    /// the fastest swing runs 1.0-1.5x the next event; even a clip trimmed down
    /// to a single stroke only reaches 3.8x, because the take-back, the
    /// follow-through and the player's footwork are all still in frame. A wrist
    /// that jumps to a bystander or across the court is unbounded. 5.0 sits
    /// clear of the measured swing ratios; the price is that a mis-track of the
    /// same order as a real swing (a wrist swapped with the other arm, say)
    /// cannot be told apart from a hard swing here and still sets the reference.
    private static let spikeRatio = 5.0

    /// Hysteresis reset level, as a fraction of the amplitude gate: the wrist
    /// has to fall back through this before another stroke can register.
    private static let resetFraction = 0.5

    /// Beyond this separation two maxima are always separate strokes, whatever
    /// the wrist did in between. No single swing holds the wrist above the reset
    /// level for a second, and rallies do legitimately put strokes close
    /// together, so hysteresis must not be allowed to swallow one.
    private static let mergeWindowS = 1.0

    /// Which wrist swings the racquet: the one whose speed distribution has the
    /// faster top end.
    ///
    /// The notebook compared 90th percentiles, and that is measurably not a
    /// stroke test. Nine samples in ten are the player walking, resetting and
    /// bouncing the ball, and during a one-handed forehand the off arm sweeps
    /// out for balance nearly as fast, so the 90th percentile compares idling,
    /// not swinging: on two Vision runs over the SAME clip it answered "left" by
    /// 11% and "right" by 4%. The top of the distribution is where the strokes
    /// actually are — at the 98th percentile the same two runs agree, "right" by
    /// 25% and 37%. Percentile rather than maximum so one surviving outlier on
    /// either wrist cannot decide it.
    /// Compared over whatever frames each wrist survived, deliberately.
    /// Pairing the samples — comparing only frames where both wrists were
    /// measured — is the more principled comparison and does pick the racquet
    /// arm more often. It was tried and reverted: on a clip where Vision loses
    /// the hitting wrist through a swing, naming that arm correctly means
    /// reporting the swing not at all, whereas following the arm that was
    /// actually tracked still finds it. Losing a swing is worse than naming the
    /// wrong wrist, because nothing in the report reveals it.
    static func pickHittingArm(frames: [FrameMetrics]) -> HittingArm {
        let l = frames.map(\.wristSpeedL).filter { $0.isFinite }
        let r = frames.map(\.wristSpeedR).filter { $0.isFinite }
        if l.isEmpty && r.isEmpty { return .right }
        let lTop = l.isEmpty ? -1 : NanStats.nanPercentile(l, swingPercentile)
        let rTop = r.isEmpty ? -1 : NanStats.nanPercentile(r, swingPercentile)
        return lTop > rTop ? .left : .right
    }

    /// The clip's fastest swing: the largest wrist speed that some other moment
    /// in the clip corroborates.
    ///
    /// The maximum is taken as-is unless it towers `spikeRatio`x over the
    /// fastest *other* event — anything at least `minGap` away, so a swing's own
    /// neighbouring samples can never corroborate it — in which case the runner
    /// up is used and the spike itself is refused as a stroke (`detect` passes
    /// `spikeRatio * reference` as the ceiling; note that only ever bites once
    /// the maximum has been demoted, since nothing can exceed `spikeRatio` times
    /// the maximum). This is a backstop for a tracking failure that got past
    /// `WristTrackingGate`, not the primary defence: one such sample would
    /// otherwise lift the gate above every real swing and silently drop a whole
    /// session.
    static func swingReference(_ y: [Double], minGap: Int) -> Double {
        guard let top = y.max(), top > 0 else { return 0.0 }
        let topIdx = y.firstIndex(of: top) ?? 0
        var runnerUp = 0.0
        for (i, v) in y.enumerated() where abs(i - topIdx) >= minGap {
            runnerUp = Swift.max(runnerUp, v)
        }
        // No second event at all (a very short clip, or one tracked instant):
        // there is nothing to compare against, so trust the maximum.
        guard runnerUp > 0 else { return top }
        return top > spikeRatio * runnerUp ? runnerUp : top
    }

    /// Dependency-free 1-D local-maxima detector (notebook detect_peaks_1d) with
    /// a Schmitt trigger on top: once a peak is accepted the signal has to fall
    /// back below `reset` before the next one can be, so the take-back and the
    /// contact of a single swing — or the contact and the follow-through — can't
    /// both register, because the wrist never stops in between. Maxima closer
    /// than `minGap` collapse to the faster of the two unconditionally, and
    /// maxima more than `mergeGap` apart are always separate strokes. Samples
    /// above `ceiling` are mis-tracking rather than swings and are ignored.
    /// `tracked` marks the samples Vision actually measured. The speeds handed
    /// in are zero-filled, so a frame where the wrist was lost is indistinguishable
    /// from one where the wrist held still — and "held still" is exactly the
    /// evidence the hysteresis needs to call the next peak a separate swing.
    /// A gap in the data is not evidence the arm stopped, so untracked samples
    /// neither lower the valley nor support a peak.
    static func detectPeaks1d(_ y: [Double],
                              tracked: [Bool],
                              thresh: Double,
                              reset: Double,
                              ceiling: Double,
                              minGap: Int,
                              mergeGap: Int) -> [Int] {
        var peaks: [Int] = []
        guard y.count > 2 else { return peaks }
        let gap = max(1, minGap)
        let isTracked = { (i: Int) in i < tracked.count ? tracked[i] : true }
        var valley = Double.infinity   // lowest *measured* speed since the last peak
        for i in 1..<(y.count - 1) {
            guard y[i].isFinite, isTracked(i) else { continue }
            // A peak needs at least one real neighbour: between two dropouts,
            // the zero-fill makes any surviving sample a local maximum.
            let hasNeighbour = isTracked(i - 1) || isTracked(i + 1)
            let isMax = y[i] > thresh && y[i] <= ceiling && hasNeighbour
                && y[i] >= y[i - 1] && y[i] >= y[i + 1]
            guard isMax else {
                valley = Swift.min(valley, y[i])
                continue
            }
            guard let last = peaks.last else {
                peaks.append(i)
                valley = .infinity
                continue
            }
            if i - last >= gap && (valley < reset || i - last >= mergeGap) {
                peaks.append(i)                   // separate swing
                valley = .infinity
            } else if y[i] > y[last] {
                peaks[peaks.count - 1] = i        // keep the larger of two close peaks
                valley = .infinity
            } else {
                valley = Swift.min(valley, y[i])
            }
        }
        return peaks
    }

    static func detect(frames: [FrameMetrics],
                       hittingArm: HittingArm,
                       fps: Double,
                       sampleStride: Int) -> [Stroke] {
        guard !frames.isEmpty else { return [] }

        let speedRaw = frames.map { $0.wristSpeed(for: hittingArm) }
        let speed = speedRaw.map { $0.isFinite ? $0 : 0.0 }   // nan_to_num(..., 0)
        let tracked = speedRaw.map(\.isFinite)

        let samplesPerSecond = fps / Double(sampleStride)
        let minGap = NanStats.pythonRound(0.45 * samplesPerSecond)
        let mergeGap = NanStats.pythonRound(mergeWindowS * samplesPerSecond)
        let win = NanStats.pythonRound(0.25 * samplesPerSecond)

        // Amplitude gate: a real stroke's wrist peak is a large fraction of the
        // player's fastest swing *and* far above how fast the player's wrist
        // moves the rest of the time. Both terms are ratios within this clip, so
        // they carry across resolutions and frame rates. The absolute floor does
        // not — `detect` never sees the frame geometry, so px/s is the only unit
        // available for a last-ditch guard on a clip with no motion in it at
        // all. It is inert wherever a real swing exists: at 240p and up, half of
        // a swing peak is already well past 300 px/s.
        let reference = swingReference(speed, minGap: minGap)
        let ordinary = NanStats.percentile(speed, 50)
        let thresh = max(300.0, peakFraction * reference, quietMultiple * ordinary)

        let peaks = detectPeaks1d(speed,
                                  tracked: tracked,
                                  thresh: thresh,
                                  reset: resetFraction * thresh,
                                  ceiling: spikeRatio * reference,
                                  minGap: minGap,
                                  mergeGap: mergeGap)

        var strokes: [Stroke] = []
        for (i, p) in peaks.enumerated() {
            let a = max(0, p - win)
            let b = min(frames.count - 1, p + win)
            let seg = Array(frames[a...b])

            let kneeMinEach = NanStats.elementwiseNanMin(seg.map(\.kneeL), seg.map(\.kneeR))
            let minKnee = NanStats.nanMin(kneeMinEach)
            let stanceMed = NanStats.nanMedian(seg.map(\.stanceRatio))
            let leanAbsMed = NanStats.nanMedian(seg.map(\.torsoLeanAbs))
            let elbowMed = NanStats.nanMedian(seg.map { $0.elbow(for: hittingArm) })

            strokes.append(Stroke(
                id: i + 1,
                peakTime: frames[p].timeS,
                peakFrame: frames[p].frameIndex,
                hittingArm: hittingArm,
                peakSpeed: speed[p],
                minKnee: minKnee,
                stanceMed: stanceMed,
                leanAbsMed: leanAbsMed,
                elbowMed: elbowMed))
        }
        return strokes
    }
}
