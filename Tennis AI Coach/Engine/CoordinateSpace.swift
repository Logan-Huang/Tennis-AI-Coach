//
//  CoordinateSpace.swift
//  Tennis AI Coach
//
//  The make-or-break coordinate math. Vision returns normalized points in the
//  ORIENTED frame, origin bottom-left, y-up. The notebook formulas assume pixel
//  space, origin top-left, y-down. We convert once here; afterwards every
//  notebook formula applies verbatim.
//

import CoreGraphics
import ImageIO
import AVFoundation

nonisolated enum CoordinateSpace {

    /// Derive the image orientation from a video track's preferredTransform.
    /// AVAssetReader hands back raw buffers WITHOUT applying this transform, so
    /// we must tell Vision how the frame is rotated.
    static func orientation(from t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0):   return .right   // portrait
        case (0, -1, 1, 0):   return .left    // portrait upside-down
        case (1, 0, 0, 1):    return .up      // landscape, no rotation
        case (-1, 0, 0, -1):  return .down    // landscape 180
        default:
            if t.b == 1 { return .right }
            if t.b == -1 { return .left }
            if t.a == -1 { return .down }
            return .up
        }
    }

    /// Size of the frame AFTER orientation is applied (W/H swapped for portrait).
    static func orientedSize(_ s: CGSize, _ o: CGImagePropertyOrientation) -> CGSize {
        switch o {
        case .right, .left, .rightMirrored, .leftMirrored:
            return CGSize(width: s.height, height: s.width)
        default:
            return s
        }
    }

    /// Convert a Vision normalized point (origin bottom-left, y-up) to pixel
    /// space (origin top-left, y-down) against the ORIENTED size.
    static func denormalize(_ loc: CGPoint, orientedSize sz: CGSize) -> Pt {
        Pt(Double(loc.x) * Double(sz.width),
           Double(1.0 - loc.y) * Double(sz.height))
    }
}
