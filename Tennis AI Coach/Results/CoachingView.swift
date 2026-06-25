//
//  CoachingView.swift
//  Tennis AI Coach
//

import SwiftUI

struct CoachingView: View {
    let report: CoachingReport
    let summary: AnalysisSummary
    let hittingArm: HittingArm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !report.good.isEmpty {
                    section(title: "What looks good", symbol: "checkmark.seal.fill", tint: Theme.good) {
                        ForEach(Array(report.good.enumerated()), id: \.offset) { _, text in
                            FeedbackCard(text: text, kind: .good)
                        }
                    }
                }

                section(title: "Focus next", symbol: "target", tint: Theme.focus) {
                    ForEach(Array(report.focus.enumerated()), id: \.offset) { _, text in
                        FeedbackCard(text: text, kind: .focus)
                    }
                }

                if report.good.isEmpty && report.focus.isEmpty {
                    EmptyStateView(
                        systemImage: "text.bubble",
                        title: "No coaching available",
                        message: "There wasn't enough clear pose data to generate feedback.")
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, symbol: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            content()
        }
    }
}
