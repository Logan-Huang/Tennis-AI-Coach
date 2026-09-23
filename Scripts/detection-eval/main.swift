// Stroke detection evaluation runner — see README.md in this folder.
// Runs the full engine (player tracker, pose, audio) on each clip and writes
// each AnalysisResult as JSON for score.py.
// env ARM=right|left stands in for a profile's racquet hand; NOAUDIO=1 skips
// the soundtrack (pose-only fallback).
import Foundation
import AVFoundation
let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args[1])
let videos = args.dropFirst(2).map { URL(fileURLWithPath: $0) }
let env = ProcessInfo.processInfo.environment
let sem = DispatchSemaphore(value: 0)
Task.detached {
    for url in videos {
        let t0 = Date()
        do {
            let source = try await VideoSource.load(url: url)
            var config = AnalysisConfig.default
            if let a = env["ARM"] { config.hittingArm = HittingArm(rawValue: a) }
            let onsets = env["NOAUDIO"] == nil ? await AudioOnsets.detect(asset: source.asset, videoStartS: source.startS) : []
            let result = try AnalysisPipeline.run(source: source, config: config, onsets: onsets, progress: { _ in })
            let dt = Date().timeIntervalSince(t0)
            let tracked = result.poses.filter { $0.hasAnyJoint }.count
            print("== \(url.lastPathComponent) frames=\(result.frames.count) tracked=\(tracked) onsets=\(onsets.count) arm=\(result.hittingArm.rawValue) strokes=\(result.strokes.count) (\(String(format: "%.1f", dt))s)")
            for s in result.strokes {
                func f(_ x: Double?) -> String { guard let x, x.isFinite else { return "  —" }; return String(format: "%5.2f", x) }
                print(String(format: "   %6.2f %-12@ %-9@ spd=%5.1f knee=%@ load=%@ elbow=%@ reach=%@ finish=%@", s.peakTime, (s.kind?.rawValue ?? "?") as NSString, (s.timing?.rawValue ?? "?") as NSString, s.peakSpeed, f(s.minKnee), f(s.loadKnee), f(s.elbowMed), f(s.reach), f(s.finish)))
            }
            let data = try AnalysisCoders.makeEncoder().encode(result)
            try data.write(to: outDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".json"))
        } catch {
            print("== \(url.lastPathComponent) FAILED: \(error)")
        }
    }
    sem.signal()
}
sem.wait()
