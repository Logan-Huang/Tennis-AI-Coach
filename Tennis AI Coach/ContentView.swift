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

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .processing(let url):
                        ProcessingView(videoURL: url)
                    case .results(let id):
                        if let session = store.session(id: id) {
                            ResultsView(session: session)
                        } else {
                            EmptyStateView(
                                systemImage: "questionmark.folder",
                                title: "Session not found",
                                message: "This analysis is no longer available.")
                        }
                    }
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppRouter())
        .environment(LibraryStore())
}
