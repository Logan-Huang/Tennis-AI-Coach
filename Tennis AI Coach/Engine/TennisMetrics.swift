//
//  TennisMetrics.swift
//  Tennis AI Coach
//
//  Per-frame metric computation — the body of the notebook's cell 11 loop,
//  with the wrist-speed adjacency fix folded in — plus `WristTrackingGate`,
//  which throws away wrist positions Vision invented, before this file turns
//  them into speeds (see below).
//

import Foundation
import simd
import CoreGraphics

nonisolated struct MetricsComputer {
    private var prevLeftWrist: Pt?
    private var prevLeftWristIndex: Int = .min
    private var prevRightWrist: Pt?
    private var prevRightWristIndex: Int = .min

    /// Produce one FrameMetrics row from a frame's joints.
    /// - processedIndex: 0-based index among PROCESSED (stride-sampled) frames.
    /// - dt: seconds between processed frames = (1/fps) * stride.
    mutating func makeRow(joints: [BodyJoint: Pt],
                          processedIndex: Int,
                          rawFrameIndex: Int,
                          timeS: Double,
                          dt: Double,
                          config: AnalysisConfig) -> FrameMetrics {

        let lShoulder = joints[.leftShoulder],  rShoulder = joints[.rightShoulder]
        let lElbow = joints[.leftElbow],        rElbow = joints[.rightElbow]
        let lWrist = joints[.leftWrist],        rWrist = joints[.rightWrist]
        let lHip = joints[.leftHip],            rHip = joints[.rightHip]
        let lKnee = joints[.leftKnee],          rKnee = joints[.rightKnee]
        let lAnkle = joints[.leftAnkle],        rAnkle = joints[.rightAnkle]

        // Joint angles.
        let kneeL = Geometry.angleDeg(lHip, lKnee, lAnkle)
        let kneeR = Geometry.angleDeg(rHip, rKnee, rAnkle)
        let elbowL = Geometry.angleDeg(lShoulder, lElbow, lWrist)
        let elbowR = Geometry.angleDeg(rShoulder, rElbow, rWrist)

        // Torso lean (signed) from shoulder-center -> hip-center vector.
        var torsoLean = Double.nan
        if let sc = Geometry.midpoint(lShoulder, rShoulder),
           let hc = Geometry.midpoint(lHip, rHip) {
            torsoLean = Geometry.signedAngleFromVerticalDeg(sc - hc)
        }
        let torsoLeanAbs = torsoLean.isFinite ? abs(torsoLean) : .nan

        // Stance width ratio, with anatomical outlier guard.
        var stance = Double.nan
        if let la = lAnkle, let ra = rAnkle, let lh = lHip, let rh = rHip {
            let ankleDist = simd_length(ra - la)
            let hipDist = simd_length(rh - lh)
            let ratio = ankleDist / (hipDist + 1e-6)
            stance = ratio > config.stanceRejectAbove ? .nan : ratio
        }

        // Wrist speeds — only across genuinely adjacent valid processed frames.
        var leftSpeed = Double.nan
        if let lw = lWrist, let prev = prevLeftWrist, prevLeftWristIndex == processedIndex - 1 {
            leftSpeed = simd_length(lw - prev) / dt
        }
        if let lw = lWrist { prevLeftWrist = lw; prevLeftWristIndex = processedIndex }

        var rightSpeed = Double.nan
        if let rw = rWrist, let prev = prevRightWrist, prevRightWristIndex == processedIndex - 1 {
            rightSpeed = simd_length(rw - prev) / dt
        }
        if let rw = rWrist { prevRightWrist = rw; prevRightWristIndex = processedIndex }

        return FrameMetrics(
            frameIndex: rawFrameIndex, timeS: timeS,
            kneeL: kneeL, kneeR: kneeR, elbowL: elbowL, elbowR: elbowR,
            torsoLean: torsoLean, torsoLeanAbs: torsoLeanAbs,
            stanceRatio: stance, wristSpeedL: leftSpeed, wristSpeedR: rightSpeed)
    }
}

// MARK: - Wrist tracking gate

