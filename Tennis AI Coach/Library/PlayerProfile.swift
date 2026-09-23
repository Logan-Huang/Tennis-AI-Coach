//
//  PlayerProfile.swift
//  Tennis AI Coach
//
//  A player on this device. Every session belongs to exactly one, and
//  everything built from sessions — the form trend, comparisons, storage —
//  is per player, so two people sharing a phone never see each other's
//  numbers mixed into their own.
//

import SwiftUI

struct PlayerProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// The racquet hand. `nil` until the player says: the analysis then
    /// guesses from the clip, which is unreliable for a player filmed from
    /// across the court.
    var hand: HittingArm?
    /// Index into `ProfilePalette.colors`.
    var colorIndex: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, hand: HittingArm?, colorIndex: Int, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.hand = hand
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }

    /// "Sam Lee" → "SL", "sam" → "S", "" → "?".
    var initials: String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Player" : trimmed
    }

    var handDescription: String {
        hand.map { "\($0.displayName)-handed" } ?? "Racquet hand not set"
    }

    var color: Color { ProfilePalette.color(colorIndex) }

    static let nameLimit = 24
}

enum ProfilePalette {
    /// Distinct at avatar size in light and dark, and none of them purple —
    /// the brand stays court green.
    static let colors: [Color] = [
        Theme.court,
        Theme.clay,
        Color(.systemBlue),
        Color(.systemTeal),
        Color(.systemOrange),
        Color(.systemPink),
    ]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// The first color no existing profile uses, so a new player is told
    /// apart from the others at a glance.
    static func nextIndex(after profiles: [PlayerProfile]) -> Int {
        let used = Set(profiles.map { $0.colorIndex % colors.count })
        return (0..<colors.count).first { !used.contains($0) } ?? profiles.count % colors.count
    }
}
