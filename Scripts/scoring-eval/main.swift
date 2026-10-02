// Scoring evaluation runner — see README.md in this folder.
// Scores saved AnalysisResult JSON files (from Scripts/detection-eval, or a
// session's result) with the app's ShotScorer and prints every component.
import Foundation

func f(_ x: Double, _ spec: String = "%5.1f") -> String { x.isFinite ? String(format: spec, x) : "    —" }

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    do {
        let result = try AnalysisCoders.makeDecoder().decode(AnalysisResult.self, from: Data(contentsOf: url))
        let shots = ShotScorer.score(result: result)
        let session = ShotScorer.sessionScore(shots)
        print("== \(url.lastPathComponent)  session \(f(session.overall))  (\(session.gradedShots)/\(session.totalShots) graded)")
        for (stroke, shot) in zip(result.strokes, shots) {
            let parts = shot.components.map { c in
                "\(c.kind.rawValue)=\(f(c.score, "%.0f"))[\(Fmt.raw(c))]"
            }
            print(String(format: "   #%d %@ %6.2fs  overall %@   ", stroke.id, (stroke.kind?.rawValue ?? "?") as NSString,
                         stroke.peakTime, f(shot.overall)) + parts.joined(separator: " "))
        }
    } catch {
        print("== \(url.lastPathComponent) FAILED: \(error)")
    }
}

enum Fmt {
    static func raw(_ c: ShotScoreComponent) -> String {
        guard c.rawValue.isFinite else { return "—" }
        switch c.kind {
        case .kineticChain, .reach, .finish, .stanceWidth: return String(format: "%.2f", c.rawValue)
        default: return String(format: "%.0f", c.rawValue)
        }
    }
}
