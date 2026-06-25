//
//  AnalysisPipeline.swift
//  Tennis AI Coach
//
//  Top-level orchestration: decode -> pose -> per-frame metrics -> strokes ->
//  coaching. The frame loop is synchronous and runs off the main actor (called
//  from a nonisolated async engine method).
//

import AVFoundation
import CoreMedia

enum AnalysisPipeline {

    nonisolated static func run(source: VideoSource,
                                config: AnalysisConfig,
                                progress: @Sendable (Double) -> Void) throws -> AnalysisResult {
        let stride = max(1, config.sampleStride)
        let dt = (1.0 / source.fps) * Double(stride)

        let (reader, output) = try source.makeReader()
        guard reader.startReading() else {
            throw AnalysisError.decodeFailed(reader.error?.localizedDescription)
        }

        let estimator = PoseEstimator(confidenceThreshold: config.jointConfidenceThreshold)
        var computer = MetricsComputer()
        var frames: [FrameMetrics] = []
        var poses: [PoseFrame] = []

        let estProcessed = max(1, source.estimatedFrameCount / stride)
        var rawIndex = 0
        var processedIndex = 0

        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            defer { rawIndex += 1 }

            if Task.isCancelled {
                reader.cancelReading()
                throw AnalysisError.cancelled
            }
            if rawIndex % stride != 0 { continue }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }

            let joints = estimator.estimate(
                pixelBuffer: pixelBuffer,
                orientation: source.orientation,
                orientedSize: source.orientedSize)
            let timeS = Double(rawIndex) / source.fps

            let row = computer.makeRow(
                joints: joints,
                processedIndex: processedIndex,
                rawFrameIndex: rawIndex,
                timeS: timeS,
                dt: dt,
                config: config)
            frames.append(row)
            poses.append(makePoseFrame(joints: joints, timeS: timeS, orientedSize: source.orientedSize))
            processedIndex += 1

            if processedIndex % 4 == 0 {
                progress(min(0.99, Double(processedIndex) / Double(estProcessed)))
            }
            if let cap = config.maxFrames, processedIndex >= cap { break }
        }

        if reader.status == .failed {
            throw AnalysisError.decodeFailed(reader.error?.localizedDescription)
        }
        guard !frames.isEmpty else { throw AnalysisError.noFramesDecoded }
        progress(1.0)

        let hittingArm = StrokeDetector.pickHittingArm(frames: frames)
        let strokes = StrokeDetector.detect(
            frames: frames, hittingArm: hittingArm,
            fps: source.fps, sampleStride: stride)
        let summary = CoachingEngine.summarize(frames: frames, strokes: strokes)
        let coaching = CoachingEngine.generate(summary: summary, hittingArm: hittingArm)

        let meta = VideoMeta(
            fps: source.fps,
            width: source.orientedSize.width,
            height: source.orientedSize.height,
            durationS: source.durationS,
            sampleStride: stride)

        return AnalysisResult(
            meta: meta, hittingArm: hittingArm,
            frames: frames, poses: poses, strokes: strokes,
            summary: summary, coaching: coaching)
    }
}
