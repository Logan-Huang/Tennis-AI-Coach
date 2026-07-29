//
//  ScoreComponents.swift
//  Tennis AI Coach
//
//  The score visual language: rings, chips, bars, tri-stats. Band color is
//  the ONLY color semantics here — grays for confidence, no decoration.
//

import SwiftUI

// MARK: - Band color mapping

extension ScoreBand {
    var color: Color {
        switch self {
        case .excellent: return Theme.good
        case .solid: return Theme.courtLight
        case .developing: return Theme.watch
        case .workOn: return Theme.focus
        case .ungraded: return .secondary
        }
    }
}

// MARK: - Score ring

/// Band-colored circular score ring. `—` when ungraded.
struct ScoreRing: View {
    enum Size {
        case row, card, hero

        var diameter: CGFloat {
            switch self {
            case .row: return 40
            case .card: return 56
            case .hero: return 96
            }
        }
        var lineWidth: CGFloat {
            switch self {
            case .row: return 4
            case .card: return 5
            case .hero: return 8
            }
        }
        var font: Font {
            switch self {
            case .row: return .system(.subheadline, design: .rounded).weight(.bold)
            case .card: return .system(.title3, design: .rounded).weight(.bold)
            case .hero: return .system(.largeTitle, design: .rounded).weight(.bold)
            }
        }
    }

    var score: Double
    var size: Size = .card
    /// Hero only: show the band word under the ring.
    var showBandLabel: Bool = false
    /// Overrides band color (e.g. white on the gradient hero zone, where
    /// band colors lack contrast; the band word still names the band).
    var overrideColor: Color? = nil
    /// VoiceOver title — "Session score" on the report hero, default elsewhere.
    var accessibilityTitle: String = "Form score"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var band: ScoreBand { ScoreBand(score: score) }
    private var ringColor: Color { overrideColor ?? band.color }
    private var diameter: CGFloat { size.diameter * min(scale, 1.6) }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.18), lineWidth: size.lineWidth)
                Circle()
                    .trim(from: 0, to: score.isFinite ? max(0.02, score / 100) : 0)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Theme.motion(.snappy, reduceMotion: reduceMotion), value: score)
                Text(Fmt.score(score))
                    .font(size.font)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(overrideColor ?? (score.isFinite ? Color.primary : Color.secondary))
            }
            .frame(width: diameter, height: diameter)

            if showBandLabel {
                Text(band.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ringColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(score.isFinite ? "\(Int(score.rounded())), \(band.label)" : "Not graded")
    }
}

// MARK: - Confidence chip

/// Tracking-confidence indicator. Deliberately gray — color is reserved for
/// score bands.
struct ConfidenceChip: View {
    var level: ConfidenceLevel

    var body: some View {
        Text(level.label)
            .microLabel()
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .accessibilityLabel(level.label)
    }
}

// MARK: - Delta chip

/// Session-over-session change: green up, red down, neutral placeholder.
struct DeltaChip: View {
    /// `nil` → first-session placeholder ("—").
    var delta: Double?

    private var text: String {
        guard let delta, delta.isFinite else { return "—" }
        let v = Int(delta.rounded())
        return v > 0 ? "+\(v)" : "\(v)"
    }

    private var tint: Color {
        guard let delta, delta.isFinite, delta != 0 else { return .secondary }
        return delta > 0 ? Theme.good : Theme.focus
    }

    var body: some View {
        HStack(spacing: 2) {
            if let delta, delta.isFinite, delta != 0 {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(tint.opacity(0.12), in: Capsule())
        .accessibilityLabel(delta.map { $0 >= 0 ? "up \(Int($0.rounded()))" : "down \(Int(abs($0).rounded()))" } ?? "no previous session")
    }
}

// MARK: - Tri-stat row (Best / Average / Worst)

struct TriStatRow: View {
    var best: Double
    var average: Double
    var worst: Double

    var body: some View {
        HStack(spacing: 0) {
            stat("Best", best)
            divider
            stat("Average", average)
            divider
            stat("Worst", worst)
        }
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5, height: 32)
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(Fmt.score(value))
                .font(.stat)
                .monospacedDigit()
                .foregroundStyle(ScoreBand(score: value).color)
            Text(label)
                .microLabel()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Component bar row

/// One score component: micro-label name, thin band-colored track, raw value.
struct ComponentBarRow: View {
    var name: String
    var score: Double       // 0–100 or NaN (not measurable)
    var rawText: String     // "132°", "0.98", "—"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var band: ScoreBand { ScoreBand(score: score) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).microLabel()
                Spacer()
                if score.isFinite {
                    Text(rawText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(Fmt.score(score))
                        .font(.callout.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(band.color)
                } else {
                    Text("not measurable in this clip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    if score.isFinite {
                        Capsule()
                            .fill(band.color)
                            .frame(width: max(6, geo.size.width * score / 100))
                            .animation(Theme.motion(.snappy, reduceMotion: reduceMotion), value: score)
                    }
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(score.isFinite ? "\(Int(score.rounded())) of 100, \(rawText)" : "not measurable")
    }
}

// MARK: - Target vs you pill

struct TargetVsYouPill: View {
    var target: String
    var you: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Group {
                Text("Target ") + Text(target).bold()
            }
            Rectangle().fill(Color(.separator)).frame(width: 0.5, height: 12)
            Group {
                Text("You ") + Text(you).bold()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s - 2)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Range band row (Home trends)

/// A muted track with a lighter band spanning the recent min–max and a tick
/// at the current value. Compact alternative to a sparkline.
struct RangeBandRow: View {
    var label: String
    var domain: ClosedRange<Double>       // full track extent
    var range: ClosedRange<Double>?       // recent min–max; nil = placeholder
    var current: Double                   // NaN = placeholder tick
    var currentText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label).microLabel()
                Spacer()
                Text(currentText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(current.isFinite ? .primary : .secondary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    if let range {
                        Capsule()
                            .fill(Theme.court.opacity(0.25))
                            .frame(width: max(6, w * frac(range.upperBound) - w * frac(range.lowerBound)))
                            .offset(x: w * frac(range.lowerBound))
                    }
                    if current.isFinite {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.court)
                            .frame(width: 3, height: 14)
                            .offset(x: max(0, min(w - 3, w * frac(current))))
                    }
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(current.isFinite ? currentText : "no data yet")
    }

    private func frac(_ x: Double) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (x - domain.lowerBound) / span)))
    }
}

// MARK: - Previews

#Preview("Score components", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        HStack(spacing: Theme.Spacing.l) {
            ScoreRing(score: 94, size: .row)
            ScoreRing(score: 72, size: .card)
            ScoreRing(score: 48, size: .card)
            ScoreRing(score: .nan, size: .card)
        }
        ScoreRing(score: 84, size: .hero, showBandLabel: true)
        HStack {
            ConfidenceChip(level: .high)
            ConfidenceChip(level: .medium)
            ConfidenceChip(level: .low)
        }
        HStack {
            DeltaChip(delta: 6)
            DeltaChip(delta: -3)
            DeltaChip(delta: nil)
        }
        TriStatRow(best: 94, average: 84, worst: 62)
        ComponentBarRow(name: "Knee bend", score: 84, rawText: "132°")
        ComponentBarRow(name: "Stance width", score: .nan, rawText: "—")
        TargetVsYouPill(target: "110–155°", you: "162°")
        RangeBandRow(label: "Knee bend", domain: 80...180, range: 115...150, current: 132, currentText: "132°")
        RangeBandRow(label: "Torso lean", domain: 0...45, range: nil, current: .nan, currentText: "—")
    }
    .padding()
}
