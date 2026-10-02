//
//  ScoreModels.swift
//  Tennis AI Coach
//
//  Value types for per-shot and session scoring. Computed at display time by
//  ShotScorer — NEVER persisted, so the on-disk AnalysisResult JSON schema is
//  untouched and legacy sessions keep decoding.
//
//  Honesty contract: scores grade form against fixed standards (FormBands),
//  the same for every player and session. Swing speed is the hand's speed
//  relative to the player's own hips in torso lengths per second, which is
//  the same at any distance or zoom; it is still a 2D estimate, so nothing
//  here may be rendered as mph or px/s.
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
        case swingSpeed          // hand speed, torso lengths/s relative to the hips
        case shoulderTurn        // groundstrokes: degrees the shoulders turned
        case kneeBend            // knee angle at the load, degrees
        case kineticChain        // groundstrokes: trunk's share of the hand's speed
        case shoulderTilt        // serves: trophy-position shoulder tilt, degrees
        case torsoStability
        case elbowExtension
        case stanceWidth
        case reach               // serves: hand height at contact
        case finish              // groundstrokes: hand height after contact

        var displayName: String {
            switch self {
            case .swingSpeed: return "Swing speed"
            case .shoulderTurn: return "Shoulder turn"
            case .kneeBend: return "Knee bend"
            case .kineticChain: return "Body-led swing"
            case .shoulderTilt: return "Shoulder tilt"
            case .torsoStability: return "Torso stability"
            case .elbowExtension: return "Elbow extension"
            case .stanceWidth: return "Stance width"
            case .reach: return "Reach at contact"
            case .finish: return "Finish height"
            }
        }

        /// The parts that make a swing powerful rather than merely tidy. A
        /// shot's score can't run more than `ShotScorer.powerMargin` above
        /// these: a still, upright, arm-only swing breaks none of the other
        /// rules, and it shouldn't pass for a good stroke.
        var isPower: Bool {
            switch self {
            case .swingSpeed, .shoulderTurn, .kneeBend, .shoulderTilt: return true
            default: return false
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
    /// The stroke's kind and contact timing, carried along so coaching can
    /// talk about "your backhands" without reaching back into the strokes.
    var strokeKind: StrokeKind? = nil
    var timing: ContactTiming? = nil

    var id: Int { strokeId }
    var band: ScoreBand { ScoreBand(score: overall) }
    var isGraded: Bool { overall.isFinite }

    /// Weakest measurable form component (excludes swing speed — "work on
    /// your speed" is an outcome, not a form cue).
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
