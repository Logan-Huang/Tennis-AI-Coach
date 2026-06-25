//
//  TennisMetrics.swift
//  Tennis AI Coach
//
//  Per-frame metric computation — the body of the notebook's cell 11 loop,
//  with the wrist-speed adjacency fix folded in.
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
