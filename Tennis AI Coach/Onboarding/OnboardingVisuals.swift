//
//  OnboardingVisuals.swift
//  Tennis AI Coach
//
//  The picture at the top of each onboarding page. Each one shows a feature
//  doing its job, built from the app's real components (score rings, component
//  bars, the stroke breakdown) wherever one exists, so what someone sees here
//  is what they'll see in their first report.
//
//  Every visual takes `active` — true only while its page is on screen — and
//  animates when it becomes active, so swiping to a page plays it from the
//  start. Under Reduce Motion each shows its finished state and holds still.
//

import SwiftUI

// MARK: - Fitting

/// Lays content out at `design` size and scales it uniformly into whatever
/// room the page has, so the same picture fits an iPhone SE and a Pro Max.
struct FitToSize<Content: View>: View {
    var design: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let k = min(1.15, geo.size.width / design.width, geo.size.height / design.height)
            content
                .frame(width: design.width, height: design.height)
                .scaleEffect(k)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - 1. Welcome: a real forehand

struct WelcomeVisual: View {
    var active: Bool

    var body: some View {
        FitToSize(design: CGSize(width: 360, height: 420)) {
            ZStack(alignment: .bottom) {
                SwingFigure(animating: active)
                    .padding(.bottom, 64)
                HStack(spacing: Theme.Spacing.s) {
                    ScoreRing(score: 95, size: .row, overrideColor: Theme.ball)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FOREHAND 3").font(.caption2.weight(.bold)).tracking(1.2)
                        Text("Excellent").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ball)
                    }
                }
                .padding(.leading, Theme.Spacing.s)
                .padding(.trailing, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, Theme.Spacing.s)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 2. Every swing, scored

struct ScoredVisual: View {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private let finished = SessionScore(overall: 91, consistency: 90, gradedShots: 4, totalShots: 4,
                                        best: 95, average: 91, worst: 86, bestShotId: 3, worstShotId: 4)
    private var mix: [Narrative.KindSummary] {
        [.init(kind: .serve, count: 1, graded: 1, median: 94),
         .init(kind: .forehand, count: 1, graded: 1, median: 95),
         .init(kind: .backhand, count: 2, graded: 2, median: 87)]
    }

    var body: some View {
        FitToSize(design: CGSize(width: 380, height: 430)) {
            VStack(spacing: Theme.Spacing.m) {
                SessionHeroCard(
                    session: revealed ? finished
                        : SessionScore(overall: 0, consistency: .nan, gradedShots: 4, totalShots: 4,
                                       best: .nan, average: .nan, worst: .nan, bestShotId: nil, worstShotId: nil),
                    headline: "Forehand 3 was your best at 95 — elbow extension was your steadiest strength.")
                StrokeMixCard(mix: mix)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 24)
            }
            .environment(\.colorScheme, .light)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
        .onChange(of: active, initial: true) { _, isActive in
            guard isActive else { revealed = false; return }
            if reduceMotion { revealed = true; return }
            withAnimation(.easeOut(duration: 1.1).delay(0.2)) { revealed = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 3. A coach for every stroke

struct CoachVisual: View {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 1

    private struct Example {
        let kind: StrokeKind
        let score: Double
        let rows: [(String, Double, String)]
        let focus: String
        let target: String
        let you: String
    }

    private let examples: [Example] = [
        Example(kind: .serve, score: 88,
                rows: [("Knee bend", 100, "129°"), ("Reach at contact", 73, "hand 0.8× torso up"), ("Elbow extension", 100, "170°")],
                focus: "Toss a little higher and hit at full stretch.", target: "1.0×+", you: "0.8×"),
        Example(kind: .forehand, score: 90,
                rows: [("Knee bend", 100, "114°"), ("Torso stability", 100, "7°"), ("Finish height", 75, "chest height")],
                focus: "Let the racquet finish over your shoulder.", target: "over the shoulder", you: "chest height"),
        Example(kind: .backhand, score: 84,
                rows: [("Knee bend", 55, "101°"), ("Stance width", 100, "1.66× hips"), ("Finish height", 100, "shoulder height")],
                focus: "Sink into your legs a little more.", target: "110–155°", you: "101°"),
    ]

    var body: some View {
        let ex = examples[index]
        FitToSize(design: CGSize(width: 380, height: 440)) {
            VStack(spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(examples.indices, id: \.self) { i in
                        Text(examples[i].kind.displayName)
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, 10)
                            .foregroundStyle(i == index ? Theme.courtDeep : .white)
                            .background(i == index ? Theme.ball : Color.white.opacity(0.12), in: Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.m) {
                        ScoreRing(score: ex.score, size: .card)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ex.kind.displayName.uppercased()) 3").microLabel()
                            Text(ScoreBand(score: ex.score).label).font(.headline)
                        }
                    }
                    ForEach(Array(ex.rows.enumerated()), id: \.offset) { _, row in
                        ComponentBarRow(name: row.0, score: row.1, rawText: row.2)
                    }
                    Divider()
                    Text(ex.focus)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    TargetVsYouPill(target: ex.target, you: ex.you)
                }
                .padding(Theme.Spacing.m + 4)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .environment(\.colorScheme, .light)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                .contentTransition(.numericText())
            }
        }
        .task(id: active) {
            guard active, !reduceMotion else { return }
            index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { index = (index + 1) % examples.count }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 4. Finds you across the net

struct TrackingVisual: View {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var locked = false

    var body: some View {
        FitToSize(design: CGSize(width: 380, height: 430)) {
            ZStack {
                CourtLines()
                    .stroke(.white.opacity(0.22), lineWidth: 2)

                // Someone on the next court: seen, and left alone.
                BystanderFigure()
                    .frame(width: 44, height: 92)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(-8)
                    }
                    .overlay(alignment: .bottom) {
                        tag("IGNORED", filled: false).offset(y: 44)
                    }
                    .position(x: 70, y: 120)

                // The player.
                SwingFigure(animating: active, weight: 1.15)
                    .frame(width: 170, height: 230)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Theme.ball, lineWidth: 3)
                            .shadow(color: Theme.ball.opacity(0.7), radius: 10)
                            .scaleEffect(locked ? 1 : 1.25)
                            .opacity(locked ? 1 : 0)
                    }
                    .overlay(alignment: .top) {
                        tag("TRACKED", filled: true)
                            .offset(y: -20)
                            .opacity(locked ? 1 : 0)
                    }
                    .position(x: 250, y: 165)

                NetView()
                    .frame(width: 440, height: 80)
                    .position(x: 190, y: 380)
            }
        }
        .onChange(of: active, initial: true) { _, isActive in
            guard isActive else { locked = false; return }
            if reduceMotion { locked = true; return }
            withAnimation(.spring(duration: 0.6, bounce: 0.3).delay(0.35)) { locked = true }
        }
        .accessibilityHidden(true)
    }

    private func tag(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .tracking(1)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(filled ? Theme.courtDeep : .white)
            .background(filled ? AnyShapeStyle(Theme.ball) : AnyShapeStyle(.black.opacity(0.45)), in: Capsule())
    }
}

/// A court in perspective, seen from behind the net.
private struct CourtLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let farY = r.height * 0.52, nearY = r.height * 1.02
        let farL = r.width * 0.12, farR = r.width * 0.88
        let nearL = -r.width * 0.25, nearR = r.width * 1.25
        p.move(to: CGPoint(x: farL, y: farY)); p.addLine(to: CGPoint(x: farR, y: farY))            // baseline
        p.move(to: CGPoint(x: farL, y: farY)); p.addLine(to: CGPoint(x: nearL, y: nearY))          // sidelines
        p.move(to: CGPoint(x: farR, y: farY)); p.addLine(to: CGPoint(x: nearR, y: nearY))
        let svcY = r.height * 0.68
        let svcL = farL + (nearL - farL) * ((svcY - farY) / (nearY - farY))
        let svcR = farR + (nearR - farR) * ((svcY - farY) / (nearY - farY))
        p.move(to: CGPoint(x: svcL, y: svcY)); p.addLine(to: CGPoint(x: svcR, y: svcY))            // service line
        p.move(to: CGPoint(x: r.midX, y: svcY)); p.addLine(to: CGPoint(x: r.midX, y: nearY))      // centre line
        return p
    }
}

/// The net across the foreground: mesh under a white tape, so the
/// camera is plainly on the other side of it from the player.
private struct NetView: View {
    var body: some View {
        Canvas { g, size in
            let w = size.width, h = size.height, tape: CGFloat = 9
            var mesh = Path()
            var x: CGFloat = 0
            while x <= w { mesh.move(to: CGPoint(x: x, y: tape)); mesh.addLine(to: CGPoint(x: x, y: h)); x += 11 }
            var y = tape
            while y <= h { mesh.move(to: CGPoint(x: 0, y: y)); mesh.addLine(to: CGPoint(x: w, y: y)); y += 11 }
            g.fill(Path(CGRect(x: 0, y: tape, width: w, height: h - tape)), with: .color(.black.opacity(0.35)))
            g.stroke(mesh, with: .color(.white.opacity(0.22)), lineWidth: 1)
            g.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: tape), cornerRadius: 2), with: .color(.white.opacity(0.9)))
        }
    }
}

