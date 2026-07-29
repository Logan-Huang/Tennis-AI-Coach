//
//  OnboardingView.swift
//  Tennis AI Coach
//
//  First launch only: the three things that actually improve results.
//  No marketing fluff — setup instructions and the privacy promise.
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0

    private let pages: [(symbol: String, title: String, message: String)] = [
        ("iphone.landscape",
         "Film side-on",
         "Set your phone level with the baseline, pointing across the court. Angles are measured in 2D — a side view is what makes them meaningful."),
        ("figure.tennis",
         "Whole body, good light",
         "Keep your full body in frame for the entire rally. The clearer the skeleton tracking, the more swings get scored."),
        ("gauge.with.needle",
         "Swing, then read your report",
         "Every swing gets a form score with a component breakdown, and sessions build a trend over time. Everything runs on your phone — no upload, no account, no analysis cap."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: Theme.Spacing.l) {
                        Spacer()
                        Image(systemName: item.symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.court)
                            .symbolEffect(.bounce, options: .nonRepeating, value: page)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.title2.weight(.bold))
                        Text(item.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Get started")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionButton()
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.l)

            if page < pages.count - 1 {
                Button("Skip") { onDone() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Theme.Spacing.m)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.selection, trigger: page)
    }
}

#Preview {
    OnboardingView(onDone: {})
}
