//
//  ContentView.swift
//  Tennis AI Coach
//
//  Created by Logan Huang on 6/4/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var store

    @Namespace private var sessionZoom

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView(zoomNamespace: sessionZoom)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .processing(let url):
                        ProcessingView(videoURL: url)
                    case .results(let id):
                        if let session = store.session(id: id) {
                            ResultsView(session: session)
                                .navigationTransition(.zoom(sourceID: id, in: sessionZoom))
                        } else {
                            ContentUnavailableView {
                                Label("Session not found", systemImage: "questionmark.folder")
                            } description: {
                                Text("This analysis is no longer available.")
                            }
                        }
                    case .compare(let beforeID, let afterID):
                        if let before = store.session(id: beforeID),
                           let after = store.session(id: afterID) {
                            CompareView(beforeSession: before, afterSession: after)
                        } else {
                            ContentUnavailableView {
                                Label("Session not found", systemImage: "questionmark.folder")
                            } description: {
                                Text("One of these analyses is no longer available.")
                            }
                        }
                    }
                }
        }
        .task {
            // Debug hook: `-autoOpenSession <uuid|newest>` launch argument
            // jumps straight to a session's report (UI verification in the
            // Simulator, where taps can't be injected). No-op otherwise.
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-autoOpenSession"), i + 1 < args.count else { return }
            let key = args[i + 1]
            let target = key == "newest"
                ? store.sessions.first
                : store.sessions.first { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame }
            if let target { router.showResults(target.id) }
        }
        .task {
            // Debug hook: `-autoCompareLatest` opens the compare screen for
            // the two most recent sessions (Simulator verification only).
            guard ProcessInfo.processInfo.arguments.contains("-autoCompareLatest"),
                  store.sessions.count >= 2 else { return }
            let a = store.sessions[0], b = store.sessions[1]
            let (before, after) = a.createdAt < b.createdAt ? (a, b) : (b, a)
            router.showCompare(beforeID: before.id, afterID: after.id)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppRouter())
        .environment(LibraryStore())
}
