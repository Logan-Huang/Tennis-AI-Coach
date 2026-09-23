//
//  PlayerTracker.swift
//  Tennis AI Coach
//
//  Finds the player a clip is about and keeps Vision's pose estimate on them.
//
//  Vision's body-pose model looks at the whole frame at a fixed internal
//  resolution. A player filmed from across the court is 15% of the frame tall
//  or less, and at that size the model mostly sees nobody: on the six sample
//  rally clips, full-frame pose returned a usable skeleton in about one frame
//  in five. Asked to look only at a square around the player, the same model
//  returns 17-19 joints almost every time. It also used to take whichever
//  person it was most confident about in each frame, so on a court with a
//  hitting partner in view the "player" could change from one frame to the
//  next, and every change looked like the fastest swing in the clip.
//
//  So pose runs in two passes:
//
//  1. `SubjectLocator` runs Vision's person detector about ten times a second,
//     links the boxes into tracks, and picks the track the clip is about: the
//     one with the most body in frame over time. A partner at the far end of
//     the court is smaller; somebody walking past is brief.
//  2. `SubjectTracker` runs pose on a square around that player in every
//     sampled frame. It steers by its own skeleton from the frame before when
//     it has one, because that is current to the frame, and by the pass-1
//     track when it doesn't, or when the two disagree about where the player
//     is (which is how it gets back onto the right person if it ever drifts).
//
//  All boxes are in pixel space over the ORIENTED frame, origin top-left —
//  the same space as `Pt` and every metric downstream.
//

import Foundation
import simd
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import ImageIO
import Vision

// MARK: - Pass 1: who is the clip about?

