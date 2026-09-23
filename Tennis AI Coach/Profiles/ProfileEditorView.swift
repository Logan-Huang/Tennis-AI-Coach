//
//  ProfileEditorView.swift
//  Tennis AI Coach
//
//  Add or edit a player: their name, the hand they hold the racquet in, and
//  their color. The racquet hand isn't decoration — it tells the analysis
//  which arm is swinging, which it otherwise has to guess.
//

import SwiftUI

struct ProfileEditorView: View {
    enum Mode {
        case add
        case edit(PlayerProfile)
        /// The player every existing session was given to when profiles
        /// arrived: same fields, but introduced as what's new.
        case firstRun(PlayerProfile)
    }

    let mode: Mode
    var onDone: (() -> Void)? = nil

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var hand: HittingArm?
    @State private var colorIndex: Int
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(mode: Mode, suggestedColor: Int = 0, onDone: (() -> Void)? = nil) {
        self.mode = mode
        self.onDone = onDone
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _hand = State(initialValue: .right)
            _colorIndex = State(initialValue: suggestedColor)
        case .edit(let p), .firstRun(let p):
            _name = State(initialValue: p.name)
            _hand = State(initialValue: p.hand ?? .right)
            _colorIndex = State(initialValue: p.colorIndex)
        }
    }

    private var existing: PlayerProfile? {
        switch mode {
        case .add: return nil
        case .edit(let p), .firstRun(let p): return p
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var preview: PlayerProfile {
        PlayerProfile(name: trimmedName, hand: hand, colorIndex: colorIndex)
    }

    var body: some View {
        NavigationStack {
            Form {
                if case .firstRun = mode {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("Sessions now belong to a player")
                                .font(.headline)
                            Text("Your existing sessions are kept under this profile. Add more players from the profile button on Home — everyone's videos, scores and trend stay separate.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        ProfileAvatar(profile: preview, size: 72)
                            .animation(.snappy, value: colorIndex)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Player name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onChange(of: name) { _, new in
                            if new.count > PlayerProfile.nameLimit {
                                name = String(new.prefix(PlayerProfile.nameLimit))
                            }
                        }
                }

                Section {
                    Picker("Racquet hand", selection: $hand) {
                        Text("Right").tag(HittingArm?.some(.right))
                        Text("Left").tag(HittingArm?.some(.left))
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.m,
                                              bottom: Theme.Spacing.s, trailing: Theme.Spacing.m))
                } header: {
                    Text("Racquet hand")
                } footer: {
                    Text("Tells the analysis which arm swings. From across the court, the camera can't reliably tell a player's wrists apart on its own.")
                }

                Section("Color") {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(ProfilePalette.colors.indices, id: \.self) { i in
                            Button {
                                colorIndex = i
                            } label: {
                                Circle()
                                    .fill(ProfilePalette.color(i).gradient)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if i == colorIndex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(i + 1)")
                            .accessibilityAddTraits(i == colorIndex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }

                if case .edit(let profile) = mode, store.profiles.count > 1 {
                    Section {
                        Button("Delete Player", role: .destructive) {
                            confirmDelete = true
                        }
                    } footer: {
                        let count = store.sessionCount(for: profile)
                        Text(count == 0
                             ? "\(profile.displayName) has no sessions."
                             : "Also deletes \(profile.displayName)'s ^[\(count) session](inflect: true) and their videos.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstRun {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Add" : "Done") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { store.deleteProfile(existing) }
                    dismiss()
                    onDone?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .task {
                if trimmedName.isEmpty { nameFocused = true }
            }
        }
        .interactiveDismissDisabled(isFirstRun)
        .sensoryFeedback(.selection, trigger: colorIndex)
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }

    private var isFirstRun: Bool {
        if case .firstRun = mode { return true }
        return false
    }

    private var title: String {
        switch mode {
        case .add: return "New Player"
        case .edit: return "Edit Player"
        case .firstRun: return "Your Profile"
        }
    }

    private var deleteTitle: String {
        "Delete \(existing?.displayName ?? "this player")?"
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if var profile = existing {
            profile.name = trimmedName
            profile.hand = hand
            profile.colorIndex = colorIndex
            store.update(profile)
        } else {
            store.addProfile(name: trimmedName, hand: hand, colorIndex: colorIndex)
        }
        dismiss()
        onDone?()
    }
}

#Preview("Add") {
    ProfileEditorView(mode: .add)
        .environment(LibraryStore())
}
