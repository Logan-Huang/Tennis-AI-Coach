//
//  WristMotion.swift
//  Tennis AI Coach
//
//  How fast each wrist moves relative to the player's own body, in torso
//  lengths per second.
//
//  The speed used to be pixels per second between neighbouring frames, which
//  measured three things at once: the swing, the player running, and the
//  camera. On a handheld clip the camera alone produced "swings"; on a player
//  filmed from across the court one pixel of jitter was a fast wrist, and a
//  player four times closer to the lens swung four times faster. Three
//  changes, each with one job:
//
//  * Positions are taken relative to the hip centre and divided by the
//    player's torso length. Running and panning move the hips too, so they
//    cancel; the torso length makes the result the same at any distance,
//    resolution or zoom.
//  * Each coordinate is median-filtered over ~0.07 s before anything else. A
//    median leaves any monotonic run of samples exactly as it was — which is
//    what a swing is — and deletes a one- or two-frame excursion, which is what
//    a tracking failure is.
//  * What remains is lightly smoothed and differenced across two frames
//    rather than one, so the speed is a property of the motion, not of one
//    frame's error.
//
//  Measured on the hand-labelled sample clips, the swing peaks this produces
//  sit at 7-38 torso lengths per second at every framing, where the old pixel
//  speeds ranged over an order of magnitude with the camera distance.
//

import Foundation
import simd

nonisolated enum WristMotion {

    /// Half-width of the median filter.
    static let medianHalfWindowS = 0.07
    /// Standard deviation of the Gaussian smoothing that follows it.
    static let smoothingSigmaS = 0.05
    /// Half-width of the rolling median that gives the torso length. Long
    /// enough to ride out a crouch or a missing hip; short enough to follow a
    /// player walking toward the camera.
    static let scaleHalfWindowS = 0.5

    struct Result {
        /// Speed of each wrist, torso lengths per second (NaN = not measured).
        var left: [Double]
        var right: [Double]
        /// Rolling torso length in pixels per frame (NaN = unknown).
        var torso: [Double]
    }

    static func speeds(joints: [[BodyJoint: Pt]], times: [Double]) -> Result {
        let n = joints.count
        let empty = [Double](repeating: .nan, count: n)
        guard n > 2, times.count == n else { return Result(left: empty, right: empty, torso: empty) }
        let steps = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0 }
        let dt = NanStats.nanMedian(steps)
        guard dt.isFinite, dt > 0 else { return Result(left: empty, right: empty, torso: empty) }
        let samplesPerSecond = 1 / dt

        let torso = rollingMedian(joints.map(torsoLength),
                                  halfWindow: Int((scaleHalfWindowS * samplesPerSecond).rounded()))
        let anchors = hipAnchors(joints)

        let medianK = max(1, Int((medianHalfWindowS * samplesPerSecond).rounded()))
        let sigma = smoothingSigmaS * samplesPerSecond

        func speed(of wrist: BodyJoint) -> [Double] {
            var x = empty, y = empty
            for i in 0..<n {
                guard let w = joints[i][wrist], let a = anchors[i],
                      torso[i].isFinite, torso[i] > 0 else { continue }
                x[i] = (w.x - a.x) / torso[i]
                y[i] = (w.y - a.y) / torso[i]
            }
            x = gaussian(median(x, halfWindow: medianK), sigma: sigma)
            y = gaussian(median(y, halfWindow: medianK), sigma: sigma)
            var v = empty
            for i in 1..<(n - 1) {
                let a = i - 1, b = i + 1
                guard x[a].isFinite, y[a].isFinite, x[b].isFinite, y[b].isFinite else { continue }
                let span = times[b] - times[a]
                guard span > 0 else { continue }
                v[i] = hypot(x[b] - x[a], y[b] - y[a]) / span
            }
            return v
        }
        return Result(left: speed(of: .leftWrist), right: speed(of: .rightWrist), torso: torso)
    }

    // MARK: - Body frame

    /// Shoulder centre to hip centre, pixels. NaN when the torso isn't tracked.
    static func torsoLength(_ j: [BodyJoint: Pt]) -> Double {
        guard let ls = j[.leftShoulder], let rs = j[.rightShoulder],
              let lh = j[.leftHip], let rh = j[.rightHip] else { return .nan }
        return simd_length((ls + rs) / 2 - (lh + rh) / 2)
    }

    /// The hip centre, or — where the hips weren't found — the shoulder centre
    /// moved by the clip's typical shoulder-to-hip offset. Switching anchors
    /// without that offset would move every wrist by a torso length in one
    /// frame, which is the fastest "swing" there could ever be.
    private static func hipAnchors(_ joints: [[BodyJoint: Pt]]) -> [Pt?] {
        var dx: [Double] = [], dy: [Double] = []
        for j in joints {
            guard let ls = j[.leftShoulder], let rs = j[.rightShoulder],
                  let lh = j[.leftHip], let rh = j[.rightHip] else { continue }
            let d = (lh + rh) / 2 - (ls + rs) / 2
            dx.append(d.x); dy.append(d.y)
        }
        let offset = dx.isEmpty ? nil : Pt(NanStats.nanMedian(dx), NanStats.nanMedian(dy))
        return joints.map { j in
            if let lh = j[.leftHip], let rh = j[.rightHip] { return (lh + rh) / 2 }
            if let ls = j[.leftShoulder], let rs = j[.rightShoulder], let offset {
                return (ls + rs) / 2 + offset
            }
            return nil
        }
    }

    // MARK: - Filters (NaN = missing; missing stays missing)

    static func rollingMedian(_ x: [Double], halfWindow k: Int) -> [Double] {
        let n = x.count
        return (0..<n).map { i in
            NanStats.nanMedian(Array(x[max(0, i - k)...min(n - 1, i + k)]))
        }
    }

    static func median(_ x: [Double], halfWindow k: Int) -> [Double] {
        let n = x.count
        return (0..<n).map { i in
            guard x[i].isFinite else { return .nan }
            return NanStats.nanMedian(Array(x[max(0, i - k)...min(n - 1, i + k)]))
        }
    }

    static func gaussian(_ x: [Double], sigma: Double) -> [Double] {
        guard sigma > 0 else { return x }
        let r = Int((3 * sigma).rounded(.up))
        let kernel = (-r...r).map { exp(-0.5 * pow(Double($0) / sigma, 2)) }
        let n = x.count
        return (0..<n).map { i in
            guard x[i].isFinite else { return .nan }
            var sum = 0.0, weight = 0.0
            for o in -r...r {
                let j = i + o
                guard j >= 0, j < n, x[j].isFinite else { continue }
                sum += x[j] * kernel[o + r]
                weight += kernel[o + r]
            }
            return weight > 0 ? sum / weight : .nan
        }
    }
}
