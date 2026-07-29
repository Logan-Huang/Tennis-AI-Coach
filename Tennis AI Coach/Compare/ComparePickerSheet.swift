//
//  ComparePickerSheet.swift
//  Tennis AI Coach
//
//  Pick two sessions to compare. Selection order doesn't matter — the older
//  session is always "before". Defaults to the latest two.
//

import SwiftUI

struct ComparePickerSheet: View {
    let onCompare: (_ beforeID: UUID, _ afterID: UUID) -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selected: [UUID] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.m - 4) {
                    Text("Pick two sessions — the older one becomes “before”.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(store.sessions) { session in
                        Button {
                            toggle(session.id)
                        } label: {
                            HStack(spacing: Theme.Spacing.m - 4) {
                                Image(systemName: selected.contains(session.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(session.id)
                                                     ? Theme.court : Color(.tertiaryLabel))
                                SessionCard(session: session,
                                            score: store.scores(for: session).session.overall)
                            }
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityAddTraits(selected.contains(session.id) ? .isSelected : [])
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Compare sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Compare") {
                        let pair = orderedPair()
                        dismiss()
                        if let pair { onCompare(pair.0, pair.1) }
                    }
                    .disabled(orderedPair() == nil)
                }
            }
            .task { preselectLatestTwo() }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func toggle(_ id: UUID) {
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
        } else {
            selected.append(id)
            if selected.count > 2 { selected.removeFirst() }
        }
    }

    private func preselectLatestTwo() {
        guard selected.isEmpty, store.sessions.count >= 2 else { return }
        selected = [store.sessions[0].id, store.sessions[1].id]
    }

    /// (beforeID, afterID) ordered by date — older first.
    private func orderedPair() -> (UUID, UUID)? {
        guard selected.count == 2,
              let a = store.session(id: selected[0]),
              let b = store.session(id: selected[1]) else { return nil }
        return a.createdAt < b.createdAt ? (a.id, b.id) : (b.id, a.id)
    }
}
