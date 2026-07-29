//
//  HomeView.swift
//  Tennis AI Coach
//
//  The progress dashboard: your numbers first (latest form score + delta),
//  the trend, then capture actions and the session library. Marketing-banner
//  hero deleted — the product's own data is the hero now.
//

import SwiftUI

struct HomeView: View {
    let zoomNamespace: Namespace.ID

    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var store

    @State private var showImport = false
    @State private var showRecord = false
    @State private var showComparePicker = false
    @State private var sessionToDelete: Session?

    // Computed off the first render via .task — scoring is cheap but not free.
    @State private var trend: [ProgressEngine.SessionProgress] = []
    @State private var componentTrends: [ProgressEngine.ComponentTrend] = []

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if store.sessions.isEmpty {
                    EmptyLibraryState(onRecord: { showRecord = true })
                        .padding(.top, Theme.Spacing.xl)
                } else {
                    heroStrip
                    TrendCard(trend: trend, componentTrends: componentTrends)
                }

                actionRow

                if store.sessions.count >= 2 {
                    compareRow
                }

                if !store.sessions.isEmpty {
                    sessionList
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tennis AI Coach")
        .navigationBarTitleDisplayMode(.large)
        .task(id: store.sessions.count) {
            trend = store.progressTrend()
            componentTrends = store.componentTrends()
        }
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
        .sheet(isPresented: $showComparePicker) {
            ComparePickerSheet { beforeID, afterID in
                router.showCompare(beforeID: beforeID, afterID: afterID)
            }
            .environment(store)
        }
        .confirmationDialog("Delete this session?",
                            isPresented: Binding(
                                get: { sessionToDelete != nil },
                                set: { if !$0 { sessionToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    withAnimation(.snappy) { store.delete(session) }
                }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        } message: {
            Text("The video and its analysis are removed from your library.")
        }
    }

    // MARK: - Hero strip (your numbers first)

    private var heroStrip: some View {
        let latest = trend.last(where: { $0.formScore.isFinite })
        let delta = ProgressEngine.latestDelta(trend)

        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Form score")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.7))

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Text(Fmt.score(latest?.formScore ?? .nan))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                if let delta {
                    DeltaChip(delta: delta)
                }

                Spacer(minLength: 0)

                if let latest {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(latest.date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(latest.gradedShots == 1 ? "1 swing graded" : "\(latest.gradedShots) swings graded")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }

            Text(subline)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .background(Theme.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subline: String {
        let graded = trend.filter { $0.formScore.isFinite }
        if graded.isEmpty {
            return "Sessions couldn't be graded yet — film side-on with your full body in frame."
        }
        if graded.count == 1 {
            return "Record another session to see your form trend."
        }
        if let delta = ProgressEngine.latestDelta(trend) {
            if delta > 1 { return "Form is trending up — keep the base compact and swing free." }
            if delta < -1 { return "A dip from last session — worth rewatching your lowest swings." }
            return "Holding steady across your last sessions."
        }
        return "Your last \(graded.count) sessions are scored below."
    }

    // MARK: - Actions (one primary)

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                showRecord = true
            } label: {
                Label("Record", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionButton()

            Button {
                showImport = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .secondaryActionButton()
        }
        .accessibilityHint("Record films a new session; Import picks a clip from your library")
    }

    // MARK: - Compare

    private var compareRow: some View {
        Button {
            showComparePicker = true
        } label: {
            HStack {
                Label("Compare two sessions", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .interactiveCardStyle()
        }
        .buttonStyle(CardButtonStyle())
    }

    // MARK: - Sessions

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            SectionHeader(title: "Recent sessions", count: store.sessions.count)

            ForEach(store.sessions) { session in
                Button {
                    router.showResults(session.id)
                } label: {
                    SessionCard(session: session,
                                score: store.scores(for: session).session.overall)
                }
                .buttonStyle(CardButtonStyle())
                .matchedTransitionSource(id: session.id, in: zoomNamespace)
                .contextMenu {
                    Button(role: .destructive) {
                        sessionToDelete = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .animation(.snappy, value: store.sessions.count)
    }
}

#Preview {
    @Previewable @Namespace var ns
    NavigationStack {
        HomeView(zoomNamespace: ns)
            .environment(AppRouter())
            .environment(LibraryStore())
    }
}