nonisolated enum SubjectLocator {

    /// Person-detector runs per second of video. The player's position is
    /// interpolated in between, and pass 2 corrects it frame by frame, so this
    /// only has to be fast enough to follow a panning camera.
    static let detectionsPerSecond = 10.0

    /// Two boxes at consecutive detections are the same person when their
    /// centres are within this many body heights, plus `driftPerSecond` body
    /// heights for every second they are apart.
    private static let linkDistance = 0.75
    private static let driftPerSecond = 1.5
    /// ... and their heights are within this factor of each other.
    private static let linkScale = 1.6
    /// A track that hasn't been seen for this long is finished.
    private static let maxLinkGapS = 1.0
    /// A track needs this many sightings before it can stand for the player.
    private static let minSightings = 3
    /// The expected box is interpolated across gaps up to this long, and held
    /// at either end of the track for `holdS`. Beyond that there is no
    /// estimate and pass 2 tracks by the skeleton alone.
    private static let maxInterpolateS = 2.0
    private static let holdS = 0.5

    /// Detector boxes for one decoded frame, keyed by processed-frame index.
    struct Sighting {
        var index: Int
        var boxes: [CGRect]
    }

    /// Run the person detector over the clip and return the expected player
    /// box for every processed frame (`nil` where there is no estimate).
    static func locate(source: VideoSource,
                       stride: Int,
                       progress: (Double) -> Void) throws -> [CGRect?] {
        let samplesPerSecond = source.fps / Double(stride)
        let every = max(1, Int((samplesPerSecond / detectionsPerSecond).rounded()))

        let (reader, output) = try source.makeReader()
        guard reader.startReading() else {
            throw AnalysisError.decodeFailed(reader.error?.localizedDescription)
        }
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false

        let estProcessed = max(1, source.estimatedFrameCount / stride)
        var sightings: [Sighting] = []
        var rawIndex = 0
        var processedCount = 0
        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            defer { rawIndex += 1 }
            if Task.isCancelled {
                reader.cancelReading()
                throw AnalysisError.cancelled
            }
            guard rawIndex % stride == 0 else { continue }
            let index = rawIndex / stride
            processedCount = index + 1
            guard index % every == 0,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer, orientation: source.orientation, options: [:])
            try? handler.perform([request])
            let boxes = (request.results ?? []).map {
                CoordinateSpace.denormalize(rect: $0.boundingBox, orientedSize: source.orientedSize)
            }
            sightings.append(Sighting(index: index, boxes: boxes))
            if sightings.count % 4 == 0 {
                progress(min(0.99, Double(index) / Double(estProcessed)))
            }
        }
        if reader.status == .failed {
            throw AnalysisError.decodeFailed(reader.error?.localizedDescription)
        }
        progress(1.0)
        return expectedBoxes(sightings: sightings,
                             frameCount: processedCount,
                             samplesPerSecond: samplesPerSecond)
    }

    /// Link sightings into tracks, pick the player's, and spread it over every
    /// processed frame. Separate from `locate` so it can be exercised without
    /// Vision.
    static func expectedBoxes(sightings: [Sighting],
                              frameCount: Int,
                              samplesPerSecond: Double) -> [CGRect?] {
        let tracks = link(sightings, samplesPerSecond: samplesPerSecond)
        let chosen = choosePlayer(tracks)
        return spread(chosen, frameCount: frameCount, samplesPerSecond: samplesPerSecond)
    }

    // MARK: Linking

    private struct Track {
        var points: [(index: Int, box: CGRect)] = []
        var last: (index: Int, box: CGRect) { points[points.count - 1] }
        var first: (index: Int, box: CGRect) { points[0] }
        /// How much of the clip this person fills: Σ height over sightings.
        var weight: Double { points.reduce(0) { $0 + Double($1.box.height) } }
        var medianHeight: Double { NanStats.nanMedian(points.map { Double($0.box.height) }) }
    }

    private static func link(_ sightings: [Sighting], samplesPerSecond: Double) -> [Track] {
        var tracks: [Track] = []
        var open: [Int] = []   // indices into `tracks` still accepting sightings
        let maxGap = Int((maxLinkGapS * samplesPerSecond).rounded())

        for sighting in sightings {
            open.removeAll { sighting.index - tracks[$0].last.index > maxGap }

            // Greedy assignment, cheapest pair first.
            var pairs: [(cost: Double, track: Int, box: Int)] = []
            for t in open {
                let last = tracks[t].last
                let gapS = Double(sighting.index - last.index) / samplesPerSecond
                let h = Double(last.box.height)
                guard h > 0 else { continue }
                for (b, box) in sighting.boxes.enumerated() {
                    let dist = simd_distance(box.center, last.box.center) / h
                    let scale = Double(box.height) / h
                    guard dist <= linkDistance + driftPerSecond * gapS,
                          scale <= linkScale, scale >= 1 / linkScale else { continue }
                    pairs.append((dist + abs(log(scale)), t, b))
                }
            }
            pairs.sort { $0.cost < $1.cost }
            var usedTracks = Set<Int>(), usedBoxes = Set<Int>()
            for p in pairs where !usedTracks.contains(p.track) && !usedBoxes.contains(p.box) {
                tracks[p.track].points.append((sighting.index, sighting.boxes[p.box]))
                usedTracks.insert(p.track)
                usedBoxes.insert(p.box)
            }
            for (b, box) in sighting.boxes.enumerated() where !usedBoxes.contains(b) {
                tracks.append(Track(points: [(sighting.index, box)]))
                open.append(tracks.count - 1)
            }
        }
        return tracks.filter { $0.points.count >= minSightings }
    }

    /// The heaviest track, plus any other track that could be the same person
    /// seen again after the detector lost them: it doesn't overlap the chosen
    /// tracks in time and it is about the same size. The size test is what
    /// keeps a hitting partner out — at the far end of the court they are a
    /// fraction of the player's height.
    private static func choosePlayer(_ tracks: [Track]) -> [(index: Int, box: CGRect)] {
        let ranked = tracks.sorted { $0.weight > $1.weight }
        guard let best = ranked.first else { return [] }
        var chosen: [Track] = [best]
        for candidate in ranked.dropFirst() {
            let overlaps = chosen.contains {
                candidate.first.index <= $0.last.index && $0.first.index <= candidate.last.index
            }
            guard !overlaps else { continue }
            // Size against the chosen sighting nearest in time.
            let nearest = chosen.flatMap(\.points).min {
                min(abs($0.index - candidate.first.index), abs($0.index - candidate.last.index)) <
                min(abs($1.index - candidate.first.index), abs($1.index - candidate.last.index))
            }
            guard let nearest, nearest.box.height > 0 else { continue }
            let scale = candidate.medianHeight / Double(nearest.box.height)
            guard scale <= linkScale, scale >= 1 / linkScale else { continue }
            chosen.append(candidate)
        }
        return chosen.flatMap(\.points).sorted { $0.index < $1.index }
    }

    // MARK: Spreading over every frame

    private static func spread(_ points: [(index: Int, box: CGRect)],
                               frameCount: Int,
                               samplesPerSecond: Double) -> [CGRect?] {
        var out = [CGRect?](repeating: nil, count: max(0, frameCount))
        guard !points.isEmpty, frameCount > 0 else { return out }
        let maxGap = Int((maxInterpolateS * samplesPerSecond).rounded())
        let hold = Int((holdS * samplesPerSecond).rounded())

        for (a, b) in zip(points, points.dropFirst()) where b.index - a.index <= maxGap {
            for i in a.index...b.index where i < frameCount {
                let f = b.index == a.index ? 0 : Double(i - a.index) / Double(b.index - a.index)
                out[i] = a.box.lerp(to: b.box, f)
            }
        }
        for p in points where p.index < frameCount { out[p.index] = p.box }
        // Hold the ends (and each side of an over-long gap) briefly.
        for (k, p) in points.enumerated() {
            let prevGapTooLong = k == 0 || p.index - points[k - 1].index > maxGap
            let nextGapTooLong = k == points.count - 1 || points[k + 1].index - p.index > maxGap
            if prevGapTooLong {
                for i in max(0, p.index - hold)..<p.index where out[i] == nil { out[i] = p.box }
            }
            if nextGapTooLong, p.index + 1 < frameCount {
                for i in (p.index + 1)...min(frameCount - 1, p.index + hold) where out[i] == nil { out[i] = p.box }
            }
        }
        return out
    }
}

