//
//  AnnotatedVideoExporter.swift
//  Tennis AI Coach
//
//  Second pass: re-decode the source, draw the skeleton + metric HUD into each
//  processed frame (oriented space), and encode an H.264 MP4. Everything is
//  drawn upright in oriented space with an identity writer transform — never
//  double-rotated. Font/line widths scale with resolution.
//

import AVFoundation
import CoreImage
import CoreVideo
import UIKit

enum AnnotatedVideoExporter {

    nonisolated static func export(source: VideoSource,
                                   result: AnalysisResult,
                                   progress: @Sendable (Double) -> Void) async throws -> URL {
        let oriented = source.orientedSize
        let width = Int(oriented.width.rounded())
        let height = Int(oriented.height.rounded())
        guard width > 0, height > 0 else { throw AnalysisError.exportFailed("Invalid video size.") }

        let stride = max(1, result.meta.sampleStride)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("annotated_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)

        // Writer setup.
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        input.transform = .identity
        let pbAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: pbAttributes)
        guard writer.canAdd(input) else { throw AnalysisError.exportFailed("Couldn't configure the writer.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw AnalysisError.exportFailed(writer.error?.localizedDescription)
        }
        writer.startSession(atSourceTime: .zero)

        // Reader setup.
        let (reader, output) = try source.makeReader()
        guard reader.startReading() else {
            throw AnalysisError.exportFailed(reader.error?.localizedDescription)
        }

        // Index cached data by raw frame index.
        let posesByFrame = Dictionary(
            zip(result.frames.map(\.frameIndex), result.poses), uniquingKeysWith: { a, _ in a })
        let metricsByFrame = Dictionary(
            uniqueKeysWithValues: result.frames.map { ($0.frameIndex, $0) })

        let ciContext = CIContext()
        let outFPS = source.fps / Double(stride)
        let drawScale = max(0.5, oriented.height / 1080.0)
        let estProcessed = max(1, source.estimatedFrameCount / stride)

        // Per-shot scores for burned-in badges around each swing's peak.
        let shotScores = ShotScorer.score(result: result)
        let badges: [(peakTime: Double, label: String, color: UIColor)] =
            zip(result.strokes, shotScores).compactMap { stroke, shot in
                guard shot.isGraded else { return nil }
                return (stroke.peakTime,
                        "SWING \(stroke.id) · \(Int(shot.overall.rounded()))",
                        bandColor(shot.band))
            }

        var rawIndex = 0
        var processedIndex = 0

        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            defer { rawIndex += 1 }

            if Task.isCancelled {
                reader.cancelReading()
                input.markAsFinished()
                writer.cancelWriting()
                throw AnalysisError.cancelled
            }
            if rawIndex % stride != 0 { continue }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }

            let orientedCI = CIImage(cvPixelBuffer: pixelBuffer).oriented(source.orientation)
            guard let baseImage = ciContext.createCGImage(orientedCI, from: orientedCI.extent) else { continue }

            let frameTime = metricsByFrame[rawIndex]?.timeS
            let badge = frameTime.flatMap { t in
                badges.first { abs($0.peakTime - t) <= 0.4 }
            }
            let annotated = renderFrame(
                base: baseImage, size: oriented,
                pose: posesByFrame[rawIndex],
                metric: metricsByFrame[rawIndex],
                hittingArm: result.hittingArm,
                badge: badge.map { ($0.label, $0.color) },
                scale: drawScale)

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool,
                  let outBuffer = makePixelBuffer(from: annotated, pool: pool, width: width, height: height) else {
                continue
            }
            let pts = CMTimeMakeWithSeconds(Double(processedIndex) / outFPS, preferredTimescale: 600)
            adaptor.append(outBuffer, withPresentationTime: pts)
            processedIndex += 1

            if processedIndex % 4 == 0 {
                progress(min(0.99, Double(processedIndex) / Double(estProcessed)))
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        guard writer.status == .completed else {
            throw AnalysisError.exportFailed(writer.error?.localizedDescription)
        }
        progress(1.0)
        return outURL
    }

    // MARK: - Drawing

    private nonisolated static func bandColor(_ band: ScoreBand) -> UIColor {
        let name: String
        switch band {
        case .excellent: name = "Good"
        case .solid: name = "CourtLight"
        case .developing: name = "Watch"
        case .workOn: name = "Focus"
        case .ungraded: name = "Court"
        }
        return UIColor(named: name) ?? .systemGreen
    }

    private nonisolated static func renderFrame(base: CGImage,
                                                size: CGSize,
                                                pose: PoseFrame?,
                                                metric: FrameMetrics?,
                                                hittingArm: HittingArm,
                                                badge: (label: String, color: UIColor)?,
                                                scale: CGFloat) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { rendererContext in
            let cg = rendererContext.cgContext

            // Upright source frame (UIImage.draw handles the CG flip).
            UIImage(cgImage: base).draw(in: CGRect(origin: .zero, size: size))

            // Skeleton — same renderer as the live overlay and share cards.
            if let pose {
                PoseDrawing.draw(pose: pose, in: cg, size: size,
                                 hittingArm: hittingArm, scale: scale)
            }

            // Metric HUD.
            if let metric {
                drawHUD(metric: metric, hittingArm: hittingArm, size: size, scale: scale)
            }

            // Score badge around each swing's peak.
            if let badge {
                drawBadge(badge.label, color: badge.color, size: size, scale: scale)
            }
        }
        return image.cgImage ?? base
    }

    private nonisolated static func drawBadge(_ label: String,
                                              color: UIColor,
                                              size: CGSize,
                                              scale: CGFloat) {
        let fontSize = max(15, 24 * scale)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let attributed = NSAttributedString(string: label, attributes: attrs)
        let textSize = attributed.size()
        let padH = 14 * scale, padV = 8 * scale
        let margin = max(10, 16 * scale)
        let rect = CGRect(
            x: size.width - textSize.width - padH * 2 - margin,
            y: margin,
            width: textSize.width + padH * 2,
            height: textSize.height + padV * 2)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        color.withAlphaComponent(0.9).setFill()
        path.fill()
        attributed.draw(at: CGPoint(x: rect.minX + padH, y: rect.minY + padV))
    }

    private nonisolated static func drawHUD(metric: FrameMetrics,
                                            hittingArm: HittingArm,
                                            size: CGSize,
                                            scale: CGFloat) {
        func f(_ x: Double, _ d: Int = 0) -> String { x.isFinite ? String(format: "%.\(d)f", x) : "—" }
        // No px/s in user-facing output — wrist speed is uncalibrated pixels.
        let line1 = "t=\(f(metric.timeS, 2))s   knee L/R=\(f(metric.kneeL))/\(f(metric.kneeR))°"
        let line2 = "lean=\(f(metric.torsoLean))°   stance=\(f(metric.stanceRatio, 2))×"
        let text = line1 + "\n" + line2

        let fontSize = max(13, 20 * scale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black.withAlphaComponent(0.85),
            .strokeWidth: -2.0,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let margin = max(10, 16 * scale)
        let textSize = attributed.size()
        let bgRect = CGRect(
            x: margin - 6, y: margin - 4,
            width: min(size.width - margin, textSize.width) + 12,
            height: textSize.height + 8)
        let bg = UIBezierPath(roundedRect: bgRect, cornerRadius: 8 * scale)
        UIColor.black.withAlphaComponent(0.35).setFill()
        bg.fill()
        attributed.draw(at: CGPoint(x: margin, y: margin))
    }

    private nonisolated static func makePixelBuffer(from image: CGImage,
                                                    pool: CVPixelBufferPool,
                                                    width: Int,
                                                    height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
