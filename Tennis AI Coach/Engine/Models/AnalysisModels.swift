//
//  AnalysisModels.swift
//  Tennis AI Coach
//
//  Shared data contract between the analysis engine and the UI.
//  Ported from the Colab notebook's metrics_df / strokes_df / report schema.
//

import Foundation
import CoreGraphics

// MARK: - Joints

/// The 12 body joints the notebook's metrics depend on. A fixed ordering
/// (the `Int` raw value) indexes into `PoseFrame.points`.
nonisolated enum BodyJoint: Int, CaseIterable, Codable, Sendable {
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

nonisolated enum HittingArm: String, Codable, Sendable {
    case left
    case right

    var displayName: String { self == .left ? "Left" : "Right" }
}

// MARK: - Per-frame metrics (one metrics_df row)

/// All values are in the notebook's units. `Double.nan` means "missing"
/// (mirrors numpy's `float("nan")` / `None` handling). Persisted via a
/// JSON coder configured with `nonConformingFloatEncodingStrategy`.
nonisolated struct FrameMetrics: Codable, Sendable, Identifiable {
    var frameIndex: Int          // notebook frame_i (original video frame number)
    var timeS: Double            // notebook time_s = frame_i / fps
    var kneeL: Double            // left_knee_angle_deg
    var kneeR: Double            // right_knee_angle_deg
    var elbowL: Double           // left_elbow_angle_deg
    var elbowR: Double           // right_elbow_angle_deg
    var torsoLean: Double        // torso_lean_deg (signed)
    var torsoLeanAbs: Double     // torso_lean_abs_deg
    var stanceRatio: Double      // stance_width_ratio
    var wristSpeedL: Double      // left_wrist_speed_px_s  (may be NaN)
    var wristSpeedR: Double      // right_wrist_speed_px_s (may be NaN)

    var id: Int { frameIndex }

    /// The "more bent" knee for a given frame (notebook knee_min_each), NaN-aware.
    var kneeMin: Double { NanStats.pairNanMin(kneeL, kneeR) }

    func wristSpeed(for arm: HittingArm) -> Double {
        arm == .left ? wristSpeedL : wristSpeedR
    }

    func elbow(for arm: HittingArm) -> Double {
        arm == .left ? elbowL : elbowR
    }
}

// MARK: - Pose geometry for overlay drawing

/// A single frame's joints in **normalized, top-left-origin** coordinates
/// ([0,1] over the displayed/oriented video frame). `nil` = joint missing.
nonisolated struct PoseFrame: Codable, Sendable {
    var timeS: Double
    /// Indexed by `BodyJoint.rawValue`; count == `BodyJoint.allCases.count`.
    var points: [CGPoint?]

    func point(_ joint: BodyJoint) -> CGPoint? {
        guard joint.rawValue < points.count else { return nil }
        return points[joint.rawValue]
    }

    var hasAnyJoint: Bool { points.contains { $0 != nil } }
}

// MARK: - Strokes (one strokes_df row)

nonisolated struct Stroke: Codable, Sendable, Identifiable {
    var id: Int                  // stroke_id (1-based)
    var peakTime: Double         // peak_time_s
    var peakFrame: Int           // peak_frame_i
    var hittingArm: HittingArm   // hitting_arm_guess
    var peakSpeed: Double        // peak_speed_px_s
    var minKnee: Double          // min_knee_angle_deg
    var stanceMed: Double        // stance_width_ratio_med
    var leanAbsMed: Double       // torso_lean_abs_deg_med
    var elbowMed: Double         // hitting_elbow_angle_deg_med
}

// MARK: - Summary (summarize_metrics output)

nonisolated struct AnalysisSummary: Codable, Sendable {
    var durationS: Double
    var framesProcessed: Int
    var strokesDetected: Int

    // Global medians (computed over every processed frame).
    var kneeMinGlobalMed: Double
    var leanAbsGlobalMed: Double
    var stanceGlobalMed: Double

    // At-stroke medians (NaN when no strokes were detected).
    var kneeMinStrokeMed: Double
    var leanAbsStrokeMed: Double
    var stanceStrokeMed: Double
    var elbowStrokeMed: Double
    var peakSpeedMed: Double
}

// MARK: - Coaching report

nonisolated struct CoachingReport: Codable, Sendable {
    var good: [String]
    var focus: [String]
    var markdown: String
}

// MARK: - Video metadata

nonisolated struct VideoMeta: Codable, Sendable {
    var fps: Double
    var width: Double            // oriented (displayed) width
    var height: Double           // oriented (displayed) height
    var durationS: Double
    var sampleStride: Int
}

// MARK: - Top-level result

nonisolated struct AnalysisResult: Codable, Sendable {
    var meta: VideoMeta
    var hittingArm: HittingArm
    var frames: [FrameMetrics]
    var poses: [PoseFrame]       // parallel to `frames`
    var strokes: [Stroke]
    var summary: AnalysisSummary
    var coaching: CoachingReport

    /// True when at least some pose data was extractable. A "degenerate but
    /// valid" result (no person ever tracked) is `false` and routes to a
    /// dedicated empty state rather than an error.
    var isUsable: Bool {
        summary.framesProcessed > 0 &&
        (summary.kneeMinGlobalMed.isFinite ||
         summary.leanAbsGlobalMed.isFinite ||
         summary.stanceGlobalMed.isFinite)
    }
}

// MARK: - Config (ported AnalysisConfig dataclass)

nonisolated struct AnalysisConfig: Sendable {
    var sampleStride: Int = 2
    var jointConfidenceThreshold: Float = 0.3   // Vision per-joint gate (bug fix)
    var stanceRejectAbove: Double = 3.0         // anatomical outlier clamp (bug fix)
    var maxFrames: Int? = nil

    static let `default` = AnalysisConfig()
}

// MARK: - JSON coders (NaN-safe)

nonisolated enum AnalysisCoders {
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }
}
