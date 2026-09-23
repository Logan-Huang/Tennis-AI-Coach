//
//  LibraryStore.swift
//  Tennis AI Coach
//
//  Source of truth for saved analysis sessions. Persists each session's result
//  (JSON) and a copy of its video into Application Support.
//

import Foundation
import SwiftUI

struct Session: Identifiable, Sendable {
    let id: UUID
    var createdAt: Date
    /// `nil` once the clip has been discarded to reclaim space. The analysis is
    /// a rounding error next to the video it came from, so a session outlives
    /// its footage: the scores, the trend and the comparison all still work.
    var videoURL: URL?
    var result: AnalysisResult

    var hasVideo: Bool { videoURL != nil }

    var title: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

/// On-disk record (the video is stored separately by filename).
private struct SessionRecord: Codable {
    let id: UUID
    let createdAt: Date
    let videoFileName: String
    let result: AnalysisResult
}

@Observable
@MainActor
final class LibraryStore {
    private(set) var sessions: [Session] = []

    private let fileManager = FileManager.default
    private let encoder = AnalysisCoders.makeEncoder()
    private let decoder = AnalysisCoders.makeDecoder()

    /// Lazily computed, never persisted — legacy session JSON stays untouched.
    private var scoreCache: [UUID: (session: SessionScore, shots: [ShotScore])] = [:]

    init() {
        createDirectories()
        load()
        purgeWorkingFiles()
    }

    // MARK: - Public API

    func session(id: UUID) -> Session? {
        sessions.first { $0.id == id }
    }

    /// Per-session scores, cached after first computation.
    func scores(for session: Session) -> (session: SessionScore, shots: [ShotScore]) {
        if let cached = scoreCache[session.id] { return cached }
        let shots = ShotScorer.score(result: session.result)
        let rollup = ShotScorer.sessionScore(shots)
        let entry = (session: rollup, shots: shots)
        scoreCache[session.id] = entry
        return entry
    }

    /// Oldest-first cross-session trend (speed-excluded form scores).
    func progressTrend() -> [ProgressEngine.SessionProgress] {
        ProgressEngine.trend(sessions: sessions.map {
            ($0.id, $0.createdAt, scores(for: $0).shots)
        })
    }

    /// Recent range + current value per form component.
    func componentTrends() -> [ProgressEngine.ComponentTrend] {
        ProgressEngine.componentTrends(sessions: sessions.map {
            ($0.id, $0.createdAt, scores(for: $0).shots)
        })
    }

    /// Copy the analyzed video into the library, persist the result, and return
    /// the new session (prepended to the list).
    @discardableResult
    func addSession(sourceVideoURL: URL, result: AnalysisResult) -> Session {
        let id = UUID()
        let ext = sourceVideoURL.pathExtension.isEmpty ? "mov" : sourceVideoURL.pathExtension
        let videoFileName = "\(id.uuidString).\(ext)"
        let destURL = videosDir.appendingPathComponent(videoFileName)

        try? fileManager.removeItem(at: destURL)
        do {
            try fileManager.copyItem(at: sourceVideoURL, to: destURL)
        } catch {
            // Fall back to the original URL if the copy fails.
        }
        let storedURL = fileManager.fileExists(atPath: destURL.path) ? destURL : sourceVideoURL

        let session = Session(id: id, createdAt: Date(), videoURL: storedURL, result: result)
        sessions.insert(session, at: 0)

        let record = SessionRecord(id: id, createdAt: session.createdAt,
                                   videoFileName: videoFileName, result: result)
        if let data = try? encoder.encode(record) {
            try? data.write(to: recordsDir.appendingPathComponent("\(id.uuidString).json"))
        }
        return session
    }

    func delete(_ session: Session) {
        scoreCache[session.id] = nil
        sessions.removeAll { $0.id == session.id }
        try? fileManager.removeItem(at: recordsDir.appendingPathComponent("\(session.id.uuidString).json"))
        if let videoURL = session.videoURL {
            try? fileManager.removeItem(at: videoURL)
        }
    }

    // MARK: - Storage

    /// Throw away the clip and keep everything measured from it. A session's
    /// video is around three hundred times the size of its analysis, so this
    /// reclaims effectively all of the space while the score, the coaching and
    /// the session's place in the trend survive untouched.
    func discardVideo(_ session: Session) {
        guard let videoURL = session.videoURL else { return }
        try? fileManager.removeItem(at: videoURL)
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i].videoURL = nil
        }
    }

    /// Bytes the clip occupies, or zero once it has been discarded.
    func videoBytes(_ session: Session) -> Int64 {
        guard let url = session.videoURL,
              let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64
        else { return 0 }
        return size
    }

    var totalVideoBytes: Int64 {
        sessions.reduce(0) { $0 + videoBytes($1) }
    }

    var sessionsWithVideo: Int {
        sessions.count { $0.hasVideo }
    }

    /// Recording, importing and exporting each leave a full-size copy behind in
    /// the app's scratch space. iOS reclaims it eventually, on its own schedule,
    /// which on a phone full of sessions is far too late to be useful. Cleared
    /// at launch, when nothing is mid-flight.
    func purgeWorkingFiles() {
        let tmp = fileManager.temporaryDirectory
        guard let files = try? fileManager.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil) else { return }
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("rec_") || name.hasPrefix("import_")
                    || name.hasPrefix("annotated_") || name.hasPrefix("TennisAICoach-")
            else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    // MARK: - Persistence

    private var baseDir: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TennisAICoach", isDirectory: true)
    }
    private var recordsDir: URL { baseDir.appendingPathComponent("sessions", isDirectory: true) }
    private var videosDir: URL { baseDir.appendingPathComponent("videos", isDirectory: true) }

    private func createDirectories() {
        for dir in [recordsDir, videosDir] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func load() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: recordsDir, includingPropertiesForKeys: nil) else { return }
        var loaded: [Session] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(SessionRecord.self, from: data) else { continue }
            // A missing clip used to drop the whole session, taking its score
            // and its place in the trend with it. Now it just means the video
            // was discarded.
            let videoURL = videosDir.appendingPathComponent(record.videoFileName)
            let stored = fileManager.fileExists(atPath: videoURL.path) ? videoURL : nil
            loaded.append(Session(id: record.id, createdAt: record.createdAt,
                                  videoURL: stored, result: record.result))
        }
        sessions = loaded.sorted { $0.createdAt > $1.createdAt }
    }
}
