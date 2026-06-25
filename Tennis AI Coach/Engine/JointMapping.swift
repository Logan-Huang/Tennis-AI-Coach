//
//  JointMapping.swift
//  Tennis AI Coach
//
//  Maps our internal BodyJoint enum to Apple Vision joint names, and defines
//  the skeleton edges used for overlay/annotation drawing.
//

import Vision

nonisolated enum JointMapping {

    /// BodyJoint -> Vision joint name. Vision's labels are subject-anatomical
    /// (same as MediaPipe), so left/right only ever affects the coaching label,
    /// never metric correctness.
    static let visionJoint: [BodyJoint: VNHumanBodyPoseObservation.JointName] = [
        .leftShoulder:  .leftShoulder,
        .rightShoulder: .rightShoulder,
        .leftElbow:     .leftElbow,
        .rightElbow:    .rightElbow,
        .leftWrist:     .leftWrist,
        .rightWrist:    .rightWrist,
        .leftHip:       .leftHip,
        .rightHip:      .rightHip,
        .leftKnee:      .leftKnee,
        .rightKnee:     .rightKnee,
        .leftAnkle:     .leftAnkle,
        .rightAnkle:    .rightAnkle,
    ]

    /// Skeleton bones (joint pairs) for drawing. A bone is drawn only when both
    /// endpoints are present in the frame.
    static let bones: [(BodyJoint, BodyJoint)] = [
        (.leftShoulder, .rightShoulder),   // shoulders
        (.leftShoulder, .leftElbow),       // left arm
        (.leftElbow,    .leftWrist),
        (.rightShoulder, .rightElbow),     // right arm
        (.rightElbow,   .rightWrist),
        (.leftShoulder, .leftHip),         // torso sides
        (.rightShoulder, .rightHip),
        (.leftHip,      .rightHip),        // hips
        (.leftHip,      .leftKnee),        // left leg
        (.leftKnee,     .leftAnkle),
        (.rightHip,     .rightKnee),       // right leg
        (.rightKnee,    .rightAnkle),
    ]

    /// Bones expressed as index pairs into `PoseFrame.points`.
    static let boneIndices: [(Int, Int)] = bones.map { ($0.0.rawValue, $0.1.rawValue) }
}
