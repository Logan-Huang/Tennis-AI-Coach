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

nonisolated enum HittingArm: String, Codable, Sendable, CaseIterable {
    case left
    case right

    var displayName: String { self == .left ? "Left" : "Right" }
    var other: HittingArm { self == .left ? .right : .left }
}

/// What kind of shot a stroke was. Decided from where the hands are at
/// contact (StrokeAnatomy), so only when that is legible: a stroke the
/// geometry can't place stays a `.groundstroke` rather than a guess.
nonisolated enum StrokeKind: String, Codable, Sendable, CaseIterable {
    case serve        // hand above the head at contact (serves and overheads)
    case forehand
    case backhand
    case groundstroke // off the ground, side not legible

    var displayName: String {
        switch self {
        case .serve: return "Serve"
        case .forehand: return "Forehand"
        case .backhand: return "Backhand"
        case .groundstroke: return "Groundstroke"
        }
    }

    var pluralName: String {
        switch self {
        case .serve: return "Serves"
        case .forehand: return "Forehands"
        case .backhand: return "Backhands"
        case .groundstroke: return "Groundstrokes"
        }
    }

    var systemImage: String {
        switch self {
        case .serve: return "arrow.up.circle"
        case .forehand: return "arrow.right.circle"
        case .backhand: return "arrow.left.circle"
        case .groundstroke: return "circle.dashed"
        }
    }
}

/// How a stroke's moment of contact was found.
nonisolated enum ContactTiming: String, Codable, Sendable {
    /// The sound of ball on strings, confirmed by the wrist moving fast.
    case heard
    /// The hitting wrist's fastest moment — contact is close to it, not on it.
    case estimated
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
    /// Wrist speed. Sessions analysed since the September 2026 engine store
    /// torso lengths per second relative to the hips (WristMotion); older ones
    /// stored image pixels per second. Only ever compared within one session.
    var wristSpeedL: Double      // (may be NaN)
    var wristSpeedR: Double      // (may be NaN)

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
    var peakTime: Double         // contact time, seconds
    var peakFrame: Int           // contact frame (original video frame index)
    var hittingArm: HittingArm   // hitting_arm_guess
    var peakSpeed: Double        // fastest wrist near contact (session units)
    var minKnee: Double          // min_knee_angle_deg
    var stanceMed: Double        // stance_width_ratio_med
    var leanAbsMed: Double       // torso_lean_abs_deg_med
    var elbowMed: Double         // hitting_elbow_angle_deg_med

    // Added September 2026. Optional so sessions saved before then still
    // decode; `nil` means "measured before this existed", not "zero".
    var kind: StrokeKind? = nil
    var timing: ContactTiming? = nil
    /// Highest hand above the shoulders at contact, in torso lengths
    /// (serves: how fully the player reached up).
    var reach: Double? = nil
    /// Highest hand above the shoulders in the half second after contact, in
    /// torso lengths (groundstrokes: how complete the finish was).
    var finish: Double? = nil
    /// Most-bent knee while loading before a serve, degrees.
    var loadKnee: Double? = nil
    /// Straightest the hitting elbow got right at contact, degrees. A serve's
    /// elbow is bent through the racquet drop and straight at the hit, so its
    /// median over the swing says nothing about the hit.
    var contactElbow: Double? = nil
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
    /// Which engine produced this. `nil`: before September 2026 — full-frame
    /// pose, wrist speeds in image pixels per second, strokes without kinds.
    /// 2: the player tracker, body-relative wrist speeds, heard contacts.
    var engineVersion: Int? = nil

    static let currentEngineVersion = 2

    /// Wrist speeds are torso lengths per second (not image pixels).
    var hasBodyRelativeSpeeds: Bool { (engineVersion ?? 1) >= 2 }

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
    /// The player's racquet hand, when they've told us (their profile). `nil`
    /// guesses it from the clip, which is unreliable for a player filmed from
    /// across the court: Vision can't consistently tell their wrists apart.
    var hittingArm: HittingArm? = nil
    /// Analyse every Nth frame. `nil` picks N so the clip is sampled at about
    /// `targetSamplesPerSecond`: every frame of a 30 fps clip, every other
    /// frame at 60 fps. A swing's fast phase lasts a tenth of a second or so,
    /// and at 15 samples a second it could fall between two of them.
    var sampleStride: Int? = nil
    var targetSamplesPerSecond: Double = 30
    var jointConfidenceThreshold: Float = 0.3   // Vision per-joint gate (bug fix)
    var stanceRejectAbove: Double = 3.0         // anatomical outlier clamp (bug fix)
    var maxFrames: Int? = nil

    static let `default` = AnalysisConfig()

    func stride(forFPS fps: Double) -> Int {
        if let sampleStride { return max(1, sampleStride) }
        guard fps.isFinite, fps > 0 else { return 1 }
        return max(1, Int((fps / targetSamplesPerSecond).rounded()))
    }
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
