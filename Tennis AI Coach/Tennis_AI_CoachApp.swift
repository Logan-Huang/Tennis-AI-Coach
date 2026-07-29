//
//  Tennis_AI_CoachApp.swift
//  Tennis AI Coach
//
//  Created by Logan Huang on 6/4/26.
//

import SwiftUI

@main
struct Tennis_AI_CoachApp: App {
    @State private var router = AppRouter()
    @State private var store = LibraryStore()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    private let engine = VisionAnalysisEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .environment(store)
                .environment(\.analysisEngine, engine)
                .tint(Theme.court)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { if !$0 { hasSeenOnboarding = true } })) {
                    OnboardingView { hasSeenOnboarding = true }
                }
        }
    }
}
