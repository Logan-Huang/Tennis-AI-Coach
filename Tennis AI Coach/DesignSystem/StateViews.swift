//
//  StateViews.swift
//  Tennis AI Coach
//
//  Distinct, specific non-content states. Each state gets its own symbol and
//  copy that says what to DO next — no more one-template-for-everything.
//

import SwiftUI
import UIKit

/// Empty library: first-run Home.
struct EmptyLibraryState: View {
    var onRecord: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No sessions yet", systemImage: "figure.tennis")
        } description: {
            Text("Film side-on from the baseline with your full body in frame to get your first form score.")
        } actions: {
            Button("Record your first session", action: onRecord)
                .primaryActionButton()
        }
    }
}

/// Analysis produced no usable pose data.
struct TrackingFailedState: View {
    var onShowVideo: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't track a player", systemImage: "person.fill.questionmark")
        } description: {
            Text("No clear body pose was detected. Film side-on from the baseline, full body in frame, in good light — then try again.")
        } actions: {
            if let onShowVideo {
                Button("Watch the clip", action: onShowVideo)
                    .secondaryActionButton()
            }
        }
    }
}

/// Camera or photo permission denied.
struct PermissionDeniedState: View {
    var title: String = "Camera access needed"
    var message: String = "Tennis AI Coach films your session locally — nothing leaves your phone. Allow camera access in Settings to record."

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "video.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .primaryActionButton()
        }
    }
}

/// Annotated-video export failed.
struct ExportFailedState: View {
    var message: String
    var onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Export didn't finish", systemImage: "film.stack")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: onRetry)
                .primaryActionButton()
        }
    }
}

#Preview("States") {
    ScrollView {
        VStack(spacing: Theme.Spacing.xl) {
            EmptyLibraryState(onRecord: {})
            Divider()
            TrackingFailedState(onShowVideo: {})
            Divider()
            PermissionDeniedState()
            Divider()
            ExportFailedState(message: "The video writer ran out of disk space.", onRetry: {})
        }
    }
}
