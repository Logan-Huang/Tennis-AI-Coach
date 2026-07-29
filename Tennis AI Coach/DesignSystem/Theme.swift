//
//  Theme.swift
//  Tennis AI Coach
//
//  Visual language: tennis-court greens with a warm clay accent.
//  All brand colors live in the asset catalog with tuned Dark variants;
//  spacing/radius come from the token scales below — no magic numbers in views.
//

import SwiftUI

enum Theme {
    // MARK: Brand (asset catalog, Any/Dark appearances)

    static let court = Color(.court)
    static let courtDeep = Color(.courtDeep)
    static let courtLight = Color(.courtLight)
    static let clay = Color(.clay)
    static let accent = court

    // MARK: Status — semantic only, never decorative

    static let good = Color(.good)
    static let watch = Color(.watch)
    static let focus = Color(.focus)

    // MARK: Comparison pair (session compare: before vs after)

    static let before = clay
    static let after = court

    // MARK: Surfaces
    // Grouped variants: white cards on the gray grouped page in light mode,
    // elevated grays on black in dark. (The non-grouped tokens render nearly
    // identical to the page background in light mode — invisible cards.)

    static let surface = Color(.secondarySystemGroupedBackground)
    static let surfaceElevated = Color(.tertiarySystemGroupedBackground)

    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [courtDeep, court],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Spacing scale — 4/8pt grid; the only padding values views may use

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: Radius tokens — one card radius everywhere

    enum Radius {
        static let card: CGFloat = 16
        static let thumb: CGFloat = 10
        // Chips/pills are capsules; no token needed.
    }

    /// Haptic vocabulary (single source of truth — see call sites):
    ///   .success   → analysis complete, export complete. Nothing else.
    ///   .selection → section chips, stroke seek, filter/scope changes.
    ///   .impact    → record start/stop.
    ///   Never on scroll or per-frame events.

    /// Returns `nil` under Reduce Motion so `.animation(_:value:)` call sites
    /// degrade to crossfades/no-ops without per-view boilerplate.
    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Typography

extension Font {
    /// Hero numerals (score rings, dashboard). Rounded + bold.
    static let statLarge = Font.system(.largeTitle, design: .rounded).weight(.bold)
    /// Standard stat numerals (metric cards, rows).
    static let stat = Font.system(.title2, design: .rounded).weight(.semibold)
}

extension View {
    /// The app's one signature typographic treatment: tiny uppercase
    /// letterspaced captions above stats ("FORM SCORE", "RANGE").
    func microLabel() -> some View {
        self
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Surfaces

extension View {
    /// Standard rounded card chrome for static content.
    func cardStyle(padding: CGFloat = Theme.Spacing.m) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// Card chrome for tappable surfaces: hairline border + soft shadow so
    /// interactive cards read as interactive. Pair with `CardButtonStyle`.
    func interactiveCardStyle(padding: CGFloat = Theme.Spacing.m) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.court.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

/// Press feedback for card-shaped buttons: subtle scale with a snappy spring.
struct CardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
