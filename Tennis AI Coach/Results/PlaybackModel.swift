//
//  PlaybackModel.swift
//  Tennis AI Coach
//
//  The single shared AVPlayer for a results session. Owns playback state and
//  maps the player's current time to the nearest analyzed frame/pose — the
//  linchpin for the skeleton overlay and stroke-to-seek.
//

import SwiftUI
import AVFoundation

@Observable
@MainActor
final class PlaybackModel {
    let player: AVPlayer
    let frames: [FrameMetrics]
    let poses: [PoseFrame]
    let videoSize: CGSize
    let duration: Double
    let hittingArm: HittingArm

    var currentTime: Double = 0
    var isPlaying = false
    var isScrubbing = false

    private let times: [Double]
    private var timeObserver: Any?

    init(videoURL: URL, frames: [FrameMetrics], poses: [PoseFrame],
         videoSize: CGSize, duration: Double, hittingArm: HittingArm) {
        self.player = AVPlayer(url: videoURL)
        self.frames = frames
        self.poses = poses
        self.times = frames.map(\.timeS)
        self.videoSize = videoSize.width > 0 && videoSize.height > 0
            ? videoSize : CGSize(width: 9, height: 16)
        self.duration = duration
        self.hittingArm = hittingArm

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.isPlaying = self.player.timeControlStatus == .playing
            }
        }
    }

    func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= duration - 0.05 { seek(to: 0) }
            player.play()
            isPlaying = true
        }
    }

    func seek(to t: Double) {
        let clamped = min(max(0, t), max(0, duration))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func currentPose() -> PoseFrame? {
        guard let i = nearestIndex() else { return nil }
        return poses[i]
    }

    func currentFrame() -> FrameMetrics? {
        guard let i = nearestIndex() else { return nil }
        return frames[i]
    }

    func cleanup() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func nearestIndex() -> Int? {
        guard !times.isEmpty else { return nil }
        let t = currentTime
        if t <= times[0] { return 0 }
        if t >= times[times.count - 1] { return times.count - 1 }
        var lo = 0, hi = times.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, (t - times[lo - 1]) <= (times[lo] - t) { return lo - 1 }
        return lo
    }
}
