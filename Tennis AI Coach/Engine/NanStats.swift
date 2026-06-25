//
//  NanStats.swift
//  Tennis AI Coach
//
//  NaN-aware reductions that match numpy semantics exactly. This is the
//  single highest transcription-risk spot in the port — every notebook
//  reduction (nanmin / nanmedian / nan(percentile)) routes through here.
//

import Foundation

nonisolated enum NanStats {

    /// np.nanmin over a 1-D array. All-NaN / empty -> NaN (no crash).
    static func nanMin(_ xs: [Double]) -> Double {
        let finite = xs.filter { $0.isFinite }
        return finite.min() ?? .nan
    }

    /// NaN-aware min of exactly two scalars (used per-frame for knee_min).
    static func pairNanMin(_ a: Double, _ b: Double) -> Double {
        switch (a.isFinite, b.isFinite) {
        case (true, true):  return Swift.min(a, b)
        case (true, false): return a
        case (false, true): return b
        case (false, false): return .nan
        }
    }

    /// np.nanmin(vstack([a, b]), axis=0): elementwise NaN-aware min of two
    /// equal-length arrays (mismatched lengths are zipped to the shorter).
    static func elementwiseNanMin(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map { pairNanMin($0, $1) }
    }

    /// np.nanmedian: drop NaN, then median (mean of the two middle values for
    /// even counts). Empty / all-NaN -> NaN.
    static func nanMedian(_ xs: [Double]) -> Double {
        let s = xs.filter { $0.isFinite }.sorted()
        guard !s.isEmpty else { return .nan }
        let n = s.count
        if n % 2 == 1 { return s[n / 2] }
        return (s[n / 2 - 1] + s[n / 2]) / 2.0
    }

    /// np.nanpercentile(xs, q): drop NaN, then linear-interpolation percentile.
    /// Empty / all-NaN -> NaN.
    static func nanPercentile(_ xs: [Double], _ q: Double) -> Double {
        let s = xs.filter { $0.isFinite }.sorted()
        return percentileSorted(s, q)
    }

    /// np.percentile(xs, q) with linear interpolation, NaN-unaware. The caller
    /// is expected to have pre-substituted NaN (e.g. nan_to_num -> 0). Empty -> NaN.
    static func percentile(_ xs: [Double], _ q: Double) -> Double {
        percentileSorted(xs.sorted(), q)
    }

    /// numpy's default ("linear") percentile interpolation on a sorted array.
    private static func percentileSorted(_ s: [Double], _ q: Double) -> Double {
        guard !s.isEmpty else { return .nan }
        let n = s.count
        if n == 1 { return s[0] }
        let rank = (q / 100.0) * Double(n - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        if lo == hi { return s[lo] }
        let frac = rank - Double(lo)
        return s[lo] + (s[hi] - s[lo]) * frac
    }

    /// Python's `round()` (banker's rounding, half-to-even) returning an Int.
    /// Used for min_gap / win frame counts so they match the notebook.
    static func pythonRound(_ x: Double) -> Int {
        Int(x.rounded(.toNearestOrEven))
    }
}
