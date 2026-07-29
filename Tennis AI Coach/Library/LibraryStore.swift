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
    var videoURL: URL
    var result: AnalysisResult

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
        try? fileManager.removeItem(at: session.videoURL)
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
            let videoURL = videosDir.appendingPathComponent(record.videoFileName)
            guard fileManager.fileExists(atPath: videoURL.path) else { continue }
            loaded.append(Session(id: record.id, createdAt: record.createdAt,
                                  videoURL: videoURL, result: record.result))
        }
        sessions = loaded.sorted { $0.createdAt > $1.createdAt }
    }
}
