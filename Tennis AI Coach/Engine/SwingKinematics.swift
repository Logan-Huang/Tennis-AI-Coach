//
//  SwingKinematics.swift
//  Tennis AI Coach
//
//  What the body did in each swing, read from the saved skeleton: how far the
//  shoulders turned, how far the hips sank before contact and rose through
//  it, how much of the hand's speed came from the trunk, and how fast the
//  racquet hand moved.
//
//  These are the things that separate a tennis player from someone swinging a
//  racquet for the first time. A first-timer's swing is the arm alone: the
//  body faces the net, the legs stay straight and the trunk barely moves, and
//  no amount of arm speed changes that. Everything the old score measured was
//  the absence of a fault (an elbow not too bent, a torso not leaning), and a
//  stiff, upright, arm-only swing has none of those faults.
//
//  Everything is measured relative to the player's own body in torso lengths,
//  and only along directions a level camera keeps, so it holds at any
//  distance and from behind, in front or side-on:
//
//  * Shoulder turn: how far the shoulders rotate from the end of the
//    backswing into the follow-through. Turning about the vertical axis
//    changes how wide the shoulders look and nothing else, so the shoulder
//    line's angle to the picture is arccos(apparent width / full width). That
//    angle folds at square-on and side-on: a turn that sweeps through square
//    (most forehands do, around contact) runs back up the same scale, so the
//    rotation is the path the angle travels, not its range. Two things keep
//    jitter out of that path. Reversals are found on the width itself, where
//    tracking noise is the same size at every angle, and only one bigger than
//    `reversalWidth` counts; near square-on, a few pixels of width are tens of
//    degrees, and a still player filmed square-on would otherwise read as
//    turning 35-45°. With it, a still player reads 0° (17° at worst).
//    The full width is the widest the shoulders appear in the clip, but never
//    less than `shoulderWidthFloor`. A player who never faces the camera
//    squarely would otherwise be measured against their own half-turn.
//  * Hip drop and leg drive. The hips' height above the ankles, against the
//    player's standing height in the clip. Vertical survives every camera
//    angle, which a 2D knee angle doesn't: filmed from behind, the knee bends
//    toward the lens and reads anything from straight to impossibly deep.
//  * Trunk share. The racquet shoulder's peak speed as a fraction of the
//    racquet wrist's, both relative to the hips. A swing driven by the trunk
//    moves the shoulder; an arm swing leaves it where it was.
//  * Shoulder tilt (serves). How far the racquet shoulder drops below the
//    other before contact: the trophy position's tilted shoulder line.
//
//  Positions are filtered the way WristMotion filters the wrist (median, then
//  Gaussian), so one frame's tracking error can't become a measurement.
//

import Foundation
import simd

