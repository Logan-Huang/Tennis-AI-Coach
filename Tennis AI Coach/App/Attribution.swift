//
//  Attribution.swift
//  Tennis AI Coach
//
//  Install attribution through AppsFlyer: which ad, if any, brought someone to
//  the app. Nothing about their tennis goes with it. No video, sound, pose,
//  score or player name is handed to the SDK; it sends only what it collects
//  itself, the device's identifiers and the app being opened.
//
//  The dev key is not in the repository, which is public. It is read from
//  AppsFlyerKeys.plist, a git-ignored file in the app folder that Xcode Cloud
//  writes from a workflow secret (ci_scripts/ci_post_clone.sh). A build
//  without it never starts the SDK.
//
//  Apple's tracking prompt waits for the end of onboarding, so a first launch
//  opens on what the app does rather than on a permission request. The SDK
//  starts once the prompt has been answered, so the install carries the
//  advertising identifier whenever the player allows it.
//

import AppTrackingTransparency
import AppsFlyerLib
import Foundation
import UIKit

enum Attribution {
    /// The app's App Store ID.
    private static let appleAppID = "6796067877"
    /// The `@AppStorage` key onboarding sets when it finishes.
    private static let onboardingKey = "hasSeenOnboarding"
    /// Time for the app to settle on screen, or for the onboarding cover to
    /// slide away. iOS drops a tracking request made while the app is still
    /// coming forward, without showing anything.
    private static let settle: Duration = .milliseconds(700)

    private static var isConfigured = false
    /// Whether the SDK is ready in this stay in the foreground, and whether it
    /// has been started in it. Both reset when the app goes to the background.
    private static var sessionReady = false
    private static var started = false
    private static var asking = false

    /// Call once, at launch.
    static func configure() {
        guard let devKey = bundledDevKey() else { return }
        let sdk = AppsFlyerLib.shared()
        sdk.initialize(devKey: devKey, appId: appleAppID)
        #if DEBUG
        sdk.isDebug = true
        #endif
        isConfigured = true

        // Fires once each time the app comes to the foreground.
        sdk.registerSessionReadyListener {
            sessionReady = true
            startIfAnswered()
        }
        // The prompt is asked for from here, once the app is really active,
        // not from the listener, which can fire while it is still arriving.
        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { askIfNeeded() }
        }
        _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                sessionReady = false
                started = false
            }
        }
    }

    /// Onboarding just closed: time to ask.
    static func onboardingDidFinish() {
        askIfNeeded()
    }

    /// Shows the prompt while its answer is unknown; after that, just starts.
    private static func askIfNeeded() {
        log("active; configured \(isConfigured), onboarding done \(UserDefaults.standard.bool(forKey: onboardingKey)), tracking \(trackingStatus)")
        guard isConfigured, UserDefaults.standard.bool(forKey: onboardingKey) else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            startIfAnswered()
            return
        }
        guard !asking else { return }
        asking = true
        Task {
            try? await Task.sleep(for: settle)
            if UIApplication.shared.applicationState == .active {
                log("asking for tracking")
                _ = await ATTrackingManager.requestTrackingAuthorization()
                log("tracking answer: \(trackingStatus)")
            } else {
                log("not active after settling; will ask next time")
            }
            asking = false
            startIfAnswered()
        }
    }

    /// Starts once per stay in the foreground, when the SDK is ready and the
    /// prompt has been answered. A prompt that went away unanswered, as when
    /// the app leaves the screen, is asked again next time instead: starting
    /// now would send the install without the identifier the player may yet
    /// allow.
    private static func startIfAnswered() {
        guard sessionReady, !started,
              UserDefaults.standard.bool(forKey: onboardingKey),
              ATTrackingManager.trackingAuthorizationStatus != .notDetermined else { return }
        started = true
        log("starting AppsFlyer")
        AppsFlyerLib.shared().start(completionHandler: { _, error in
            log(error.map { "AppsFlyer start failed: \($0.localizedDescription)" } ?? "AppsFlyer accepted the launch")
        })
    }

    private static var trackingStatus: String {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .notDetermined: "not determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }

    /// Debug builds only: the steps above, in the console. The SDK may call
    /// back off the main thread, so this isn't tied to it.
    private nonisolated static func log(_ message: String) {
        #if DEBUG
        print("[Attribution] \(message)")
        #endif
    }

    private static func bundledDevKey() -> String? {
        guard let url = Bundle.main.url(forResource: "AppsFlyerKeys", withExtension: "plist"),
              let keys = NSDictionary(contentsOf: url),
              let devKey = keys["DevKey"] as? String,
              !devKey.isEmpty else { return nil }
        return devKey
    }
}
