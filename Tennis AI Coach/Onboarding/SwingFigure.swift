//
//  SwingFigure.swift
//  Tennis AI Coach
//
//  A real forehand, drawn the way the app draws every swing it analyses: the
//  skeleton (racquet arm in clay, body in court green, white joints) and the
//  ball meeting it at contact. Onboarding's opening image.
//
//  The motion isn't animated by hand. It is 30 frames of the app's own pose
//  output for one right-handed forehand (the IMG_7145 sample clip), from late
//  in the take-back to the end of the follow-through, gap-filled and lightly
//  smoothed. It carries no photo and no face, only joint positions.
//

import SwiftUI

enum OnboardingSwing {
    /// Frames of the source clip per second; played at half speed.
    static let sourceFPS = 30.0
    static let playbackRate = 0.5
    /// The frame where the ball meets the strings.
    static let contactFrame = 17

    /// Per frame, the twelve joints in `BodyJoint` order as (x, y): body
    /// heights from the hip centre at contact, y down.
    static let frames: [[CGPoint]] = {
        let v: [Float] = raw
        let joints: Int = BodyJoint.allCases.count
        var out: [[CGPoint]] = []
        var start = 0
        while start + 2 * joints <= v.count {
            var frame: [CGPoint] = []
            for j in 0..<joints {
                let x = CGFloat(v[start + 2 * j])
                let y = CGFloat(v[start + 2 * j + 1])
                frame.append(CGPoint(x: x, y: y))
            }
            out.append(frame)
            start += 2 * joints
        }
        return out
    }()

