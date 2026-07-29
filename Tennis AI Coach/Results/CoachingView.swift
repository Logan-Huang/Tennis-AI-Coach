//
//  CoachingView.swift
//  Tennis AI Coach
//
//  Coaching inside the Session Report: one Focus-next priority (with
//  target-vs-you), flaw-frequency findings, and strengths collapsed into a
//  compact checklist — no more wall of identical cards.
//

import SwiftUI

struct CoachingSection: View {
    let focus: Narrative.Focus?
    let findings: [FindingCount]
    let report: CoachingReport

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let focus {
                focusCard(focus)
            }

            if !findings.isEmpty {
                findingsCard
            }

            if !report.good.isEmpty {
                strengthsCard
            }

            if focus == nil && findings.isEmpty && report.good.isEmpty {
                ContentUnavailableView {
                    Label("No coaching available", systemImage: "text.bubble")
                } description: {
                    Text("There wasn't enough clear pose data to generate feedback.")
                }
            }
        }
    }

    // MARK: - Focus next (the one priority)

    private func focusCard(_ focus: Narrative.Focus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "Focus next")
            Text(focus.sentence)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            TargetVsYouPill(target: focus.targetText, you: focus.youText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.focus.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.focus.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Findings with frequency pills

    private var findingsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "Across your swings")
            ForEach(findings) { finding in
                HStack(spacing: Theme.Spacing.m - 4) {
                    Text(finding.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("\(finding.affectedShots)/\(finding.totalGradedShots)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.watch.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.watch)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(finding.text), \(finding.affectedShots) of \(finding.totalGradedShots) swings")
            }
        }
        .cardStyle()
    }

    // MARK: - Strengths (compact checklist)

    private var strengthsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "What looks good")
            ForEach(Array(report.good.enumerated()), id: \.offset) { _, text in
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.good)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
