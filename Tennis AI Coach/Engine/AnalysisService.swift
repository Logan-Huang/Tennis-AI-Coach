//
//  AnalysisService.swift
//  Tennis AI Coach
//
//  The engine facade the UI talks to. VisionAnalysisEngine is the real
//  on-device engine; MockEngine produces deterministic data for previews.
//

import Foundation
import CoreGraphics

protocol AnalysisEngine: Sendable {
    nonisolated func analyze(videoURL: URL,
                             config: AnalysisConfig,
                             progress: @Sendable @escaping (Double) -> Void) async throws -> AnalysisResult

    nonisolated func exportAnnotatedVideo(result: AnalysisResult,
                                          sourceURL: URL,
                                          progress: @Sendable @escaping (Double) -> Void) async throws -> URL
}

extension AnalysisEngine {
    nonisolated func analyze(videoURL: URL,
                             progress: @Sendable @escaping (Double) -> Void) async throws -> AnalysisResult {
        try await analyze(videoURL: videoURL, config: .default, progress: progress)
    }
}

// MARK: - Real engine

nonisolated final class VisionAnalysisEngine: AnalysisEngine {
    init() {}

    nonisolated func analyze(videoURL: URL,
                             config: AnalysisConfig,
                             progress: @Sendable @escaping (Double) -> Void) async throws -> AnalysisResult {
        let source = try await VideoSource.load(url: videoURL)
        try Task.checkCancellation()
        return try AnalysisPipeline.run(source: source, config: config, progress: progress)
    }

    nonisolated func exportAnnotatedVideo(result: AnalysisResult,
                                          sourceURL: URL,
                                          progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let source = try await VideoSource.load(url: sourceURL)
        return try await AnnotatedVideoExporter.export(source: source, result: result, progress: progress)
    }
}

// MARK: - Mock engine (previews / UI development)

nonisolated final class MockEngine: AnalysisEngine {
    init() {}

    nonisolated func analyze(videoURL: URL,
                             config: AnalysisConfig,
                             progress: @Sendable @escaping (Double) -> Void) async throws -> AnalysisResult {
        // Simulate work with progress.
        for step in 1...10 {
            try? await Task.sleep(nanoseconds: 80_000_000)
            progress(Double(step) / 10.0)
        }
        return MockEngine.sampleResult()
    }

    nonisolated func exportAnnotatedVideo(result: AnalysisResult,
                                          sourceURL: URL,
                                          progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        for step in 1...5 {
            try? await Task.sleep(nanoseconds: 60_000_000)
            progress(Double(step) / 5.0)
        }
        return sourceURL
    }

    /// Deterministic synthetic result: a sine-wave right-wrist speed with a few
    /// peaks, a gently swaying skeleton, and some NaN gaps.
    nonisolated static func sampleResult() -> AnalysisResult {
        let fps = 30.0
        let stride = 2
        let count = 150

        var frames: [FrameMetrics] = []
        var poses: [PoseFrame] = []
        frames.reserveCapacity(count)
        poses.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i * stride) / fps
            let phase = Double(i) * 0.18
            // Right wrist speed: baseline + periodic swing peaks; a couple of NaN gaps.
            let isGap = (i % 47 == 0)
            let swing = max(0.0, sin(phase)) * 2600.0
            let rightSpeed = isGap ? Double.nan : 250.0 + swing + 120.0 * sin(phase * 3.1)
            let leftSpeed = isGap ? Double.nan : 180.0 + 90.0 * abs(sin(phase * 0.7))

            let knee = 138.0 - 22.0 * max(0.0, sin(phase))   // dips during swings
            let elbow = 96.0 + 30.0 * sin(phase + 0.5)
            let lean = 9.0 + 6.0 * sin(phase * 0.5)
            let stance = 1.25 + 0.18 * sin(phase * 0.3)

            frames.append(FrameMetrics(
                frameIndex: i * stride, timeS: t,
                kneeL: knee + 4, kneeR: knee, elbowL: elbow - 10, elbowR: elbow,
                torsoLean: lean, torsoLeanAbs: abs(lean),
                stanceRatio: stance, wristSpeedL: leftSpeed, wristSpeedR: rightSpeed))

            poses.append(MockEngine.samplePose(timeS: t, phase: phase, gap: isGap))
        }

        let hittingArm = StrokeDetector.pickHittingArm(frames: frames)
        let strokes = StrokeDetector.detect(frames: frames, hittingArm: hittingArm, fps: fps, sampleStride: stride)
        let summary = CoachingEngine.summarize(frames: frames, strokes: strokes)
        let coaching = CoachingEngine.generate(summary: summary, hittingArm: hittingArm)
        let meta = VideoMeta(fps: fps, width: 1080, height: 1920,
                             durationS: Double(count * stride) / fps, sampleStride: stride)

        return AnalysisResult(
            meta: meta, hittingArm: hittingArm,
            frames: frames, poses: poses, strokes: strokes,
            summary: summary, coaching: coaching)
    }

    private nonisolated static func samplePose(timeS: Double, phase: Double, gap: Bool) -> PoseFrame {
        var points = [CGPoint?](repeating: nil, count: BodyJoint.allCases.count)
        guard !gap else { return PoseFrame(timeS: timeS, points: points) }

        let sway = 0.02 * sin(phase * 0.5)
        let armSwing = 0.10 * max(0.0, sin(phase))
        func p(_ j: BodyJoint, _ x: Double, _ y: Double) { points[j.rawValue] = CGPoint(x: x + sway, y: y) }

        p(.leftShoulder, 0.44, 0.30); p(.rightShoulder, 0.56, 0.30)
        p(.leftElbow, 0.40, 0.40); p(.rightElbow, 0.60 + armSwing, 0.40 - armSwing)
        p(.leftWrist, 0.38, 0.50); p(.rightWrist, 0.64 + armSwing * 1.6, 0.34 - armSwing * 1.4)
        p(.leftHip, 0.46, 0.55); p(.rightHip, 0.54, 0.55)
        p(.leftKnee, 0.45, 0.72); p(.rightKnee, 0.55, 0.72)
        p(.leftAnkle, 0.45, 0.90); p(.rightAnkle, 0.56, 0.90)
        return PoseFrame(timeS: timeS, points: points)
    }
}
