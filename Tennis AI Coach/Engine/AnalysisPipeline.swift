//
//  AnalysisPipeline.swift
//  Tennis AI Coach
//
//  Top-level orchestration: find the player -> pose -> per-frame metrics ->
//  strokes -> coaching. The frame loops are synchronous and run off the main
//  actor (called from a nonisolated async engine method).
//

import AVFoundation
import CoreMedia

enum AnalysisPipeline {

    /// Share of the progress bar given to finding the player. It decodes the
    /// whole clip but runs a detector on one frame in three, against a pose
    /// request on every frame in pass 2.
    nonisolated private static let locateShare = 0.25

    nonisolated static func run(source: VideoSource,
                                config: AnalysisConfig,
                                onsets: [AudioOnset] = [],
                                progress: @Sendable (Double) -> Void) throws -> AnalysisResult {
        let stride = config.stride(forFPS: source.fps)
        let samplesPerSecond = source.fps / Double(stride)
        let dt = 1.0 / samplesPerSecond

        // Pass 1: where is the player in each frame? (PlayerTracker.swift)
        let plan = try SubjectLocator.locate(source: source, stride: stride) { p in
            progress(locateShare * p)
        }

        // Pass 2: pose on the player, every sampled frame.
        let (reader, output) = try source.makeReader()
        guard reader.startReading() else {
            throw AnalysisError.decodeFailed(reader.error?.localizedDescription)
        }

        let estimator = PoseEstimator(confidenceThreshold: config.jointConfidenceThreshold)
        var tracker = SubjectTracker(plan: plan, frameSize: source.orientedSize,
                                     samplesPerSecond: samplesPerSecond)
        // Joints are collected for the whole clip first: a wrist position can
        // only be judged against its neighbours and against the player's own
        // proportions, and it has to be judged BEFORE any speed is differenced
        // from it (see WristTrackingGate). Twelve points a frame is nothing.
        var jointsPerFrame: [[BodyJoint: Pt]] = []
        var frameTimes: [(rawIndex: Int, timeS: Double)] = []

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

            let joints = tracker.track(index: rawIndex / stride,
                                       pixelBuffer: pixelBuffer,
                                       orientation: source.orientation,
                                       estimator: estimator)
            let timeS = Double(rawIndex) / source.fps

            jointsPerFrame.append(joints)
            frameTimes.append((rawIndex, timeS))
            processedIndex += 1

            if processedIndex % 4 == 0 {
                let p = min(0.99, Double(processedIndex) / Double(estProcessed))
                progress(locateShare + (1 - locateShare) * p)
            }
            if let cap = config.maxFrames, processedIndex >= cap { break }
        }

        if reader.status == .failed {
            throw AnalysisError.decodeFailed(reader.error?.localizedDescription)
        }
        guard !jointsPerFrame.isEmpty else { throw AnalysisError.noFramesDecoded }
        progress(1.0)

        let tracked = WristTrackingGate.clean(jointsPerFrame)
        let motion = WristMotion.speeds(joints: tracked, times: frameTimes.map(\.timeS))
        let limbs = LimbReference.measure(tracked, torso: motion.torso)

        var computer = MetricsComputer()
        var frames: [FrameMetrics] = []
        var poses: [PoseFrame] = []
        frames.reserveCapacity(tracked.count)
        poses.reserveCapacity(tracked.count)
        for (i, joints) in tracked.enumerated() {
            frames.append(computer.makeRow(
                joints: joints,
                processedIndex: i,
                rawFrameIndex: frameTimes[i].rawIndex,
                timeS: frameTimes[i].timeS,
                dt: dt,
                config: config,
                limbs: limbs,
                torso: motion.torso[i]))
            poses.append(makePoseFrame(joints: joints,
                                       timeS: frameTimes[i].timeS,
                                       orientedSize: source.orientedSize))
        }

        // The racquet hand: the player's own word for it when there is one.
        // The guess compares raw image speeds (what it was measured on), so
        // it runs before those are replaced by body-relative ones below.
        let hittingArm = config.hittingArm ?? StrokeDetector.pickHittingArm(frames: frames)
        for i in frames.indices {
            frames[i].wristSpeedL = motion.left[i]
            frames[i].wristSpeedR = motion.right[i]
        }

        var strokes = StrokeDetector.detect(
            frames: frames, hittingArm: hittingArm,
            fps: source.fps, sampleStride: stride, onsets: onsets)
        StrokeAnatomy.annotate(&strokes, frames: frames, joints: tracked,
                               torso: motion.torso, hittingArm: hittingArm)
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
            summary: summary, coaching: coaching,
            engineVersion: AnalysisResult.currentEngineVersion)
    }
}
