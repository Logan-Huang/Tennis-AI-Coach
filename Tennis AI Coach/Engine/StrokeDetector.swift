//
//  StrokeDetector.swift
//  Tennis AI Coach
//
//  Wrist-speed peak detection and per-stroke aggregation (from the notebook's
//  cell 12). The amplitude gate is NOT the notebook's: it now scales off the
//  player's fastest swing, not the 95th-percentile speed (see `detect`), which
//  chronically over-counted strokes by admitting take-back/follow-through motion.
//  The two speed-statistic paths are deliberately asymmetric (hitting-arm drops
//  NaN; threshold zero-fills) — do not unify.
//

import Foundation

nonisolated enum StrokeDetector {

    /// pick_hitting_arm: the wrist with the higher 90th-percentile speed.
    static func pickHittingArm(frames: [FrameMetrics]) -> HittingArm {
        let l = frames.map(\.wristSpeedL).filter { $0.isFinite }
        let r = frames.map(\.wristSpeedR).filter { $0.isFinite }
        if l.isEmpty && r.isEmpty { return .right }
        let l90 = l.isEmpty ? -1 : NanStats.nanPercentile(l, 90)
        let r90 = r.isEmpty ? -1 : NanStats.nanPercentile(r, 90)
        return l90 > r90 ? .left : .right
    }

    /// Dependency-free 1-D local-maxima detector (notebook detect_peaks_1d).
    static func detectPeaks1d(_ y: [Double], thresh: Double, minGap: Int) -> [Int] {
        var peaks: [Int] = []
        guard y.count > 2 else { return peaks }
        let gap = max(1, minGap)
        for i in 1..<(y.count - 1) {
            guard y[i].isFinite else { continue }
            if y[i] > thresh && y[i] >= y[i - 1] && y[i] >= y[i + 1] {
                if let last = peaks.last {
                    if i - last >= gap {
                        peaks.append(i)
                    } else if y[i] > y[last] {
                        peaks[peaks.count - 1] = i   // keep the larger of two close peaks
                    }
                } else {
                    peaks.append(i)
                }
            }
        }
        return peaks
    }

    /// Width-3 median filter (endpoints pass through). Used only to pick the
    /// amplitude reference: it strips single-frame spikes so the bar reflects
    /// sustained swing speed, not a one-frame tracking glitch.
    static func medianFilter3(_ y: [Double]) -> [Double] {
        guard y.count >= 3 else { return y }
        var out = y
        for i in 1..<(y.count - 1) {
            let a = y[i - 1], b = y[i], c = y[i + 1]
            out[i] = max(min(a, b), min(max(a, b), c))   // median of three
        }
        return out
    }

    static func detect(frames: [FrameMetrics],
                       hittingArm: HittingArm,
                       fps: Double,
                       sampleStride: Int) -> [Stroke] {
        guard !frames.isEmpty else { return [] }

        let speedRaw = frames.map { $0.wristSpeed(for: hittingArm) }
        let speed = speedRaw.map { $0.isFinite ? $0 : 0.0 }   // nan_to_num(..., 0)

        let minGap = NanStats.pythonRound(0.45 * fps / Double(sampleStride))
        let win = NanStats.pythonRound(0.25 * fps / Double(sampleStride))

        // Amplitude gate. A real stroke's wrist peak is a large fraction of the
        // player's FASTEST swing. The old gate used 0.35 * p95, but swings are
        // sparse, so the 95th percentile sits inside ordinary take-back /
        // follow-through / reset motion — that motion cleared the bar and was
        // counted as extra strokes. Reference instead = the fastest *sustained*
        // wrist speed (max of a width-3 median filter, so a single-frame tracking
        // glitch can't set the bar), and a stroke must reach 45% of it. This is
        // scale-invariant (any resolution / fps); the 300 floor only keeps a
        // near-still clip from promoting noise.
        let reference = medianFilter3(speed).max() ?? 0.0
        let thresh = max(300.0, 0.45 * reference)

        let peaks = detectPeaks1d(speed, thresh: thresh, minGap: minGap)

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
