//
//  AudioOnsets.swift
//  Tennis AI Coach
//
//  Finds the sharp transients in a clip's soundtrack — the "pock" of a ball
//  on strings is the loudest, shortest sound on a tennis court.
//
//  Pose can say that the player swung, but not reliably when the racquet met
//  the ball: the wrist is motion-blurred at exactly that moment, and on a
//  player filmed from across the court the take-back or the follow-through can
//  measure faster than the swing itself. The sound of the hit is late only by
//  the time it takes to reach the phone (60 ms from the far baseline). On the
//  hand-labelled sample clips a sharp onset marks 29 of 31 contacts, within
//  0.04 s of the frame where the ball meets the strings.
//
//  It also marks the ball bouncing, the hitting partner's shots and the court
//  next door, so an onset is never a stroke on its own. `StrokeDetector` only
//  accepts one where the player is mid-swing and their hand is moving at the
//  sound, and a clip with no soundtrack, or one buried under music, falls
//  back to pose alone.
//

import AVFoundation
import CoreMedia

nonisolated struct AudioOnset: Sendable {
    var timeS: Double
    /// Rise of the log energy over the preceding 50 ms (natural-log units):
    /// how sharply the sound stands out from what came just before it.
    var strength: Double
    /// Loudest sample in the first 30 ms, full scale = 1. How loud the sound
    /// is — which, between a hit and a bounce half a second apart, says more
    /// than how sharply each one starts.
    var peak: Double = 0
}

nonisolated enum AudioOnsets {

    static let sampleRate = 22_050.0
    /// Analysis hop: 128 samples, ~5.8 ms.
    private static let hop = 128
    /// The energy an onset rises from is the median of this much sound before it.
    private static let baselineS = 0.05
    /// An onset stands this many robust standard deviations (MAD × 1.4826)
    /// clear of the clip's typical rise. 3-6 all find the same contacts on the
    /// sample clips; 5 admits the fewest bounces.
    private static let madMultiple = 5.0
    /// ... and is louder than 90% of the clip.
    private static let loudnessPercentile = 90.0
    /// Two onsets closer than this are one sound.
    private static let mergeS = 0.1
    /// More onsets per second than this is music or wind, not tennis: a rally
    /// is two hits and two bounces every two or three seconds.
    private static let maxRatePerSecond = 2.5
    /// How much sound after an onset its `peak` is read from.
    private static let peakWindowS = 0.03

    /// Onsets in the clip's first audio track, on the clock the analysis uses
    /// for video frames (seconds since `videoStartS`, the video track's first
    /// frame); empty when there is no soundtrack or it can't be trusted.
    static func detect(asset: AVAsset, videoStartS: Double = 0) async -> [AudioOnset] {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return [] }
        guard let (samples, startS) = try? decode(asset: asset, track: track), !samples.isEmpty else { return [] }
        return onsets(in: samples, startS: startS - videoStartS)
    }

    /// Mono float samples at `sampleRate`, and the time of the first one.
    private static func decode(asset: AVAsset, track: AVAssetTrack) throws -> ([Float], Double) {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ])
        guard reader.canAdd(output) else { return ([], 0) }
        reader.add(output)
        guard reader.startReading() else { return ([], 0) }

        var samples: [Float] = []
        var startS: Double?
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return ([], 0) }
            if startS == nil {
                let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                startS = pts.isFinite ? pts : 0
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var chunk = [Float](repeating: 0, count: count)
            let status = chunk.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count,
                                           destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            samples.append(contentsOf: chunk)
        }
        guard reader.status == .completed else { return ([], 0) }
        return (samples, startS ?? 0)
    }

    /// The onset picker, separate from decoding so it can be tested on
    /// synthetic sound.
    static func onsets(in x: [Float], startS: Double) -> [AudioOnset] {
        let n = x.count / hop
        guard n > 16 else { return [] }

        // Energy of the first difference: a crude high-pass that favours the
        // click of a hit over voices, footsteps and hum.
        var energy = [Double](repeating: 0, count: n)
        var previous: Float = 0
        for h in 0..<n {
            var sum = 0.0
            for i in (h * hop)..<((h + 1) * hop) {
                let d = Double(x[i] - previous)
                previous = x[i]
                sum += d * d
            }
            energy[h] = (sum / Double(hop)).squareRoot()
        }
        let logE = energy.map { log($0 + 1e-6) }
        let base = max(1, Int((baselineS * sampleRate / Double(hop)).rounded()))
        var rise = [Double](repeating: 0, count: n)
        for h in 1..<n {
            rise[h] = logE[h] - NanStats.nanMedian(Array(logE[max(0, h - base)..<h]))
        }

        let med = NanStats.nanMedian(rise)
        let mad = 1.4826 * NanStats.nanMedian(rise.map { abs($0 - med) })
        let threshold = med + madMultiple * mad
        let loud = NanStats.nanPercentile(energy, loudnessPercentile)
        let merge = Int((mergeS * sampleRate / Double(hop)).rounded())

        var picked: [Int] = []
        for h in 1..<(n - 1) where rise[h] > threshold && energy[h] > loud
            && rise[h] >= rise[h - 1] && rise[h] >= rise[h + 1] {
            if let last = picked.last, h - last < merge {
                if rise[h] > rise[last] { picked[picked.count - 1] = h }
                continue
            }
            picked.append(h)
        }

        let durationS = Double(x.count) / sampleRate
        guard durationS > 0, Double(picked.count) / durationS <= maxRatePerSecond else { return [] }
        let peakSamples = Int((peakWindowS * sampleRate).rounded())
        return picked.map { h in
            let start = h * hop
            let peak = x[start..<min(x.count, start + peakSamples)].reduce(Float(0)) { max($0, abs($1)) }
            return AudioOnset(timeS: startS + Double(start) / sampleRate, strength: rise[h], peak: Double(peak))
        }
    }
}
