//
//  Theme.swift
//  Tennis AI Coach
//
//  Visual language: tennis-court greens with a warm clay accent.
//

import SwiftUI

enum Theme {
    // Brand
    static let court = Color(red: 0.10, green: 0.44, blue: 0.30)
    static let courtDeep = Color(red: 0.06, green: 0.30, blue: 0.21)
    static let courtLight = Color(red: 0.22, green: 0.60, blue: 0.42)
    static let clay = Color(red: 0.87, green: 0.43, blue: 0.25)
    static let accent = court

    // Status
    static let good = Color(red: 0.18, green: 0.62, blue: 0.40)
    static let watch = Color(red: 0.92, green: 0.66, blue: 0.20)
    static let focus = Color(red: 0.85, green: 0.34, blue: 0.27)

    // Surfaces
    static let surface = Color(.secondarySystemBackground)
    static let surfaceElevated = Color(.tertiarySystemBackground)

    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [courtDeep, court],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var ballGradient: LinearGradient {
        LinearGradient(
            colors: [courtLight, court],
            startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// Standard rounded card chrome.
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
