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
    @State private var showPlayers = false
    @State private var sessionToDelete: Session?
    @State private var showClearVideos = false

    // Computed off the first render via .task — scoring is cheap but not free.
    @State private var trend: [ProgressEngine.SessionProgress] = []
    @State private var componentTrends: [ProgressEngine.ComponentTrend] = []

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if store.sessions.isEmpty {
                    EmptyLibraryState(playerName: store.profiles.count > 1 ? store.activeProfile.displayName : nil,
                                      onRecord: { showRecord = true })
                        .padding(.top, Theme.Spacing.xl)
                } else {
                    heroStrip
                    TrendCard(trend: trend, componentTrends: componentTrends)
                }

                actionRow

                if store.sessions.count >= 2 {
                    compareRow
                }

                storageCard

                if !store.sessions.isEmpty {
                    sessionList
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(store.activeProfile.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPlayers = true
                } label: {
                    ProfileAvatar(profile: store.activeProfile, size: 32)
                }
                .accessibilityLabel("Players")
                .accessibilityValue(store.activeProfile.displayName)
                .accessibilityHint("Switch player or add a new one")
            }
        }
        .task {
            // Debug hook: `-autoOpenPlayers` opens the player switcher
            // (Simulator verification, where taps can't be injected).
            if ProcessInfo.processInfo.arguments.contains("-autoOpenPlayers") { showPlayers = true }
        }
        .task(id: TrendKey(player: store.activeProfileID, sessions: store.sessions.count)) {
            trend = store.progressTrend()
            componentTrends = store.componentTrends()
        }
        .sheet(isPresented: $showPlayers) {
            ProfileSwitcherSheet()
                .environment(store)
        }
        .sheet(isPresented: $showImport) {
            ImportSheet(player: store.activeProfile) { url in
                showImport = false
                router.startProcessing(url)
            }
        }
        .fullScreenCover(isPresented: $showRecord) {
            RecordView(player: store.activeProfile) { url in
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
        .confirmationDialog("Remove every video?",
                            isPresented: $showClearVideos,
                            titleVisibility: .visible) {
            Button("Free up \(Self.sizeText(store.totalVideoBytes))", role: .destructive) {
                withAnimation(.snappy) {
                    for session in store.sessions where session.hasVideo {
                        store.discardVideo(session)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your sessions, scores, coaching and trend all stay. Only the footage goes, and it can't be recovered.")
        }
    }

    /// Home's trend is recomputed when the player or their session count changes.
    private struct TrendKey: Hashable {
        var player: UUID
        var sessions: Int
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

    // MARK: - Storage

    /// A session's video is roughly three hundred times the size of the analysis
    /// taken from it, so the library is almost entirely footage. This only
    /// appears once that adds up to something worth acting on, rather than
    /// nagging someone with two sessions.
    private static let storageWorthMentioning: Int64 = 250_000_000

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @ViewBuilder
    private var storageCard: some View {
        let bytes = store.totalVideoBytes
        if bytes >= Self.storageWorthMentioning {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("STORAGE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text("\(Self.sizeText(bytes)) of video across ^[\(store.sessionsWithVideo) session](inflect: true)")
                    .font(.subheadline.weight(.semibold))
                Text("Clearing the footage keeps every score, the coaching and your trend. Only playback and the annotated export need the original clip.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showClearVideos = true
                } label: {
                    Label("Free up \(Self.sizeText(bytes))", systemImage: "internaldrive")
                        .frame(maxWidth: .infinity)
                }
                .secondaryActionButton()
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.l)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
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
                    let others = store.profiles.filter { $0.id != session.profileID }
                    if !others.isEmpty {
                        Menu {
                            ForEach(others) { profile in
                                Button(profile.displayName) {
                                    withAnimation(.snappy) { store.move(session, to: profile) }
                                }
                            }
                        } label: {
                            Label("Move to Player", systemImage: "person.crop.circle.badge.arrow.forward")
                        }
                    }
                    if session.hasVideo {
                        Button {
                            withAnimation(.snappy) { store.discardVideo(session) }
                        } label: {
                            Label("Free up \(Self.sizeText(store.videoBytes(session)))",
                                  systemImage: "internaldrive")
                        }
                    }
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