/// A plain figure standing at the far side of the next court.
private struct BystanderFigure: View {
    var body: some View {
        Canvas { g, size in
            let w = size.width, h = size.height
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            var body = Path()
            body.move(to: pt(0.5, 0.2)); body.addLine(to: pt(0.5, 0.55))                   // torso
            body.move(to: pt(0.5, 0.55)); body.addLine(to: pt(0.32, 0.98))                 // legs
            body.move(to: pt(0.5, 0.55)); body.addLine(to: pt(0.68, 0.98))
            body.move(to: pt(0.5, 0.26)); body.addLine(to: pt(0.2, 0.5))                   // arms
            body.move(to: pt(0.5, 0.26)); body.addLine(to: pt(0.8, 0.46))
            g.stroke(body, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            g.stroke(Circle().path(in: CGRect(x: w * 0.5 - 7, y: h * 0.02, width: 14, height: 14)),
                     with: .color(.white.opacity(0.55)), lineWidth: 3)
        }
    }
}

// MARK: - 5. Hears every hit

struct SoundVisual: View {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bars = 46
    private static let hits: [(bar: Int, kind: StrokeKind)] =
        [(4, .serve), (13, .forehand), (21, .backhand), (30, .forehand), (39, .backhand)]
    private static let sweepS = 4.2
    private static let cycleS = 5.4

