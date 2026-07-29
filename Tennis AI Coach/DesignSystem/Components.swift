//
//  Components.swift
//  Tennis AI Coach
//
//  Reusable UI building blocks.
//

import SwiftUI

// MARK: - Metric card

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    var unit: String? = nil
    var tint: Color = Theme.court

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .microLabel()
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.stat)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Feedback card

struct FeedbackCard: View {
    enum Kind { case good, focus }
    let text: String
    let kind: Kind

    private var tint: Color { kind == .good ? Theme.good : Theme.focus }
    private var symbol: String { kind == .good ? "checkmark.seal.fill" : "target" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Score badge

struct ScoreBadge: View {
    let text: String
    var tint: Color = Theme.court

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(title).microLabel()
            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func deg(_ x: Double) -> String { x.isFinite ? String(format: "%.0f°", x) : "—" }
    static func deg1(_ x: Double) -> String { x.isFinite ? String(format: "%.1f°", x) : "—" }
    static func ratio(_ x: Double) -> String { x.isFinite ? String(format: "%.2f", x) : "—" }
    static func speed(_ x: Double) -> String { x.isFinite ? String(format: "%.0f", x) : "—" }
    /// Integer form score; "—" when ungraded. Never decimals — pixel-derived
    /// data cannot honestly support them.
    static func score(_ x: Double) -> String { x.isFinite ? String(Int(x.rounded())) : "—" }
    /// Session-relative swing speed: "92% of your fastest". Never px/s or mph.
    static func relSpeed(_ ratio: Double) -> String {
        ratio.isFinite ? "\(Int((ratio * 100).rounded()))% of your fastest" : "—"
    }
    static func seconds(_ x: Double) -> String { x.isFinite ? String(format: "%.1fs", x) : "—" }
    static func time(_ x: Double) -> String {
        guard x.isFinite else { return "—" }
        let m = Int(x) / 60, s = Int(x) % 60
        return String(format: "%d:%02d", m, s)
    }
}
