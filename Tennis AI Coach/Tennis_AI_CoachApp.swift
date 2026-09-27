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
    /// Set once the player has been named — by onboarding for a new install,
    /// or by the one-time "Your Profile" sheet for someone updating from
    /// before there were players.
    @AppStorage("hasSeenProfilesIntro") private var hasSeenProfilesIntro = false
    private let engine = VisionAnalysisEngine()

    init() {
        Attribution.configure()
    }

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
                    OnboardingView {
                        hasSeenOnboarding = true
                        hasSeenProfilesIntro = true
                        Attribution.onboardingDidFinish()
                    }
                    .environment(store)
                    .tint(Theme.court)
                }
                .sheet(isPresented: Binding(
                    get: { hasSeenOnboarding && !hasSeenProfilesIntro },
                    set: { if !$0 { hasSeenProfilesIntro = true } })) {
                    ProfileEditorView(mode: .firstRun(store.activeProfile)) {
                        hasSeenProfilesIntro = true
                    }
                    .environment(store)
                    .tint(Theme.court)
                }
        }
    }
}
