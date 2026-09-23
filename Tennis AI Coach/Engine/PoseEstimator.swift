//
//  PoseEstimator.swift
//  Tennis AI Coach
//
//  Wraps a reused VNDetectHumanBodyPoseRequest. Returns every person Vision
//  found — in the whole frame, or in a region of it — as joints denormalized
//  to oriented pixel space, with low-confidence joints dropped (-> NaN
//  downstream, matching the notebook's None handling). Choosing which of them
//  is the player is `SubjectTracker`'s job.
//

import Vision
import CoreVideo
import ImageIO
import simd

nonisolated final class PoseEstimator {
    private let request = VNDetectHumanBodyPoseRequest()
    private let confidenceThreshold: Float

    /// One person's pose.
    struct Detection {
        /// The twelve metric joints that cleared the confidence gate.
        var joints: [BodyJoint: Pt]
        /// Bounds of every confident point Vision returned for this person,
        /// head and neck included — the size and position used to track them.
        var box: CGRect
        var confidence: Float
        /// The box spans the whole body, so its height is the player's.
        var isHeadToAnkle: Bool
    }

    init(confidenceThreshold: Float) {
        self.confidenceThreshold = confidenceThreshold
    }

    /// Run pose estimation on one frame, optionally restricted to `region`
    /// (oriented pixel space, top-left origin). Everything returned is in
    /// oriented pixel space over the WHOLE frame, whatever the region.
    func detect(pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation,
                orientedSize: CGSize,
                region: CGRect?) -> [Detection] {
        // Vision takes the region normalized with a bottom-left origin and
        // hands points back normalized to that region, not to the frame.
        let roi = region.map { CoordinateSpace.normalize(rect: $0, orientedSize: orientedSize) }
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        request.regionOfInterest = roi

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observations = request.results else { return [] }

        func toFrame(_ p: CGPoint) -> Pt {
            let inFrame = CGPoint(x: roi.minX + p.x * roi.width, y: roi.minY + p.y * roi.height)
            return CoordinateSpace.denormalize(inFrame, orientedSize: orientedSize)
        }

        return observations.compactMap { observation in
            guard let all = try? observation.recognizedPoints(.all) else { return nil }
            var joints: [BodyJoint: Pt] = [:]
            for (bodyJoint, visionName) in JointMapping.visionJoint {
                guard let point = all[visionName], point.confidence >= confidenceThreshold else { continue }
                joints[bodyJoint] = toFrame(point.location)
            }
            let confident = all.values.filter { $0.confidence >= confidenceThreshold }.map { toFrame($0.location) }
            guard let first = confident.first else { return nil }
            var lo = first, hi = first
            for p in confident {
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
            }
            let hasHead = [VNHumanBodyPoseObservation.JointName.nose, .leftEye, .rightEye, .neck]
                .contains { (all[$0]?.confidence ?? 0) >= confidenceThreshold }
            let hasAnkle = joints[.leftAnkle] != nil || joints[.rightAnkle] != nil
            return Detection(
                joints: joints,
                box: CGRect(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y),
                confidence: observation.confidence,
                isHeadToAnkle: hasHead && hasAnkle)
        }
    }
}
