//
//  PoseEstimator.swift
//  Tennis AI Coach
//
//  Wraps a reused VNDetectHumanBodyPoseRequest. Returns the single
//  highest-confidence person's joints, denormalized to oriented pixel space,
//  with low-confidence joints dropped (-> NaN downstream, matching the
//  notebook's None handling).
//

import Vision
import CoreVideo
import ImageIO

nonisolated final class PoseEstimator {
    private let request = VNDetectHumanBodyPoseRequest()
    private let confidenceThreshold: Float

    init(confidenceThreshold: Float) {
        self.confidenceThreshold = confidenceThreshold
    }

    /// Run pose estimation on one frame. Returns joints in oriented pixel space
    /// (origin top-left, y-down). An empty dictionary means "no person".
    func estimate(pixelBuffer: CVPixelBuffer,
                  orientation: CGImagePropertyOrientation,
                  orientedSize: CGSize) -> [BodyJoint: Pt] {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return [:]
        }
        guard let observations = request.results, !observations.isEmpty else { return [:] }

        // Single-person selection: highest overall confidence.
        guard let best = observations.max(by: { $0.confidence < $1.confidence }) else {
            return [:]
        }

        var joints: [BodyJoint: Pt] = [:]
        for (bodyJoint, visionName) in JointMapping.visionJoint {
            guard let point = try? best.recognizedPoint(visionName) else { continue }
            guard point.confidence >= confidenceThreshold else { continue }
            joints[bodyJoint] = CoordinateSpace.denormalize(point.location, orientedSize: orientedSize)
        }
        return joints
    }
}
