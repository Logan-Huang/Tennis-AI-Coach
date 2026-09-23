//
//  ProfileAvatar.swift
//  Tennis AI Coach
//

import SwiftUI

/// A player's initials on their color. The one place a player is drawn, so
/// they look the same on Home, in the switcher and in the camera.
struct ProfileAvatar: View {
    var profile: PlayerProfile
    var size: CGFloat = 32

    var body: some View {
        Text(profile.initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(profile.color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// "For Sam" with Sam's avatar — on the camera and the import sheet, so the
/// player a new session will belong to is never a surprise.
struct PlayerChip: View {
    var player: PlayerProfile
    /// Glass on the live camera; a quiet fill on ordinary backgrounds.
    var onCamera: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ProfileAvatar(profile: player, size: 22)
            Text("For \(player.displayName)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.leading, Theme.Spacing.xs)
        .padding(.trailing, Theme.Spacing.m - 4)
        .padding(.vertical, Theme.Spacing.xs)
        .foregroundStyle(onCamera ? .white : .primary)
        .modifier(ChipBackground(onCamera: onCamera))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session will be saved for \(player.displayName)")
    }

    private struct ChipBackground: ViewModifier {
        var onCamera: Bool
        func body(content: Content) -> some View {
            if onCamera {
                content.glassEffect(.regular, in: .capsule)
            } else {
                content.background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
    }
}

#Preview("Avatars", traits: .sizeThatFitsLayout) {
    HStack(spacing: Theme.Spacing.m) {
        ForEach(0..<6) { i in
            ProfileAvatar(profile: PlayerProfile(name: ["Sam Lee", "Alex", "Jo Park", "Max", "Rae", ""][i],
                                                 hand: .right, colorIndex: i), size: 44)
        }
    }
    .padding()
}