    var body: some View {
        FitToSize(design: CGSize(width: 380, height: 380)) {
            VStack(spacing: Theme.Spacing.l) {
                TimelineView(.animation(paused: !active || reduceMotion)) { timeline in
                    let progress = currentProgress(timeline.date)
                    waveform(progress: progress)
                }
                .frame(height: 220)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.l)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.14)))

                HStack(spacing: Theme.Spacing.l) {
                    ForEach([StrokeKind.serve, .forehand, .backhand], id: \.self) { kind in
                        HStack(spacing: 6) {
                            Circle().fill(Self.color(kind)).frame(width: 12, height: 12)
                            Text(kind.displayName).font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .accessibilityHidden(true)
    }

    private func currentProgress(_ date: Date) -> Double {
        guard active, !reduceMotion else { return 1 }
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycleS)
        return min(1, t / Self.sweepS)
    }

    private func waveform(progress: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = w / CGFloat(Self.bars)
            let midY = h * 0.62
            ZStack(alignment: .topLeading) {
                ForEach(0..<Self.bars, id: \.self) { i in
                    let amp = Self.amplitude(i)
                    let played = Double(i) / Double(Self.bars) <= progress
                    Capsule()
                        .fill(.white.opacity(played ? 0.9 : 0.3))
                        .frame(width: step * 0.55, height: max(4, amp * h * 0.6))
                        .position(x: step * (CGFloat(i) + 0.5), y: midY)
                }
                ForEach(Self.hits, id: \.bar) { hit in
                    let x = step * (CGFloat(hit.bar) + 0.5)
                    let heard = Double(hit.bar) / Double(Self.bars) <= progress
                    Rectangle()
                        .fill(Self.color(hit.kind))
                        .frame(width: 2.5, height: h * 0.72)
                        .position(x: x, y: midY)
                        .opacity(heard ? 0.9 : 0)
                    Text(Self.label(hit.kind))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Theme.courtDeep)
                        .frame(width: 34, height: 34)
                        .background(Self.color(hit.kind), in: Circle())
                        .position(x: x, y: 17)
                        .scaleEffect(heard ? 1 : 0.2, anchor: .bottom)
                        .opacity(heard ? 1 : 0)
                        .animation(.spring(duration: 0.35, bounce: 0.45), value: heard)
                }
                Rectangle()
                    .fill(Theme.ball)
                    .frame(width: 3, height: h * 0.82)
                    .position(x: w * CGFloat(progress), y: midY)
                    .opacity(progress < 1 ? 1 : 0)
            }
        }
    }

    /// A made-up but tennis-shaped soundtrack: a low bed of court noise with
    /// a sharp spike at each hit and a smaller one for each bounce.
    private static func amplitude(_ i: Int) -> CGFloat {
        let bed = 0.12 + 0.08 * abs(sin(Double(i) * 1.7)) + 0.05 * abs(sin(Double(i) * 0.37))
        for hit in hits {
            if i == hit.bar { return 1 }
            if abs(i - hit.bar) == 1 { return 0.55 }
            if i == hit.bar + 4 { return 0.42 }   // the bounce on the other side
        }
        return CGFloat(bed)
    }

    static func color(_ kind: StrokeKind) -> Color {
        switch kind {
        case .serve: return Theme.ball
        case .forehand: return Theme.onboardingBody
        case .backhand, .groundstroke: return Theme.clay
        }
    }

    private static func label(_ kind: StrokeKind) -> String {
        switch kind {
        case .serve: return "S"
        case .forehand: return "FH"
        case .backhand: return "BH"
        case .groundstroke: return "G"
        }
    }
}

// MARK: - 6. Filming tips

struct TipsVisual: View {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    private let tips: [(symbol: String, title: String, detail: String)] = [
        ("figure.tennis", "Whole body in frame", "Feet included, for the entire rally."),
        ("iphone.gen3.landscape", "Side-on for angles", "Knee and elbow angles are graded when the camera sees the limb from the side."),
        ("speaker.wave.2.fill", "Sound on", "The sound of the ball is what times each stroke."),
    ]

    var body: some View {
        FitToSize(design: CGSize(width: 380, height: 420)) {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(Array(tips.enumerated()), id: \.offset) { i, tip in
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        Image(systemName: tip.symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.courtDeep)
                            .frame(width: 56, height: 56)
                            .background(Theme.ball, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title).font(.headline).foregroundStyle(.white)
                            Text(tip.detail)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Spacing.m)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.14)))
                    .opacity(shown > i ? 1 : 0)
                    .offset(x: shown > i ? 0 : 40)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .task(id: active) {
            guard active else { shown = 0; return }
            if reduceMotion { shown = tips.count; return }
            for i in 1...tips.count {
                try? await Task.sleep(for: .milliseconds(i == 1 ? 250 : 180))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.2)) { shown = i }
            }
        }
    }
}
