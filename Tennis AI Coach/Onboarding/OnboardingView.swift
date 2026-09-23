//
//  OnboardingView.swift
//  Tennis AI Coach
//
//  First launch: swipe through what the app does, then say who's playing.
//
//  Six feature pages, each a live picture of one thing the app does over a
//  short headline, then the player's name and racquet hand — which the
//  analysis needs, so it's the one page that can't be skipped past. Always on
//  the dark court surface, whatever the system appearance, like the App Store
//  screenshots it follows on from.
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    @Environment(LibraryStore.self) private var store

    @State private var page = 0
    @State private var name = ""
    @State private var hand: HittingArm = .right
    @FocusState private var nameFocused: Bool

    private enum Step: Int, CaseIterable, Identifiable {
        case welcome, scored, coach, tracking, sound, tips, player
        var id: Int { rawValue }
    }

    private var step: Step { Step(rawValue: page) ?? .welcome }
    private var isLast: Bool { step == .player }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { withAnimation(.snappy) { page = Step.player.rawValue } }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                        .opacity(isLast ? 0 : 1)
                        .disabled(isLast)
                        .accessibilityHint("Go to setting up your player")
                }
                .frame(height: 44)

                TabView(selection: $page) {
                    ForEach(Step.allCases) { s in
                        content(for: s)
                            .tag(s.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: Theme.Spacing.l) {
                    if !nameFocused {
                        PageDots(count: Step.allCases.count, current: page)
                    }
                    Button {
                        if isLast {
                            finish()
                        } else {
                            withAnimation(.snappy) { page += 1 }
                        }
                    } label: {
                        Text(isLast ? "Get started" : "Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(Theme.courtDeep)
                            .background(Theme.ball, in: Capsule())
                    }
                    .buttonStyle(CardButtonStyle())
                    .opacity(isLast && trimmedName.isEmpty ? 0.45 : 1)
                    .disabled(isLast && trimmedName.isEmpty)
                    .padding(.horizontal, Theme.Spacing.l)
                }
                .padding(.bottom, Theme.Spacing.m)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: page)
        .onChange(of: page) { _, new in
            if new != Step.player.rawValue { nameFocused = false }
        }
        .task {
            // Debug hook: `-onboardingPage <n>` opens on page n (Simulator
            // verification, where swipes can't be injected).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-onboardingPage"), i + 1 < args.count, let n = Int(args[i + 1]) {
                page = min(max(0, n), Step.allCases.count - 1)
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func content(for s: Step) -> some View {
        let active = s == step
        switch s {
        case .welcome:
            FeaturePage(line1: "Your swing,", line2: "coached.",
                        message: "Film a rally or a practice. The app finds every swing, scores it and tells you what to work on.") {
                WelcomeVisual(active: active)
            }
        case .scored:
            FeaturePage(line1: "Every swing.", line2: "Scored.",
                        message: "A 0–100 form score for each forehand, backhand and serve, with the full breakdown one tap away.") {
                ScoredVisual(active: active)
            }
        case .coach:
            FeaturePage(line1: "A coach for", line2: "every stroke",
                        message: "Serves, forehands and backhands are recognized and coached on what matters for each one.") {
                CoachVisual(active: active)
            }
        case .tracking:
            FeaturePage(line1: "Finds you", line2: "across the net",
                        message: "Film from the side or from the far end. The app follows you through every frame and ignores everyone else.") {
                TrackingVisual(active: active)
            }
        case .sound:
            FeaturePage(line1: "Hears", line2: "every hit",
                        message: "Each stroke is timed from the sound of the ball on your strings. The audio is analyzed on your iPhone and never uploaded.") {
                SoundVisual(active: active)
            }
        case .tips:
            FeaturePage(line1: "Film it", line2: "right",
                        message: "Three things that make the biggest difference to your scores.") {
                TipsVisual(active: active)
            }
        case .player:
            playerPage
        }
    }

    // MARK: - Who's playing

    /// Scrolls, so the keyboard can take the bottom half of an iPhone SE
    /// without the name field or the racquet hand going underneath it.
    private var playerPage: some View {
        ScrollView {
            playerForm
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var playerForm: some View {
        VStack(spacing: Theme.Spacing.l) {
            ProfileAvatar(profile: PlayerProfile(name: trimmedName, hand: hand,
                                                 colorIndex: store.activeProfile.colorIndex),
                          size: nameFocused ? 64 : 96)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .animation(.snappy, value: nameFocused)
            OnboardingTitle(line1: "Who's", line2: "playing?")
            Text("Everyone who plays gets their own sessions, scores and progress. Add more players later from Home.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.Spacing.m) {
                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit { if !trimmedName.isEmpty { finish() } }
                    .font(.title3.weight(.semibold))
                    .padding(Theme.Spacing.m)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(.white.opacity(0.18)))
                    .onChange(of: name) { _, new in
                        if new.count > PlayerProfile.nameLimit { name = String(new.prefix(PlayerProfile.nameLimit)) }
                    }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Racquet hand")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                    Picker("Racquet hand", selection: $hand) {
                        Text("Right").tag(HittingArm.right)
                        Text("Left").tag(HittingArm.left)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
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

// MARK: - Page layout

/// A picture of the feature over a two-line headline and one sentence.
private struct FeaturePage<Visual: View>: View {
    var line1: String
    var line2: String
    var message: String
    @ViewBuilder var visual: Visual

    /// The words take the room they need and the picture scales into what's
    /// left, so a long sentence on an iPhone SE shrinks the picture instead of
    /// running into the page dots.
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            visual
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.Spacing.m)
            VStack(spacing: Theme.Spacing.m - 4) {
                OnboardingTitle(line1: line1, line2: line2)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.m)
            .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The App Store screenshots' headline treatment: heavy italic capitals, the
/// second line in tennis-ball yellow.
private struct OnboardingTitle: View {
    var line1: String
    var line2: String

    var body: some View {
        VStack(spacing: 0) {
            Text(line1).foregroundStyle(.white)
            Text(line2).foregroundStyle(Theme.ball)
        }
        .font(.system(.largeTitle, weight: .heavy).italic())
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct PageDots: View {
    var count: Int
    var current: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.ball : .white.opacity(0.3))
                    .frame(width: i == current ? 24 : 8, height: 8)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// Deep court green with a glow of tennis-ball yellow and faint court lines —
/// the same surface as the App Store screenshots.
private struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.16, blue: 0.11),
                                    Color(red: 0.05, green: 0.26, blue: 0.19),
                                    Color(red: 0.07, green: 0.35, blue: 0.25)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.ball.opacity(0.16), .clear],
                           center: UnitPoint(x: 0.85, y: 0.05), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.courtLight.opacity(0.3), .clear],
                           center: UnitPoint(x: 0.1, y: 1.0), startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    OnboardingView(onDone: {})
        .environment(LibraryStore())
}
