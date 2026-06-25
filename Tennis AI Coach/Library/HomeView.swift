//
//  HomeView.swift
//  Tennis AI Coach
//

import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var store

    @State private var showImport = false
    @State private var showRecord = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                HStack(spacing: 14) {
                    actionButton(title: "Record", subtitle: "Film a session",
                                 systemImage: "camera.fill", tint: Theme.clay) {
                        showRecord = true
                    }
                    actionButton(title: "Import", subtitle: "From your library",
                                 systemImage: "square.and.arrow.down", tint: Theme.court) {
                        showImport = true
                    }
                }
                .padding(.horizontal)

                librarySection
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tennis AI Coach")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImport) {
            ImportSheet { url in
                showImport = false
                router.startProcessing(url)
            }
        }
        .fullScreenCover(isPresented: $showRecord) {
            RecordView { url in
                showRecord = false
                router.startProcessing(url)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.tennis")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            Text("Analyze your strokes")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text("Record or import a clip and get instant, pose-based coaching on your form.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }

    private func actionButton(title: String, subtitle: String, systemImage: String,
                              tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var librarySection: some View {
        if store.sessions.isEmpty {
            EmptyStateView(
                systemImage: "figure.tennis",
                title: "No sessions yet",
                message: "Your analyzed sessions will appear here. Record or import a clip to get started.")
                .padding(.top, 30)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent sessions")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(store.sessions) { session in
                    Button {
                        router.showResults(session.id)
                    } label: {
                        SessionCard(session: session)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(session)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AppRouter())
            .environment(LibraryStore())
    }
}
