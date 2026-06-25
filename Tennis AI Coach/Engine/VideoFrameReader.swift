//
//  VideoFrameReader.swift
//  Tennis AI Coach
//
//  Loads a video's metadata and provides a sequential frame decoder via
//  AVAssetReader (fast, in-order). The reader does NOT apply the track's
//  preferredTransform — orientation is handled downstream via CoordinateSpace.
//

import AVFoundation
import CoreVideo
import ImageIO

nonisolated struct VideoSource: @unchecked Sendable {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let fps: Double
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let orientation: CGImagePropertyOrientation
    let orientedSize: CGSize
    let durationS: Double
    let estimatedFrameCount: Int

    static func load(url: URL) async throws -> VideoSource {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { throw AnalysisError.unreadableVideo }

        let (nominalFPS, naturalSize, transform) = try await track.load(
            .nominalFrameRate, .naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration)

        var fps = Double(nominalFPS)
        if !fps.isFinite || fps <= 0 {
            fps = 30   // malformed-video guard
        }
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            throw AnalysisError.zeroDimensions
        }

        let orientation = CoordinateSpace.orientation(from: transform)
        let orientedSize = CoordinateSpace.orientedSize(naturalSize, orientation)
        let durationS = duration.seconds.isFinite ? duration.seconds : 0
        let estFrames = max(0, Int((durationS * fps).rounded()))

        return VideoSource(
            asset: asset, track: track, fps: fps,
            naturalSize: naturalSize, preferredTransform: transform,
            orientation: orientation, orientedSize: orientedSize,
            durationS: durationS, estimatedFrameCount: estFrames)
    }

    /// Build a fresh reader + output for one decode pass.
    func makeReader() throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AnalysisError.decodeFailed("Couldn't attach the video output.")
        }
        reader.add(output)
        return (reader, output)
    }
}
