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
        guard oriented.width > 0, oriented.height > 0 else {
            throw AnalysisError.exportFailed("Invalid video size.")
        }

        // The export is capped at 1080p. A 4K frame costs about 33 MB three
        // times over — decoded, drawn, and encoded — and a phone recording at
        // 60fps supplies hundreds of them. Every destination the clip can be
        // shared to recompresses it well below this anyway, so the resolution
        // buys nothing and costs the memory the render was being killed for.
        let longEdge = max(oriented.width, oriented.height)
        let fit = min(1.0, 1920.0 / longEdge)
        let width = evenSide(oriented.width * fit)
        let height = evenSide(oriented.height * fit)
        let exportSize = CGSize(width: Double(width), height: Double(height))
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
        // Both keyed by raw frame index, and both tolerate a repeat. A stored
        // result is only ever read back here, so a duplicated index from an odd
        // clip should cost a frame's annotation, not the whole export.
        let metricsByFrame = Dictionary(
            result.frames.map { ($0.frameIndex, $0) }, uniquingKeysWith: { a, _ in a })

        // Intermediates are never reused across frames here, so caching them
        // only grows the footprint.
        let ciContext = CIContext(options: [.cacheIntermediates: false])
        let outFPS = source.fps / Double(stride)
        let drawScale = max(0.5, exportSize.height / 1080.0)
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

        var reachedEnd = false
        var appendFailed = false

        while reader.status == .reading, !reachedEnd, !appendFailed {
            if Task.isCancelled {
                reader.cancelReading()
                input.markAsFinished()
                writer.cancelWriting()
                throw AnalysisError.cancelled
            }
            // Waiting for the encoder has to happen out here: `await` cannot
            // cross into the non-escaping closure below.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            // One pool per frame. Without it the decoded sample, the CGImage,
            // the rendered frame and the output buffer all stay alive until the
            // loop ends, because nothing in a tight loop inside an async
            // function drains the enclosing pool. Over a few hundred frames
            // that reaches gigabytes, and the app is killed with no crash
            // report — it simply disappears.
            autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else {
                    reachedEnd = true
                    return
                }
                let index = rawIndex
                rawIndex += 1
                guard index % stride == 0,
                      let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return }

                // Scale on the GPU while it is still a CIImage, so a
                // full-resolution CGImage is never materialised.
                let orientedCI = CIImage(cvPixelBuffer: pixelBuffer).oriented(source.orientation)
                let shrink = exportSize.width / orientedCI.extent.width
                let sourceCI = shrink < 1
                    ? orientedCI.transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
                    : orientedCI
                guard let baseImage = ciContext.createCGImage(sourceCI, from: sourceCI.extent) else { return }

                let frameTime = metricsByFrame[index]?.timeS
                let badge = frameTime.flatMap { t in
                    badges.first { abs($0.peakTime - t) <= 0.4 }
                }
                let annotated = renderFrame(
                    base: baseImage, size: exportSize,
                    pose: posesByFrame[index],
                    metric: metricsByFrame[index],
                    hittingArm: result.hittingArm,
                    badge: badge.map { ($0.label, $0.color) },
                    scale: drawScale)

                guard let pool = adaptor.pixelBufferPool,
                      let outBuffer = makePixelBuffer(from: annotated, pool: pool,
                                                      width: width, height: height) else { return }
                let pts = CMTimeMakeWithSeconds(Double(processedIndex) / outFPS, preferredTimescale: 600)
                guard adaptor.append(outBuffer, withPresentationTime: pts) else {
                    // Carrying on here would finish the write and hand back a
                    // video that silently stops early.
                    appendFailed = true
                    return
                }
                processedIndex += 1
            }

            if processedIndex % 4 == 0 {
                progress(min(0.99, Double(processedIndex) / Double(estProcessed)))
            }
        }

        if appendFailed {
            reader.cancelReading()
            input.markAsFinished()
            writer.cancelWriting()
            throw AnalysisError.exportFailed(
                writer.error?.localizedDescription ?? "A frame couldn't be written.")
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

    /// H.264 requires even dimensions, so round down to one.
    private nonisolated static func evenSide(_ value: Double) -> Int {
        let n = Int(value.rounded())
        return n - (n % 2)
    }

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
