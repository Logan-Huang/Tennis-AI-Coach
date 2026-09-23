//
//  ProfileSwitcherSheet.swift
//  Tennis AI Coach
//
//  Who's playing: every player on this device, with enough on each row
//  (sessions, latest form score, racquet hand) to tell them apart, one tap to
//  switch, and add / edit / delete.
//

import SwiftUI

struct ProfileSwitcherSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editing: PlayerProfile?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.profiles) { profile in
                        row(profile)
                    }
                } footer: {
                    Text("Each player's sessions, scores and trend are kept separate on this iPhone.")
                }

                Section {
                    Button {
                        adding = true
                    } label: {
                        Label("Add Player", systemImage: "person.badge.plus")
                    }
                }
            }
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { profile in
                ProfileEditorView(mode: .edit(profile))
                    .environment(store)
            }
            .sheet(isPresented: $adding) {
                ProfileEditorView(mode: .add, suggestedColor: ProfilePalette.nextIndex(after: store.profiles)) {
                    // A new player is made active; go straight to their Home.
                    dismiss()
                }
                .environment(store)
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.selection, trigger: store.activeProfileID)
    }

    private func row(_ profile: PlayerProfile) -> some View {
        let isActive = profile.id == store.activeProfileID
        let count = store.sessionCount(for: profile)
        let latest = store.latestFormScore(for: profile)
        return Button {
            store.switchTo(profile)
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                ProfileAvatar(profile: profile, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("^[\(count) session](inflect: true) · \(profile.handDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if latest.isFinite {
                    ScoreRing(score: latest, size: .row)
                }
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.court)
                    .opacity(isActive ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Edit") { editing = profile }
                .tint(Theme.court)
        }
        .contextMenu {
            Button {
                editing = profile
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.displayName), \(count) sessions, \(profile.handDescription)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(isActive ? "Current player" : "Switch to this player")
        .accessibilityAction(named: "Edit") { editing = profile }
    }
}

#Preview {
    ProfileSwitcherSheet()
        .environment(LibraryStore())
}