    private static let raw: [Float] = [
        -0.128, -0.271, -0.273, -0.224, -0.267, -0.316, -0.340, -0.231, -0.377, -0.441, -0.386, -0.376, -0.073, 0.125, -0.199, 0.137, 0.002, 0.435, -0.291, 0.405, 0.181, 0.672, -0.269, 0.691,
        -0.122, -0.265, -0.268, -0.214, -0.262, -0.297, -0.333, -0.241, -0.378, -0.420, -0.384, -0.391, -0.064, 0.131, -0.190, 0.141, 0.015, 0.440, -0.289, 0.404, 0.190, 0.670, -0.273, 0.686,
        -0.115, -0.259, -0.262, -0.212, -0.263, -0.288, -0.331, -0.268, -0.384, -0.405, -0.392, -0.400, -0.053, 0.133, -0.182, 0.140, 0.028, 0.441, -0.288, 0.399, 0.190, 0.669, -0.278, 0.674,
        -0.109, -0.258, -0.252, -0.215, -0.273, -0.284, -0.330, -0.287, -0.394, -0.391, -0.402, -0.396, -0.040, 0.129, -0.172, 0.137, 0.042, 0.441, -0.286, 0.398, 0.185, 0.666, -0.284, 0.667,
        -0.102, -0.261, -0.237, -0.217, -0.276, -0.274, -0.325, -0.286, -0.400, -0.371, -0.407, -0.379, -0.024, 0.127, -0.158, 0.135, 0.055, 0.441, -0.280, 0.392, 0.179, 0.660, -0.289, 0.665,
        -0.091, -0.265, -0.221, -0.219, -0.254, -0.255, -0.321, -0.280, -0.389, -0.340, -0.407, -0.354, -0.007, 0.126, -0.145, 0.132, 0.065, 0.440, -0.272, 0.379, 0.176, 0.652, -0.292, 0.659,
        -0.077, -0.268, -0.209, -0.226, -0.215, -0.236, -0.321, -0.277, -0.361, -0.304, -0.407, -0.330, 0.010, 0.124, -0.131, 0.129, 0.076, 0.440, -0.260, 0.361, 0.174, 0.646, -0.295, 0.649,
        -0.061, -0.271, -0.197, -0.239, -0.170, -0.226, -0.310, -0.268, -0.314, -0.270, -0.396, -0.306, 0.025, 0.121, -0.115, 0.123, 0.086, 0.437, -0.245, 0.344, 0.170, 0.643, -0.298, 0.639,
        -0.048, -0.279, -0.183, -0.248, -0.098, -0.224, -0.278, -0.245, -0.238, -0.241, -0.365, -0.274, 0.038, 0.112, -0.100, 0.115, 0.095, 0.426, -0.233, 0.340, 0.165, 0.639, -0.304, 0.630,
        -0.036, -0.296, -0.173, -0.252, 0.005, -0.226, -0.246, -0.216, -0.144, -0.229, -0.341, -0.239, 0.049, 0.097, -0.091, 0.107, 0.102, 0.413, -0.225, 0.348, 0.157, 0.636, -0.310, 0.624,
        -0.016, -0.313, -0.172, -0.258, 0.110, -0.230, -0.231, -0.185, -0.040, -0.227, -0.341, -0.204, 0.059, 0.085, -0.085, 0.099, 0.108, 0.402, -0.215, 0.353, 0.148, 0.633, -0.316, 0.618,
        0.011, -0.323, -0.172, -0.267, 0.165, -0.250, -0.234, -0.157, 0.077, -0.232, -0.356, -0.164, 0.067, 0.074, -0.081, 0.089, 0.113, 0.385, -0.203, 0.347, 0.140, 0.628, -0.322, 0.610,
        0.036, -0.334, -0.167, -0.275, 0.157, -0.291, -0.246, -0.132, 0.184, -0.257, -0.375, -0.113, 0.071, 0.055, -0.078, 0.073, 0.117, 0.363, -0.192, 0.334, 0.134, 0.621, -0.329, 0.601,
        0.065, -0.353, -0.155, -0.287, 0.162, -0.319, -0.246, -0.113, 0.240, -0.285, -0.387, -0.067, 0.074, 0.036, -0.072, 0.053, 0.121, 0.342, -0.189, 0.316, 0.130, 0.614, -0.333, 0.589,
        0.092, -0.372, -0.131, -0.302, 0.198, -0.307, -0.215, -0.118, 0.257, -0.305, -0.363, -0.062, 0.077, 0.023, -0.065, 0.035, 0.121, 0.325, -0.193, 0.299, 0.125, 0.607, -0.334, 0.576,
        0.103, -0.386, -0.099, -0.324, 0.203, -0.283, -0.162, -0.155, 0.257, -0.332, -0.294, -0.101, 0.076, 0.014, -0.061, 0.019, 0.118, 0.315, -0.199, 0.285, 0.116, 0.603, -0.335, 0.563,
        0.101, -0.396, -0.069, -0.350, 0.179, -0.258, -0.093, -0.205, 0.241, -0.363, -0.185, -0.161, 0.073, 0.008, -0.063, 0.006, 0.112, 0.303, -0.201, 0.277, 0.107, 0.601, -0.338, 0.553,
        0.095, -0.405, -0.045, -0.373, 0.156, -0.250, 0.003, -0.245, 0.228, -0.379, -0.010, -0.251, 0.066, 0.004, -0.066, -0.004, 0.102, 0.286, -0.199, 0.272, 0.098, 0.595, -0.340, 0.542,
        0.081, -0.409, -0.025, -0.388, 0.153, -0.275, 0.087, -0.278, 0.236, -0.385, 0.169, -0.343, 0.056, -0.004, -0.069, -0.012, 0.092, 0.276, -0.194, 0.264, 0.086, 0.590, -0.337, 0.526,
        0.066, -0.410, -0.008, -0.402, 0.171, -0.299, 0.135, -0.319, 0.269, -0.396, 0.273, -0.401, 0.047, -0.013, -0.071, -0.019, 0.081, 0.276, -0.186, 0.256, 0.075, 0.586, -0.334, 0.509,
        0.053, -0.421, 0.008, -0.415, 0.177, -0.298, 0.177, -0.361, 0.280, -0.384, 0.323, -0.431, 0.040, -0.019, -0.068, -0.022, 0.073, 0.274, -0.177, 0.251, 0.067, 0.586, -0.334, 0.496,
        0.045, -0.438, 0.020, -0.422, 0.139, -0.276, 0.204, -0.394, 0.226, -0.325, 0.333, -0.438, 0.035, -0.020, -0.064, -0.019, 0.067, 0.267, -0.169, 0.253, 0.059, 0.587, -0.336, 0.489,
        0.019, -0.439, 0.033, -0.430, 0.049, -0.255, 0.196, -0.419, 0.142, -0.262, 0.308, -0.430, 0.026, -0.021, -0.054, -0.018, 0.061, 0.265, -0.160, 0.259, 0.052, 0.583, -0.339, 0.487,
        -0.026, -0.431, 0.053, -0.435, -0.063, -0.257, 0.185, -0.431, 0.065, -0.238, 0.271, -0.424, 0.011, -0.026, -0.039, -0.020, 0.053, 0.268, -0.149, 0.265, 0.045, 0.580, -0.343, 0.486,
        -0.052, -0.428, 0.071, -0.438, -0.127, -0.271, 0.204, -0.431, -0.008, -0.234, 0.232, -0.420, -0.001, -0.033, -0.026, -0.027, 0.046, 0.267, -0.139, 0.271, 0.040, 0.578, -0.346, 0.486,
        -0.058, -0.431, 0.086, -0.444, -0.151, -0.283, 0.240, -0.427, -0.069, -0.230, 0.198, -0.411, -0.007, -0.045, -0.022, -0.038, 0.041, 0.261, -0.132, 0.277, 0.034, 0.575, -0.345, 0.487,
        -0.066, -0.433, 0.101, -0.449, -0.173, -0.291, 0.256, -0.425, -0.103, -0.227, 0.169, -0.402, -0.005, -0.050, -0.023, -0.042, 0.038, 0.254, -0.127, 0.281, 0.028, 0.570, -0.342, 0.488,
        -0.075, -0.435, 0.108, -0.450, -0.194, -0.299, 0.247, -0.420, -0.118, -0.221, 0.142, -0.431, -0.009, -0.049, -0.019, -0.041, 0.033, 0.253, -0.124, 0.283, 0.021, 0.565, -0.337, 0.493,
        -0.085, -0.439, 0.103, -0.451, -0.214, -0.308, 0.235, -0.410, -0.126, -0.216, 0.121, -0.491, -0.030, -0.053, -0.007, -0.039, 0.029, 0.253, -0.124, 0.285, 0.013, 0.562, -0.333, 0.502,
        -0.091, -0.442, 0.096, -0.453, -0.230, -0.316, 0.227, -0.403, -0.135, -0.215, 0.108, -0.521, -0.035, -0.055, -0.002, -0.036, 0.029, 0.248, -0.125, 0.287, 0.009, 0.559, -0.331, 0.506,
    ]
}

