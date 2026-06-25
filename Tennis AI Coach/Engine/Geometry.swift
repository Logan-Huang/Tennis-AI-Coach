//
//  Geometry.swift
//  Tennis AI Coach
//
//  Pure math primitives transcribed verbatim from the notebook (cell 8).
//  Points are in PIXEL space, origin top-left, y-down — the same convention
//  the notebook assumes after CoordinateSpace.denormalize() runs.
//

import Foundation
import simd

typealias Pt = SIMD2<Double>

nonisolated enum Geometry {

    /// `angle_deg(a, b, c)`: the angle at vertex `b` formed by a-b-c, in degrees.
    /// Returns NaN if any point is missing or the denominator is degenerate.
    static func angleDeg(_ a: Pt?, _ b: Pt?, _ c: Pt?) -> Double {
        guard let a, let b, let c else { return .nan }
        let ba = a - b
        let bc = c - b
        let denom = simd_length(ba) * simd_length(bc)
        if denom < 1e-9 { return .nan }
        let cosang = min(max(simd_dot(ba, bc) / denom, -1.0), 1.0)
        return acos(cosang) * 180.0 / .pi
    }

    /// `safe_norm(vec)`: Euclidean norm, or NaN if missing.
    static func safeNorm(_ v: Pt?) -> Double {
        guard let v else { return .nan }
        return simd_length(v)
    }

    /// `signed_angle_from_vertical_deg(vec)`. Image coords (x right, y down),
    /// "up" = (0, -1). Positive => leaning to the right of the image.
    static func signedAngleFromVerticalDeg(_ v: Pt?) -> Double {
        guard let v, simd_length(v) >= 1e-9 else { return .nan }
        return atan2(v.x, -v.y) * 180.0 / .pi
    }

    /// Midpoint of two points; NaN-propagating if either is missing.
    static func midpoint(_ a: Pt?, _ b: Pt?) -> Pt? {
        guard let a, let b else { return nil }
        return (a + b) * 0.5
    }
}
