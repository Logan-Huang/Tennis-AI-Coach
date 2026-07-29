//
//  AppShell.swift
//  Tennis AI Coach
//
//  Navigation router, route definitions, and the analysis-engine environment.
//

import SwiftUI

// MARK: - Routes

enum Route: Hashable {
    case processing(videoURL: URL)
    case results(sessionID: UUID)
    case compare(beforeID: UUID, afterID: UUID)
}

@Observable
@MainActor
final class AppRouter {
    var path: [Route] = []

    func startProcessing(_ url: URL) {
        path.append(.processing(videoURL: url))
    }

    /// Replace the whole stack with the results screen so Back returns Home.
    func showResults(_ id: UUID) {
        path = [.results(sessionID: id)]
    }

    func showCompare(beforeID: UUID, afterID: UUID) {
        path.append(.compare(beforeID: beforeID, afterID: afterID))
    }
}

// MARK: - Engine environment

extension EnvironmentValues {
    @Entry var analysisEngine: AnalysisEngine = MockEngine()
}
