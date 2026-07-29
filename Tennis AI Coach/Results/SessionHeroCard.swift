//
//  SessionHeroCard.swift
//  Tennis AI Coach
//
//  The Session Report's single focal point: the two-zone hero. Court-gradient
//  identity zone (headline + hero ring) over a light stat shelf (Best/Avg/Worst).
//  Replaces the duplicated gradient banners that HomeView and OverviewView
//  used to hand-roll separately.
//

import SwiftUI

struct SessionHeroCard: View {
    let session: SessionScore
    let headline: String

    var body: some View {
        VStack(spacing: 0) {
            gradientZone
            statShelf
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var gradientZone: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                // "Session score" (includes swing speed) — deliberately
                // distinct from Home's speed-excluded "Form score" trend.
                Text("Session score")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))

                Text(headline)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Spacing.s) {
                    Text(gradedText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    if session.isProvisional && session.overall.isFinite {
                        Text("Provisional")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.18), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // White ring on the gradient — band colors lack contrast here;
            // the band word and the tri-stat below carry the semantics.
            ScoreRing(score: session.overall, size: .hero,
                      showBandLabel: true, overrideColor: .white,
                      accessibilityTitle: "Session score")
        }
        .padding(Theme.Spacing.l)
        .background(Theme.headerGradient)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statShelf: some View {
        if session.gradedShots > 0 {
            TriStatRow(best: session.best, average: session.average, worst: session.worst)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.surface)
        }
    }

    private var gradedText: String {
        if session.gradedShots == 0 {
            return "No swings could be graded"
        }
        if session.gradedShots == session.totalShots {
            return "Graded all \(session.totalShots) swings"
        }
        return "Graded \(session.gradedShots) of \(session.totalShots) swings"
    }
}

#Preview("Hero card", traits: .sizeThatFitsLayout) {
    VStack(spacing: Theme.Spacing.l) {
        SessionHeroCard(
            session: SessionScore(overall: 84, consistency: 84, gradedShots: 3, totalShots: 3,
                                  best: 94, average: 86, worst: 79,
                                  bestShotId: 2, worstShotId: 1),
            headline: "Swing 2 was your best at 94 — knee bend was your steadiest strength.")
        SessionHeroCard(
            session: SessionScore(overall: .nan, consistency: .nan, gradedShots: 0, totalShots: 2,
                                  best: .nan, average: .nan, worst: .nan,
                                  bestShotId: nil, worstShotId: nil),
            headline: "Not enough tracking to grade this session — film side-on with your full body in frame.")
    }
    .padding()
}