// MARK: - Pass 2: pose on the player, every frame

nonisolated struct SubjectTracker {
    /// Side of the square pose is run on, in player heights. Wide enough for a
    /// fully extended arm and a racquet either side of the body; any wider and
    /// the player shrinks back toward what full-frame pose already fails on.
    static let regionHeights = 1.7
    /// The previous frame's skeleton steers the next region for this long.
    static let priorMaxAgeS = 0.3
    /// Where the previous skeleton and the pass-1 track disagree by more than
    /// this many player heights, the track wins: the skeleton has drifted.
    static let reanchorHeights = 1.0
    /// A skeleton belongs to the player when its centre is within this many
    /// heights of where the player was expected ...
    static let acceptHeights = 0.6
    /// ... it is no more than this factor taller than the player ...
    static let maxScale = 1.6
    /// ... and it has at least this many of the twelve metric joints.
    static let minJoints = 5

    private let plan: [CGRect?]
    private let frameSize: CGSize
    private let priorMaxAge: Int
    private var prior: (index: Int, box: CGRect)?
    /// Height of the last skeleton that ran head to ankle. A skeleton missing
    /// its ankles is short; sizing the next region from it would shrink the
    /// region onto the torso and lose the legs for good.
    private var fullHeight: Double?

    init(plan: [CGRect?], frameSize: CGSize, samplesPerSecond: Double) {
        self.plan = plan
        self.frameSize = frameSize
        self.priorMaxAge = max(1, Int((Self.priorMaxAgeS * samplesPerSecond).rounded()))
    }

    /// Pose for processed frame `index`: the player's joints, or empty.
    mutating func track(index: Int,
                        pixelBuffer: CVPixelBuffer,
                        orientation: CGImagePropertyOrientation,
                        estimator: PoseEstimator) -> [BodyJoint: Pt] {
        let anchor = index < plan.count ? plan[index] : nil
        let fresh = prior.flatMap { index - $0.index <= priorMaxAge ? $0.box : nil }

        // Where to look first, and where to look if that finds nobody.
        var attempts: [CGRect] = []
        switch (fresh, anchor) {
        case let (p?, a?):
            let height = Double(a.height)
            if simd_distance(p.center, a.center) > Self.reanchorHeights * height {
                attempts = [a]
            } else {
                attempts = [p.resized(height: max(Double(p.height), height)), a]
            }
        case let (p?, nil):
            attempts = [p.resized(height: max(Double(p.height), fullHeight ?? 0))]
        case let (nil, a?):
            attempts = [a]
        case (nil, nil):
            break
        }

        for expected in attempts {
            let region = Self.region(around: expected, in: frameSize)
            let found = estimator.detect(pixelBuffer: pixelBuffer, orientation: orientation,
                                         orientedSize: frameSize, region: region)
            if let hit = Self.pick(found, expected: expected) {
                remember(hit, index: index)
                return hit.joints
            }
        }

        // Nothing to steer by (no track yet, or both searches came up empty
        // with no track to fall back on): whole frame, most confident person.
        // This is the old behaviour, and it is what bootstraps a clip the
        // person detector never saw anyone in.
        if anchor == nil, fresh == nil {
            let found = estimator.detect(pixelBuffer: pixelBuffer, orientation: orientation,
                                         orientedSize: frameSize, region: nil)
            if let best = found.filter({ $0.joints.count >= Self.minJoints })
                .max(by: { $0.confidence < $1.confidence }) {
                remember(best, index: index)
                return best.joints
            }
        }
        return [:]
    }

    private mutating func remember(_ hit: PoseEstimator.Detection, index: Int) {
        prior = (index, hit.box)
        if hit.isHeadToAnkle { fullHeight = Double(hit.box.height) }
    }

    /// The detection that is the player, if any.
    private static func pick(_ found: [PoseEstimator.Detection],
                             expected: CGRect) -> PoseEstimator.Detection? {
        let h = Double(expected.height)
        guard h > 0 else { return nil }
        return found
            .filter { $0.joints.count >= minJoints }
            .filter { Double($0.box.height) <= maxScale * h }
            .map { ($0, simd_distance($0.box.center, expected.center) / h) }
            .filter { $0.1 <= acceptHeights }
            .min { $0.1 < $1.1 }?.0
    }

    /// Square (in pixels) of side `regionHeights` × the player's height,
    /// centred on them and slid back inside the frame. `nil` — the whole
    /// frame — when the player is already large enough to fill it.
    static func region(around box: CGRect, in size: CGSize) -> CGRect? {
        let side = regionHeights * Double(box.height)
        let w = Double(size.width), h = Double(size.height)
        guard side > 0, side < min(w, h) else { return nil }
        var x = Double(box.midX) - side / 2
        var y = Double(box.midY) - side / 2
        x = min(max(0, x), w - side)
        y = min(max(0, y), h - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }
}

// MARK: - Geometry helpers

nonisolated extension CGRect {
    var center: Pt { Pt(Double(midX), Double(midY)) }

    func lerp(to other: CGRect, _ f: Double) -> CGRect {
        let g = CGFloat(f)
        return CGRect(x: minX + (other.minX - minX) * g,
                      y: minY + (other.minY - minY) * g,
                      width: width + (other.width - width) * g,
                      height: height + (other.height - height) * g)
    }

    /// Same centre, the given height, width scaled to keep the aspect.
    func resized(height newHeight: Double) -> CGRect {
        guard height > 0, newHeight > 0 else { return self }
        let k = CGFloat(newHeight) / height
        return CGRect(x: midX - width * k / 2, y: midY - height * k / 2,
                      width: width * k, height: height * k)
    }
}