/// The swing on a loop: played through, held at the finish, eased back to the
/// start. `animating` false freezes it at contact (Reduce Motion, or a page
/// that isn't showing).
struct SwingFigure: View {
    var animating: Bool
    /// Show the ball arriving at contact and leaving again.
    var showsBall = true
    /// Line weight relative to the figure's size; smaller figures draw finer.
    var weight: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let holdS = 0.8
    private static let returnS = 0.5
    private static var swingS: Double {
        Double(OnboardingSwing.frames.count - 1) / OnboardingSwing.sourceFPS / OnboardingSwing.playbackRate
    }
    private static var cycleS: Double { swingS + holdS + returnS }

    var body: some View {
        TimelineView(.animation(paused: !animating || reduceMotion)) { timeline in
            Canvas { g, size in
                let t = animating && !reduceMotion
                    ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycleS)
                    : Self.contactTime
                draw(in: &g, size: size, at: t)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Timing

    private static var contactTime: Double {
        Double(OnboardingSwing.contactFrame) / OnboardingSwing.sourceFPS / OnboardingSwing.playbackRate
    }

    /// The pose at cycle time `t`, and how far through the swing it is in frames.
    private func pose(at t: Double) -> (points: [CGPoint], frame: Double) {
        let frames = OnboardingSwing.frames
        let last = frames.count - 1
        let f = t * OnboardingSwing.sourceFPS * OnboardingSwing.playbackRate
        if f <= Double(last) {
            let i = Int(f), k = CGFloat(f - Double(i))
            let a = frames[i], b = frames[min(last, i + 1)]
            return (zip(a, b).map { lerp($0, $1, k) }, f)
        }
        let back = t - Self.swingS - Self.holdS
        guard back > 0 else { return (frames[last], Double(last)) }
        // Ease from the finish back to the start of the take-back.
        let k = CGFloat(min(1, back / Self.returnS))
        let eased = k * k * (3 - 2 * k)
        return (zip(frames[last], frames[0]).map { lerp($0, $1, eased) }, Double(last))
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    // MARK: - Drawing

    private func draw(in g: inout GraphicsContext, size: CGSize, at t: Double) {
        let (pts, frame) = pose(at: t)
        let scale = size.height * 0.64
        let origin = CGPoint(x: size.width * 0.54, y: size.height * 0.5)
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: origin.x + q.x * scale, y: origin.y + q.y * scale) }
        func j(_ joint: BodyJoint) -> CGPoint { p(pts[joint.rawValue]) }

        // Shadow under the feet.
        let footY = max(j(.leftAnkle).y, j(.rightAnkle).y) + scale * 0.03
        let footX = (j(.leftAnkle).x + j(.rightAnkle).x) / 2
        g.fill(Ellipse().path(in: CGRect(x: footX - scale * 0.32, y: footY - scale * 0.035,
                                         width: scale * 0.64, height: scale * 0.07)),
               with: .color(.black.opacity(0.28)))

        let line = max(2, scale * 0.024 * weight)
        let racquetArm: Set<BodyJoint> = [.rightShoulder, .rightElbow, .rightWrist]
        g.drawLayer { layer in
            layer.addFilter(.shadow(color: Theme.courtLight.opacity(0.6), radius: line * 1.4))
            for (a, b) in JointMapping.bones {
                var path = Path()
                path.move(to: j(a)); path.addLine(to: j(b))
                let color = racquetArm.contains(a) && racquetArm.contains(b) ? Theme.clay : Theme.onboardingBody
                layer.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: .round))
            }
            // A head, which the twelve tracked joints don't include: above
            // the shoulders along the line of the torso.
            let sc = CGPoint(x: (j(.leftShoulder).x + j(.rightShoulder).x) / 2, y: (j(.leftShoulder).y + j(.rightShoulder).y) / 2)
            let hc = CGPoint(x: (j(.leftHip).x + j(.rightHip).x) / 2, y: (j(.leftHip).y + j(.rightHip).y) / 2)
            let dx = sc.x - hc.x, dy = sc.y - hc.y
            let len = max(1, (dx * dx + dy * dy).squareRoot())
            let head = CGPoint(x: sc.x + dx / len * scale * 0.17, y: sc.y + dy / len * scale * 0.17)
            let r = scale * 0.075
            layer.stroke(Circle().path(in: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Theme.onboardingBody), lineWidth: line)
            for q in pts {
                let c = p(q), jr = line * 0.85
                layer.fill(Circle().path(in: CGRect(x: c.x - jr, y: c.y - jr, width: 2 * jr, height: 2 * jr)), with: .color(.white))
            }
        }

