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
            // Debug hooks (UI verification in the Simulator, where taps can't
            // be injected). No-ops otherwise.
            //   `-activeProfile <name>`           switch player at launch
            //   `-autoOpenSession <uuid|newest>`  jump to a session's report
            //                                     (a uuid switches to its player)
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            if let name = value("-activeProfile"),
               let profile = store.profiles.first(where: {
                   $0.displayName.caseInsensitiveCompare(name) == .orderedSame
               }) {
                store.switchTo(profile)
            }
            guard let key = value("-autoOpenSession") else { return }
            if key == "newest" {
                if let target = store.sessions.first { router.showResults(target.id) }
            } else if let id = UUID(uuidString: key), let target = store.session(id: id) {
                if let owner = store.profiles.first(where: { $0.id == target.profileID }) {
                    store.switchTo(owner)
                }
                router.showResults(target.id)
            }
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
