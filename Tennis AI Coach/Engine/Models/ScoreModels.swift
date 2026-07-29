//
//  ScoreModels.swift
//  Tennis AI Coach
//
//  Value types for per-shot and session scoring. Computed at display time by
//  ShotScorer — NEVER persisted, so the on-disk AnalysisResult JSON schema is
//  untouched and legacy sessions keep decoding.
//
//  Honesty contract: scores are relative FORM indices for one session, not
//  physical measurements. The speed component is normalized to the session's
//  own fastest swing (unitless); nothing here may be rendered as mph or px/s.
//

import Foundation

// MARK: - Bands

/// Score bands drive every score color in the UI (color = semantics only).
nonisolated enum ScoreBand: String, Sendable {
    case excellent      // 85–100
    case solid          // 70–84
    case developing     // 55–69
    case workOn         // 0–54
    case ungraded       // NaN — low tracking or too few measurable components

    init(score: Double) {
        switch score {
        case let s where !s.isFinite: self = .ungraded
        case 85...:  self = .excellent
        case 70...:  self = .solid
        case 55...:  self = .developing
        default:     self = .workOn
        }
    }

    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .solid: return "Solid"
        case .developing: return "Developing"
        case .workOn: return "Work on it"
        case .ungraded: return "Not graded"
        }
    }
}

// MARK: - Tracking confidence

/// Joint-presence coverage over the stroke window (proxy for Vision
/// confidence, which PoseEstimator discards after its 0.3 gate).
nonisolated enum ConfidenceLevel: String, Sendable {
    case high       // coverage ≥ 0.75
    case medium     // coverage ≥ 0.5 — score shown but provisional
    case low        // coverage < 0.5 — shot is ungraded

    init(coverage: Double) {
        switch coverage {
        case 0.75...: self = .high
        case 0.5...:  self = .medium
        default:      self = .low
        }
    }

    var label: String {
        switch self {
        case .high: return "High tracking"
        case .medium: return "Medium tracking"
        case .low: return "Low tracking"
        }
    }
}

// MARK: - Components

nonisolated struct ShotScoreComponent: Sendable, Identifiable {
    enum Kind: String, CaseIterable, Sendable {
        case swingSpeed          // relative to session best — unitless
        case kneeBend
        case torsoStability
        case elbowExtension
        case stanceWidth
        case prepFollowThrough

        var displayName: String {
            switch self {
            case .swingSpeed: return "Swing speed"
            case .kneeBend: return "Knee bend"
            case .torsoStability: return "Torso stability"
            case .elbowExtension: return "Elbow extension"
            case .stanceWidth: return "Stance width"
            case .prepFollowThrough: return "Prep & follow-through"
            }
        }
    }

    var kind: Kind
    var score: Double        // 0–100, NaN = not measurable in this clip
    var weight: Double       // nominal weight before renormalization
    var rawValue: Double     // underlying measurement (deg, ratio, fraction)

    var id: Kind { kind }
}

// MARK: - Per-shot score

nonisolated struct ShotScore: Sendable, Identifiable {
    var strokeId: Int
    var overall: Double              // 0–100; NaN = ungraded
    var trackingCoverage: Double     // 0–1 joint coverage over the window
    var confidence: ConfidenceLevel
    var components: [ShotScoreComponent]

    var id: Int { strokeId }
    var band: ScoreBand { ScoreBand(score: overall) }
    var isGraded: Bool { overall.isFinite }

    /// Weakest measurable form component (excludes swing speed — "work on
    /// your speed" is not actionable form advice).
    var weakestFormComponent: ShotScoreComponent? {
        components
            .filter { $0.kind != .swingSpeed && $0.score.isFinite }
            .min { $0.score < $1.score }
    }
}

// MARK: - Session rollup

nonisolated struct SessionScore: Sendable {
    var overall: Double          // median of graded shots; NaN if none
    var consistency: Double      // 0–100 from spread of graded shots; NaN if <2
    var gradedShots: Int
    var totalShots: Int
    var best: Double             // NaN if no graded shots
    var average: Double
    var worst: Double
    var bestShotId: Int?
    var worstShotId: Int?

    var band: ScoreBand { ScoreBand(score: overall) }

    /// Mirrors CoachingEngine's existing "<4 strokes" warning threshold.
    var isProvisional: Bool { gradedShots < 4 }
}

// MARK: - Findings (flaw frequency)

/// "Knee bend outside the athletic band on 4 of 9 swings."
nonisolated struct FindingCount: Sendable, Identifiable {
    var kind: ShotScoreComponent.Kind
    var affectedShots: Int
    var totalGradedShots: Int
    var text: String

    var id: ShotScoreComponent.Kind { kind }
}