/// Throws away wrist joint *positions* that Vision cannot have seen, before any
/// speed is differenced from them.
///
/// Vision loses the wrist exactly when it matters: at contact the arm is
/// motion-blurred and often crossing the body, and the tracker responds by
/// parking the joint somewhere impossible for a frame — on the racquet head, on
/// the other arm, on the torso. One such position poisons *two* speeds, the one
/// into it and the one out of it, each larger than any real stroke. Both then
/// look like the hardest swing in the clip, and one of them usually lands on the
/// off arm, which is enough to flip `pickHittingArm` and put every reported
/// stroke on the wrong wrist. Dropping the position instead of the speeds is
/// what makes that impossible: an excluded joint is simply never differenced,
/// so neither bad speed is created and both wrists get honest statistics.
///
/// Three independent things give a bad position away, all dimensionless — ratios
/// against the player's own body or against the joint's own neighbours — so they
/// hold at any resolution, framing or frame rate:
///
/// * The forearm it implies is longer than that player's forearm ever is.
/// * The wrist leaves and comes back: it sits far from both neighbouring
///   samples while those two sit close to each other. Arms do not do this.
/// * The step into it dwarfs the steps around it. A real swing is a ramp — the
///   wrist accelerates over several samples and decelerates over several more
///   (measured spike ratios 0.5-1.9, against 2.5-52 for tracking failures).
///   This is the check `medianFilter3` used to be reaching for; the mistake was
///   applying it to the speed trace, where it lowers the amplitude reference
///   without removing the bogus peak from the signal being searched.
///
/// Real strokes survive all three by construction, and because they are ramps
/// rather than single samples, losing one sample of one would not lose the
/// stroke.
nonisolated enum WristTrackingGate {

    /// A forearm longer than this multiple of the player's own 95th-percentile
    /// forearm is not a forearm. Measured: real contact samples reach 1.12x
    /// (the arm is fully extended and closest to the camera there).
    private static let maxForearm = 1.25

    /// The wrist is treated as having left and returned when the shorter of the
    /// two steps around a sample exceeds this multiple of the distance between
    /// that sample's neighbours. Measured: real strokes 0.06-0.57, out-and-back
    /// tracking failures 1.31-6.71.
    private static let maxExcursion = 1.0

    /// A step this many times larger than the largest step beside it is not the
    /// arm accelerating. Measured: real strokes 0.5-1.9, failures 2.5-51.9.
    private static let maxSpike = 2.5

    /// ... but only for steps worth judging at all: shorter than this many torso
    /// lengths in one sampled interval and the wrist is just moving normally.
    private static let jumpTorsos = 0.30

    /// Returns `frames` (joint dictionaries, one per processed frame, in pixel
    /// space) with untrustworthy wrist positions removed.
    static func clean(_ frames: [[BodyJoint: Pt]]) -> [[BodyJoint: Pt]] {
        guard frames.count > 2 else { return frames }
        let torsoMed = NanStats.nanMedian(frames.map(torsoLength))
        guard torsoMed.isFinite, torsoMed > 0 else { return frames }

        var out = frames
        for (wrist, elbow) in [(BodyJoint.leftWrist, BodyJoint.leftElbow),
                               (BodyJoint.rightWrist, BodyJoint.rightElbow)] {
            let n = frames.count
            let forearm = frames.map { f -> Double in
                guard let w = f[wrist], let e = f[elbow] else { return .nan }
                return simd_length(w - e)
            }
            let forearmMax = maxForearm * NanStats.nanPercentile(forearm, 95)
            let step: [Double] = (0..<n).map { i in
                guard i > 0, let a = frames[i - 1][wrist], let b = frames[i][wrist] else { return .nan }
                return simd_length(b - a)
            }

            for i in 0..<n where frames[i][wrist] != nil {
                let torso = torsoLength(frames[i]).isFinite ? torsoLength(frames[i]) : torsoMed
                var bogus = forearm[i].isFinite && forearmMax.isFinite && forearm[i] > forearmMax

                if !bogus, i > 0, i + 1 < n,
                   let before = frames[i - 1][wrist], let after = frames[i + 1][wrist],
                   step[i].isFinite, step[i + 1].isFinite {
                    let neighbourSpan = simd_length(after - before)
                    bogus = min(step[i], step[i + 1]) > maxExcursion * neighbourSpan
                }

                if !bogus, step[i].isFinite, step[i] > jumpTorsos * torso {
                    let before = (i > 0 && step[i - 1].isFinite) ? step[i - 1] : 0.0
                    let after = (i + 1 < n && step[i + 1].isFinite) ? step[i + 1] : 0.0
                    let beside = max(before, after)
                    bogus = beside <= 0 || step[i] > maxSpike * beside
                }

                if bogus { out[i][wrist] = nil }
            }
        }
        return out
    }

    /// Shoulder-centre to hip-centre — the body-scale yardstick. NaN when the
    /// torso isn't tracked.
    private static func torsoLength(_ joints: [BodyJoint: Pt]) -> Double {
        guard let ls = joints[.leftShoulder], let rs = joints[.rightShoulder],
              let lh = joints[.leftHip], let rh = joints[.rightHip] else { return .nan }
        return simd_length((ls + rs) / 2 - (lh + rh) / 2)
    }
}

/// Build a normalized (top-left, [0,1]) PoseFrame for overlay/annotation drawing.
nonisolated func makePoseFrame(joints: [BodyJoint: Pt],
                               timeS: Double,
                               orientedSize: CGSize) -> PoseFrame {
    let w = Double(orientedSize.width)
    let h = Double(orientedSize.height)
    var points = [CGPoint?](repeating: nil, count: BodyJoint.allCases.count)
    if w > 0, h > 0 {
        for (joint, px) in joints {
            points[joint.rawValue] = CGPoint(x: px.x / w, y: px.y / h)
        }
    }
    return PoseFrame(timeS: timeS, points: points)
}
