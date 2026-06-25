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
}

// MARK: - Engine environment

private struct AnalysisEngineKey: EnvironmentKey {
    static let defaultValue: AnalysisEngine = MockEngine()
}

extension EnvironmentValues {
    var analysisEngine: AnalysisEngine {
        get { self[AnalysisEngineKey.self] }
        set { self[AnalysisEngineKey.self] = newValue }
    }
}
