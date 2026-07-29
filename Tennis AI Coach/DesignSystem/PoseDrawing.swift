//
//  PoseDrawing.swift
//  Tennis AI Coach
//
//  The one skeleton renderer. Live overlay (Canvas), annotated MP4 export,
//  and share cards all draw through here so the skeleton looks identical
//  everywhere: hitting-arm kinetic chain in clay, body in court-light,
//  white joints.
//

import CoreGraphics
import UIKit

nonisolated enum PoseDrawing {

    // Asset-catalog colors with hard fallbacks (engine code must never crash
    // on a missing asset).
    static var armColor: UIColor {
        UIColor(named: "Clay") ?? UIColor(red: 0.87, green: 0.43, blue: 0.25, alpha: 1)
    }
    static var bodyColor: UIColor {
        UIColor(named: "CourtLight") ?? UIColor(red: 0.22, green: 0.60, blue: 0.42, alpha: 1)
    }

    /// Bone indices (into JointMapping.boneIndices) of the hitting-arm chain.
    static func armBoneIndexSet(for arm: HittingArm) -> Set<Int> {
        let chain: [BodyJoint] = arm == .right
            ? [.rightShoulder, .rightElbow, .rightWrist]
            : [.leftShoulder, .leftElbow, .leftWrist]
        let joints = Set(chain.map(\.rawValue))
        return Set(JointMapping.boneIndices.enumerated()
            .filter { joints.contains($0.element.0) && joints.contains($0.element.1) }
            .map(\.offset))
    }

    /// Draws a pose into a CGContext whose coordinate space is `size`
    /// (top-left origin, as UIGraphicsImageRenderer provides).
    static func draw(pose: PoseFrame,
                     in cg: CGContext,
                     size: CGSize,
                     hittingArm: HittingArm,
                     scale: CGFloat = 1) {
        let points: [CGPoint?] = pose.points.map { normalized in
            normalized.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        }
        let armBones = armBoneIndexSet(for: hittingArm)

        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        // Body bones.
        cg.setLineWidth(max(2, 3 * scale))
        cg.setStrokeColor(bodyColor.cgColor)
        for (i, bone) in JointMapping.boneIndices.enumerated() where !armBones.contains(i) {
            let (a, b) = bone
            guard a < points.count, b < points.count,
                  let pa = points[a], let pb = points[b] else { continue }
            cg.move(to: pa)
            cg.addLine(to: pb)
            cg.strokePath()
        }

        // Hitting-arm chain, slightly heavier.
        cg.setLineWidth(max(2.5, 4 * scale))
        cg.setStrokeColor(armColor.cgColor)
        for (i, bone) in JointMapping.boneIndices.enumerated() where armBones.contains(i) {
            let (a, b) = bone
            guard a < points.count, b < points.count,
                  let pa = points[a], let pb = points[b] else { continue }
            cg.move(to: pa)
            cg.addLine(to: pb)
            cg.strokePath()
        }

        // Joints.
        let radius = max(2, 4 * scale)
        cg.setFillColor(UIColor.white.cgColor)
        for case let point? in points {
            cg.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                      width: radius * 2, height: radius * 2))
        }
    }
}
