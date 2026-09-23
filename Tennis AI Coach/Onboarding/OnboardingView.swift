//
//  OnboardingView.swift
//  Tennis AI Coach
//
//  First launch only: the three things that actually improve results, the
//  privacy promise, and who's playing — the player's name and racquet hand,
//  which the analysis needs.
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    @Environment(LibraryStore.self) private var store

    @State private var page = 0
    @State private var name = ""
    @State private var hand: HittingArm = .right
    @FocusState private var nameFocused: Bool

    private let pages: [(symbol: String, title: String, message: String)] = [
        ("iphone.landscape",
         "Film side-on",
         "Set your phone level with the baseline, pointing across the court. Angles are measured in 2D — a side view is what makes them meaningful."),
        ("figure.tennis",
         "Whole body, good light",
         "Keep your full body in frame for the entire rally. The clearer the skeleton tracking, the more swings get scored."),
        ("gauge.with.needle",
         "Swing, then read your report",
         "Every swing gets a form score with a component breakdown, and sessions build a trend over time. Everything runs on your phone — no upload, no account, no analysis cap."),
    ]

    private var lastPage: Int { pages.count }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: Theme.Spacing.l) {
                        Spacer()
                        Image(systemName: item.symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.court)
                            .symbolEffect(.bounce, options: .nonRepeating, value: page)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.title2.weight(.bold))
                        Text(item.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }

                playerPage
                    .tag(lastPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < lastPage {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < lastPage ? "Continue" : "Get started")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionButton()
            .disabled(page == lastPage && trimmedName.isEmpty)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.l)

            if page < lastPage {
                Button("Skip") { withAnimation(.snappy) { page = lastPage } }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Theme.Spacing.m)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.selection, trigger: page)
        .onChange(of: page) { _, new in
            nameFocused = new == lastPage
        }
    }

    // MARK: - Who's playing

    private var playerPage: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            ProfileAvatar(profile: PlayerProfile(name: trimmedName, hand: hand,
                                                 colorIndex: store.activeProfile.colorIndex),
                          size: 80)
            Text("Who's playing?")
                .font(.title2.weight(.bold))
            Text("Sessions, scores and trends are kept per player. Sharing this phone? Add more players later from Home.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.Spacing.m) {
                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit { if !trimmedName.isEmpty { finish() } }
                    .padding(Theme.Spacing.m - 4)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
                    .onChange(of: name) { _, new in
                        if new.count > PlayerProfile.nameLimit { name = String(new.prefix(PlayerProfile.nameLimit)) }
                    }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Racquet hand").microLabel()
                    Picker("Racquet hand", selection: $hand) {
                        Text("Right").tag(HittingArm.right)
                        Text("Left").tag(HittingArm.left)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            Spacer()
            Spacer()
        }
    }

    /// Name the player every session will belong to — the one the store
    /// created on first launch.
    private func finish() {
        guard !trimmedName.isEmpty else { return }
        var profile = store.activeProfile
        profile.name = trimmedName
        profile.hand = hand
        store.update(profile)
        onDone()
    }
}

#Preview {
    OnboardingView(onDone: {})
        .environment(LibraryStore())
}
