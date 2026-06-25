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
    var unit: String? = nil
    var systemImage: String = "gauge.with.dots.needle.bottom.50percent"
    var tint: Color = Theme.court

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
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
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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

// MARK: - Empty state

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 46))
                .foregroundStyle(Theme.court.gradient)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.court)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func deg(_ x: Double) -> String { x.isFinite ? String(format: "%.0f°", x) : "—" }
    static func deg1(_ x: Double) -> String { x.isFinite ? String(format: "%.1f°", x) : "—" }
    static func ratio(_ x: Double) -> String { x.isFinite ? String(format: "%.2f", x) : "—" }
    static func speed(_ x: Double) -> String { x.isFinite ? String(format: "%.0f", x) : "—" }
    static func seconds(_ x: Double) -> String { x.isFinite ? String(format: "%.1fs", x) : "—" }
    static func time(_ x: Double) -> String {
        guard x.isFinite else { return "—" }
        let m = Int(x) / 60, s = Int(x) % 60
        return String(format: "%d:%02d", m, s)
    }
}
