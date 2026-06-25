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

            let annotated = renderFrame(
                base: baseImage, size: oriented,
                pose: posesByFrame[rawIndex],
                metric: metricsByFrame[rawIndex],
                hittingArm: result.hittingArm,
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

    private nonisolated static func renderFrame(base: CGImage,
                                                size: CGSize,
                                                pose: PoseFrame?,
                                                metric: FrameMetrics?,
                                                hittingArm: HittingArm,
                                                scale: CGFloat) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { rendererContext in
            let cg = rendererContext.cgContext

            // Upright source frame (UIImage.draw handles the CG flip).
            UIImage(cgImage: base).draw(in: CGRect(origin: .zero, size: size))

            // Skeleton.
            if let pose {
                let pts: [CGPoint?] = pose.points.map { normalized in
                    normalized.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                }
                cg.setLineCap(.round)
                cg.setLineWidth(max(2, 3 * scale))
                cg.setStrokeColor(UIColor.systemGreen.cgColor)
                for (a, b) in JointMapping.boneIndices {
                    if a < pts.count, b < pts.count, let pa = pts[a], let pb = pts[b] {
                        cg.move(to: pa)
                        cg.addLine(to: pb)
                        cg.strokePath()
                    }
                }
                let radius = max(2, 4 * scale)
                cg.setFillColor(UIColor.white.cgColor)
                for case let point? in pts {
                    cg.fillEllipse(in: CGRect(
                        x: point.x - radius, y: point.y - radius,
                        width: radius * 2, height: radius * 2))
                }
            }

            // Metric HUD.
            if let metric {
                drawHUD(metric: metric, hittingArm: hittingArm, size: size, scale: scale)
            }
        }
        return image.cgImage ?? base
    }

    private nonisolated static func drawHUD(metric: FrameMetrics,
                                            hittingArm: HittingArm,
                                            size: CGSize,
                                            scale: CGFloat) {
        func f(_ x: Double, _ d: Int = 0) -> String { x.isFinite ? String(format: "%.\(d)f", x) : "—" }
        let line1 = "t=\(f(metric.timeS, 2))s   knee L/R=\(f(metric.kneeL))/\(f(metric.kneeR))°"
        let line2 = "lean=\(f(metric.torsoLean))°   stance=\(f(metric.stanceRatio, 2))   wrist=\(f(metric.wristSpeed(for: hittingArm))) px/s"
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
