//
//  Buttons.swift
//  Tennis AI Coach
//
//  The app's two button treatments. Liquid Glass is chrome-layer only —
//  buttons qualify; content surfaces never do.
//

import SwiftUI

extension View {
    /// The one primary action per screen: prominent glass, court tint.
    func primaryActionButton() -> some View {
        self
            .buttonStyle(.glassProminent)
            .tint(Theme.court)
            .controlSize(.large)
    }

    /// Secondary actions: plain glass, same metrics.
    func secondaryActionButton() -> some View {
        self
            .buttonStyle(.glass)
            .controlSize(.large)
    }
}

#Preview("Buttons", traits: .sizeThatFitsLayout) {
    VStack(spacing: Theme.Spacing.m) {
        Button("Record a session") {}
            .primaryActionButton()
        Button("Import from Photos") {}
            .secondaryActionButton()
        HStack(spacing: Theme.Spacing.m) {
            Button("Analyze") {}.primaryActionButton()
            Button("Retake") {}.secondaryActionButton()
        }
    }
    .padding(Theme.Spacing.xl)
}