nonisolated struct SwingKinematics: Sendable {
    /// Racquet wrist's peak speed relative to the hips, torso lengths/s.
    var handSpeed: Double = .nan
    /// Degrees the shoulders rotated from the end of the backswing into the follow-through.
    var shoulderTurn: Double = .nan
    /// Fraction of standing hip height the hips sank before contact.
    var hipDrop: Double = .nan
    /// Fraction of standing hip height regained from that low point through contact.
    var legDrive: Double = .nan
    /// The knee angle that hip drop implies, degrees (180 = straight).
    var kneeEstimate: Double = .nan
    /// Racquet shoulder's peak speed over the racquet wrist's.
    var trunkShare: Double = .nan
    /// Seconds the shoulder's peak came before the wrist's (negative: after).
    var shoulderLead: Double = .nan
    /// Most the racquet shoulder dropped below the other before contact, degrees.
    var shoulderTilt: Double = .nan

    /// Vision's shoulder points, squarely facing the camera, sit about this
    /// many torso lengths apart (0.58 measured on IMG_7145).
    static let shoulderWidthFloor = 0.55

    /// A change of direction in the shoulders' apparent width smaller than
    /// this (fraction of full width) is tracking noise, not a turn reversing.
    static let reversalWidth = 0.15

    // Windows around contact, seconds.
    /// The turn is measured from the start of the forward swing, which is
    /// where the racquet hand is slowest before contact, less this much (the
    /// trunk starts uncoiling before the arm), to this long after contact.
    static let swingStartSearch = (-0.9, -0.15)
    static let trunkLeadS = 0.1
    static let turnEndS = 0.3
    static let defaultSwingStartS = -0.5
    static let chainWindow = (-0.45, 0.15)
    static let speedWindow = (-0.25, 0.1)
    static let loadWindow = (-0.9, -0.05)
    static let driveWindow = (-0.1, 0.3)
    static let tiltWindow = (-0.9, -0.1)
    /// Standing height: the hips are this high or lower in 90% of the clip.
    static let standingPercentile = 90.0

    /// Measurements for each stroke, by stroke id. Empty when the clip has
    /// no usable skeleton.
    static func measure(_ result: AnalysisResult) -> [Int: SwingKinematics] {
        let poses = result.poses
        let n = poses.count
        let w = result.meta.width, h = result.meta.height
        guard n > 4, w > 0, h > 0, !result.strokes.isEmpty else { return [:] }

        let times = poses.map(\.timeS)
        let steps = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0 }
        let dt = NanStats.nanMedian(steps)
        guard dt.isFinite, dt > 0 else { return [:] }
        let samplesPerSecond = 1 / dt

        // Smoothed pixel coordinates, per joint.
        let k = max(1, Int((WristMotion.medianHalfWindowS * samplesPerSecond).rounded()))
        let sigma = WristMotion.smoothingSigmaS * samplesPerSecond
        var xs: [[Double]] = [], ys: [[Double]] = []
        for joint in BodyJoint.allCases {
            var x = [Double](repeating: .nan, count: n)
            var y = [Double](repeating: .nan, count: n)
            for i in 0..<n {
                guard let p = poses[i].point(joint) else { continue }
                x[i] = Double(p.x) * w
                y[i] = Double(p.y) * h
            }
            xs.append(WristMotion.gaussian(WristMotion.median(x, halfWindow: k), sigma: sigma))
            ys.append(WristMotion.gaussian(WristMotion.median(y, halfWindow: k), sigma: sigma))
        }
        func point(_ j: BodyJoint, _ i: Int) -> Pt? {
            let x = xs[j.rawValue][i], y = ys[j.rawValue][i]
            return x.isFinite && y.isFinite ? Pt(x, y) : nil
        }
        func centre(_ a: BodyJoint, _ b: BodyJoint, _ i: Int) -> Pt? {
            guard let p = point(a, i), let q = point(b, i) else { return nil }
            return (p + q) / 2
        }

        let hips = (0..<n).map { centre(.leftHip, .rightHip, $0) }
        let shoulders = (0..<n).map { centre(.leftShoulder, .rightShoulder, $0) }
        let torso = WristMotion.rollingMedian((0..<n).map { i -> Double in
            guard let s = shoulders[i], let p = hips[i] else { return .nan }
            return simd_length(s - p)
        }, halfWindow: Int((WristMotion.scaleHalfWindowS * samplesPerSecond).rounded()))

        // Shoulders' apparent width as a fraction of their full width.
        let width = (0..<n).map { i -> Double in
            guard let l = point(.leftShoulder, i), let r = point(.rightShoulder, i),
                  torso[i].isFinite, torso[i] > 0 else { return .nan }
            return abs(l.x - r.x) / torso[i]
        }
        let fullWidth = max(NanStats.nanPercentile(width, 95), shoulderWidthFloor)
        let squareness = width.map { min(1, $0 / fullWidth) }

        // Hips' height above the ankles, torso lengths.
        let hipHeight = (0..<n).map { i -> Double in
            guard let p = hips[i], torso[i].isFinite, torso[i] > 0 else { return .nan }
            let ankles = [point(.leftAnkle, i), point(.rightAnkle, i)].compactMap { $0 }
            guard !ankles.isEmpty else { return .nan }
            let ankleY = ankles.map(\.y).reduce(0, +) / Double(ankles.count)
            return (ankleY - p.y) / torso[i]
        }
        let standing = NanStats.nanPercentile(hipHeight, standingPercentile)

        // Speed of a joint relative to the hips, torso lengths/s.
        func speed(of joint: BodyJoint) -> [Double] {
            let rel = (0..<n).map { i -> Pt? in
                guard let p = point(joint, i), let c = hips[i], torso[i].isFinite, torso[i] > 0 else { return nil }
                return (p - c) / torso[i]
            }
            return (0..<n).map { i in
                guard i > 0, i < n - 1, let a = rel[i - 1], let b = rel[i + 1] else { return .nan }
                let span = times[i + 1] - times[i - 1]
                return span > 0 ? simd_length(b - a) / span : .nan
            }
        }
        let arm = result.hittingArm
        let (racquetShoulder, offShoulder, racquetWrist): (BodyJoint, BodyJoint, BodyJoint) = arm == .right
            ? (.rightShoulder, .leftShoulder, .rightWrist)
            : (.leftShoulder, .rightShoulder, .leftWrist)
        let shoulderSpeed = speed(of: racquetShoulder)
        let wristSpeed = speed(of: racquetWrist)

        // The shoulder line's tilt toward the racquet side, degrees.
        let tilt = (0..<n).map { i -> Double in
            guard let r = point(racquetShoulder, i), let o = point(offShoulder, i),
                  torso[i].isFinite, torso[i] > 0 else { return .nan }
            let drop = (r.y - o.y) / torso[i] / shoulderWidthFloor
            return asin(min(1, max(-1, drop))) * 180 / .pi
        }

        var out: [Int: SwingKinematics] = [:]
        for stroke in result.strokes {
            let t = stroke.peakTime
            func window(_ span: (Double, Double)) -> [Int] {
                (0..<n).filter { times[$0] >= t + span.0 && times[$0] <= t + span.1 }
            }
            func values(_ x: [Double], _ span: (Double, Double)) -> [Double] {
                window(span).map { x[$0] }
            }
            /// Time and value of the largest sample in the window.
            func peak(_ x: [Double], _ span: (Double, Double)) -> (time: Double, value: Double) {
                let best = window(span).filter { x[$0].isFinite }.max { x[$0] < x[$1] }
                return best.map { (times[$0], x[$0]) } ?? (.nan, .nan)
            }

            var m = SwingKinematics()
            m.handSpeed = NanStats.nanMax(values(wristSpeed, speedWindow))

            let slowest = window(swingStartSearch).filter { wristSpeed[$0].isFinite }
                .min { wristSpeed[$0] < wristSpeed[$1] }
            let start = slowest.map { times[$0] - trunkLeadS - t } ?? defaultSwingStartS
            m.shoulderTurn = rotation(values(squareness, (start, turnEndS)))

            let shoulderPeak = peak(shoulderSpeed, chainWindow)
            let wristPeak = peak(wristSpeed, chainWindow)
            if wristPeak.value.isFinite, wristPeak.value > 0 {
                m.trunkShare = shoulderPeak.value / wristPeak.value
                m.shoulderLead = wristPeak.time - shoulderPeak.time
            }

            if standing.isFinite, standing > 0 {
                let low = NanStats.nanMin(values(hipHeight, loadWindow))
                m.hipDrop = max(0, (standing - low) / standing)
                m.legDrive = max(0, (NanStats.nanMax(values(hipHeight, driveWindow)) - low) / standing)
                if m.hipDrop.isFinite {
                    // A bent leg holds the hips at (1 - cos κ) / 2 of their
                    // standing height, so the drop f gives cos κ = 2f - 1.
                    m.kneeEstimate = acos(min(1, max(-1, 2 * m.hipDrop - 1))) * 180 / .pi
                }
            }
            m.shoulderTilt = NanStats.nanMax(values(tilt, tiltWindow))
            out[stroke.id] = m
        }
        return out
    }

    /// Degrees the shoulder line travelled, from its apparent width as a
    /// fraction of full width (1 = square to the camera, 0 = side-on).
    /// Reversals are found on the width, then the turning points are
    /// converted to angles and the path between them summed.
    static func rotation(_ squareness: [Double]) -> Double {
        let x = squareness.filter(\.isFinite)
        guard x.count >= 2 else { return .nan }
        var turningPoints = [x[0]]
        var extreme = x[0]
        var direction = 0.0
        for y in x.dropFirst() {
            if direction == 0 {
                if abs(y - x[0]) > reversalWidth { direction = y > x[0] ? 1 : -1; extreme = y }
            } else if (y - extreme) * direction > 0 {
                extreme = y
            } else if abs(y - extreme) > reversalWidth {
                turningPoints.append(extreme)
                extreme = y
                direction = -direction
            }
        }
        turningPoints.append(extreme)
        let angles = turningPoints.map { acos(min(1, max(0, $0))) * 180 / .pi }
        return zip(angles.dropFirst(), angles).reduce(0) { $0 + abs($1.0 - $1.1) }
    }
}