        if showsBall, let ball = ballPosition(frame: frame, pts: pts, contact: OnboardingSwing.frames[OnboardingSwing.contactFrame]) {
            let c = p(ball), r = scale * 0.035
            g.drawLayer { layer in
                layer.addFilter(.shadow(color: Theme.ball.opacity(0.7), radius: r))
                layer.fill(Circle().path(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.ball))
            }
        }
    }

    /// The ball comes in from the left to meet the racquet at contact and
    /// leaves up and to the left, all in the figure's own units.
    private func ballPosition(frame: Double, pts: [CGPoint], contact: [CGPoint]) -> CGPoint? {
        let wrist = contact[BodyJoint.rightWrist.rawValue], elbow = contact[BodyJoint.rightElbow.rawValue]
        let hit = CGPoint(x: wrist.x - 0.16, y: wrist.y + (wrist.y - elbow.y) * 0.4)
        let c = Double(OnboardingSwing.contactFrame)
        let inFrames = 9.0, outFrames = 8.0
        if frame >= c - inFrames && frame < c {
            let k = CGFloat((frame - (c - inFrames)) / inFrames)
            let start = CGPoint(x: hit.x - 1.1, y: hit.y - 0.05)
            return CGPoint(x: start.x + (hit.x - start.x) * k, y: start.y + (hit.y - start.y) * k - sin(k * .pi) * 0.08)
        }
        if frame >= c && frame < c + outFrames {
            let k = CGFloat((frame - c) / outFrames)
            let end = CGPoint(x: hit.x - 1.2, y: hit.y - 0.45)
            return CGPoint(x: hit.x + (end.x - hit.x) * k, y: hit.y + (end.y - hit.y) * k)
        }
        return nil
    }
}
