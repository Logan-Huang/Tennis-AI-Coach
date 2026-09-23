//
//  StrokeAnatomy.swift
//  Tennis AI Coach
//
//  What kind of shot each stroke was, and the stroke-specific measurements
//  that coaching a serve and coaching a forehand need.
//
//  Everything here is read from where the hands are relative to the body at
//  and around contact, in torso lengths, and it leans on the vertical, which a
//  level camera preserves from any side: a hand above the head is above the
//  head whether the player is filmed from behind, in front or side-on.
//
//  Measured on 30 hand-labelled strokes (two players, far and near camera):
//
//  * Serves put a hand 0.9-1.3 torso lengths above the shoulders at contact;
//    no groundstroke got past 0.4.
//  * Two-handed backhands hold the wrists within 0.12-0.36 torso lengths of
//    each other at contact; forehands and serves never came closer than 0.85.
//  * Otherwise the side of the body the racquet wrist is on at contact decides
//    it: every labelled forehand was on the racquet-hand side of the hips,
//    every backhand on the other. That relies on Vision naming the player's
//    left and right correctly, so it only decides when the wrist is clearly
//    to one side; in between, the stroke stays a `.groundstroke`.
//

import Foundation
import simd

nonisolated enum StrokeAnatomy {

    /// A hand this far above the shoulders (torso lengths) at contact is
    /// overhead — a serve, or a smash, which is coached the same way.
    static let overheadReach = 0.6
    /// Wrists closer than this at contact are both on the racquet.
    static let twoHandedGap = 0.5
    /// The racquet wrist this far to its own side of the hips at contact is a
    /// forehand; this far to the other side, a backhand.
    static let sideMargin = 0.1
    /// Contact window for the hand positions: the frame of contact is the one
    /// the wrist is most blurred in, so look either side of it.
    static let contactBeforeS = 0.12
    static let contactAfterS = 0.05
    /// A groundstroke's finish is the highest the hands get in this long after contact.
    static let finishS = 0.5
    /// A serve's leg drive is loaded in this span before contact (the trophy
    /// position to the start of the upward drive).
    static let loadFromS = 0.8
    static let loadToS = 0.15

    static func annotate(_ strokes: inout [Stroke],
                         frames: [FrameMetrics],
                         joints: [[BodyJoint: Pt]],
                         torso: [Double],
                         hittingArm: HittingArm) {
        guard frames.count == joints.count, torso.count == joints.count, !frames.isEmpty else { return }
        let times = frames.map(\.timeS)
        var indexByFrame: [Int: Int] = [:]
        for (i, f) in frames.enumerated() { indexByFrame[f.frameIndex] = i }

        // Per-frame hand geometry, in torso lengths (NaN = not visible).
        let up = WristMotion.median(joints.indices.map { handHeight(joints[$0], torso[$0]) }, halfWindow: 1)
        let gap = joints.indices.map { wristGap(joints[$0], torso[$0]) }
        let side = joints.indices.map { racquetSide(joints[$0], torso[$0], hittingArm) }

        let knees = frames.map(\.kneeMin)
        let elbows = frames.map { $0.elbow(for: hittingArm) }

        func values(_ x: [Double], from a: Double, to b: Double) -> [Double] {
            zip(times, x).filter { $0.0 >= a && $0.0 <= b }.map(\.1)
        }

        for k in strokes.indices {
            guard let p = indexByFrame[strokes[k].peakFrame] else { continue }
            let t = times[p]
            var reach = NanStats.nanMax(values(up, from: t - contactBeforeS, to: t + contactAfterS))
            if !reach.isFinite {
                // Contact itself untracked (motion blur, a stretched body):
                // the frames either side still show where the hand was going.
                reach = NanStats.nanMax(values(up, from: t - 2 * contactBeforeS, to: t + 3 * contactAfterS))
            }
            let gapAt = NanStats.nanMedian(values(gap, from: t - contactBeforeS, to: t + contactAfterS))
            let sideAt = NanStats.nanMedian(values(side, from: t - contactBeforeS, to: t + contactAfterS))

            let kind: StrokeKind
            if reach.isFinite, reach >= overheadReach {
                kind = .serve
            } else if gapAt.isFinite, gapAt < twoHandedGap {
                kind = .backhand
            } else if sideAt.isFinite, sideAt > sideMargin {
                kind = .forehand
            } else if sideAt.isFinite, sideAt < -sideMargin {
                kind = .backhand
            } else {
                kind = .groundstroke
            }
            strokes[k].kind = kind
            strokes[k].reach = reach
            strokes[k].finish = NanStats.nanMax(values(up, from: t, to: t + finishS))
            strokes[k].loadKnee = NanStats.nanMin(values(knees, from: t - loadFromS, to: t - loadToS))
            strokes[k].contactElbow = NanStats.nanMax(values(elbows, from: t - contactBeforeS, to: t + contactAfterS))
        }
    }

    // MARK: - Geometry (pixel space, y down)

    /// The higher hand's height above the shoulder centre, torso lengths.
    /// Whichever hand is higher: at a serve's contact and a groundstroke's
    /// finish that's the racquet hand (or both, on a two-hander), and not
    /// having to know which wrist is which keeps it immune to Vision swapping
    /// their labels.
    /// Both shoulders, never one: a serve tilts the shoulder line by a third
    /// of a torso length, so either shoulder alone moves the reference by as
    /// much as the difference between a serve and a high forehand.
    static func handHeight(_ j: [BodyJoint: Pt], _ torso: Double) -> Double {
        guard torso.isFinite, torso > 0,
              let ls = j[.leftShoulder], let rs = j[.rightShoulder] else { return .nan }
        let shoulderY = (ls.y + rs.y) / 2
        let heights = [j[.leftWrist], j[.rightWrist]].compactMap { $0 }.map { (shoulderY - $0.y) / torso }
        return heights.max() ?? .nan
    }

    /// Distance between the wrists, torso lengths.
    static func wristGap(_ j: [BodyJoint: Pt], _ torso: Double) -> Double {
        guard torso.isFinite, torso > 0, let l = j[.leftWrist], let r = j[.rightWrist] else { return .nan }
        return simd_length(l - r) / torso
    }

    /// How far the racquet wrist is toward the racquet-hand side of the hips,
    /// along the shoulder line, in torso lengths. Positive: forehand side.
    static func racquetSide(_ j: [BodyJoint: Pt], _ torso: Double, _ arm: HittingArm) -> Double {
        let (own, off, wrist): (BodyJoint, BodyJoint, BodyJoint) = arm == .right
            ? (.rightShoulder, .leftShoulder, .rightWrist)
            : (.leftShoulder, .rightShoulder, .leftWrist)
        guard torso.isFinite, torso > 0,
              let s1 = j[own], let s0 = j[off], let w = j[wrist],
              let lh = j[.leftHip], let rh = j[.rightHip] else { return .nan }
        let axis = s1 - s0
        let length = simd_length(axis)
        guard length > 1e-6 else { return .nan }
        return simd_dot(w - (lh + rh) / 2, axis / length) / torso
    }
}
