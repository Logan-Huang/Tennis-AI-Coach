//
//  CompareView.swift
//  Tennis AI Coach
//
//  Before/after session comparison. The dual-color system is consistent
//  everywhere: clay = before, court = after (Theme.before / Theme.after).
//  V1 is stats + findings; synced side-by-side video is out of scope.
//

import SwiftUI

struct CompareView: View {
    let beforeSession: Session
    let afterSession: Session

    @Environment(LibraryStore.self) private var store

    private var report: CompareEngine.CompareReport {
        CompareEngine.report(
            before: store.scores(for: beforeSession).shots,
            after: store.scores(for: afterSession).shots)
    }

    var body: some View {
        let report = self.report

        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header(report)

                if report.formDelta == nil {
                    Text("One of these sessions couldn't be graded, so form scores can't be compared.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !report.components.isEmpty {
                    componentSection(report)
                }

                if !report.transitions.isEmpty {
                    transitionSection(report)
                }

                Text("Form only — swing speed isn't comparable across differently filmed sessions. Camera angle changes can shift angle estimates.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private func header(_ report: CompareEngine.CompareReport) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                sideColumn(title: "Before", date: beforeSession.createdAt,
                           summary: report.before, tint: Theme.before)
                VStack(spacing: Theme.Spacing.xs) {
                    if let delta = report.formDelta {
                        DeltaChip(delta: delta)
                    }
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                sideColumn(title: "After", date: afterSession.createdAt,
                           summary: report.after, tint: Theme.after)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func sideColumn(title: String, date: Date,
                            summary: CompareEngine.SideSummary, tint: Color) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(tint)
            ScoreRing(score: summary.formScore, size: .card, overrideColor: tint,
                      accessibilityTitle: "\(title) form score")
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(summary.gradedShots == 1 ? "1 swing" : "\(summary.gradedShots) swings")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Component pairs

    private func componentSection(_ report: CompareEngine.CompareReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Form components")
            ForEach(report.components) { pair in
                componentPairRow(pair)
            }
        }
        .cardStyle()
    }

    private func componentPairRow(_ pair: CompareEngine.ComponentPair) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(pair.kind.displayName).microLabel()
                Spacer()
                if let delta = pair.delta {
                    DeltaChip(delta: delta)
                }
            }
            pairTrack(score: pair.beforeScore, raw: rawText(pair.kind, pair.beforeRaw), tint: Theme.before)
            pairTrack(score: pair.afterScore, raw: rawText(pair.kind, pair.afterRaw), tint: Theme.after)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pair.kind.displayName): before \(Fmt.score(pair.beforeScore)), after \(Fmt.score(pair.afterScore))")
    }

    private func pairTrack(score: Double, raw: String, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    if score.isFinite {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(6, geo.size.width * score / 100))
                    }
                }
            }
            .frame(height: 6)
            Text(score.isFinite ? "\(Fmt.score(score)) · \(raw)" : "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .trailing)
        }
    }

    private func rawText(_ kind: ShotScoreComponent.Kind, _ raw: Double) -> String {
        guard raw.isFinite else { return "—" }
        switch kind {
        case .kneeBend, .torsoStability, .elbowExtension: return Fmt.deg(raw)
        case .stanceWidth: return String(format: "%.2f×", raw)
        case .prepFollowThrough: return "\(Int((raw * 100).rounded()))%"
        case .swingSpeed: return "—"
        }
    }

    // MARK: - Finding transitions

    private func transitionSection(_ report: CompareEngine.CompareReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "Findings")
            ForEach(report.transitions) { t in
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: t.improved ? "arrow.down.right" : "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(t.improved ? Theme.good : Theme.watch)
                        .accessibilityHidden(true)
                    Text(t.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("\(t.beforeAffected)/\(t.beforeTotal) → \(t.afterAffected)/\(t.afterTotal)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }
}
