//
//  LibraryStore.swift
//  Tennis AI Coach
//
//  Source of truth for players and their saved analysis sessions. Persists
//  each session's result (JSON) and a copy of its video into Application
//  Support, and the players alongside them.
//
//  Everything the UI reads — `sessions`, the trend, storage — is the ACTIVE
//  player's. Switching player switches all of it; nothing outside this file
//  has to know other players exist.
//

import Foundation
import SwiftUI

struct Session: Identifiable, Sendable {
    let id: UUID
    var createdAt: Date
    /// The player this session belongs to.
    var profileID: UUID
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
    /// `nil` in records written before there were players; those belong to
    /// the first player, and are rewritten with their id on first load.
    var profileID: UUID?
}

@Observable
@MainActor
final class LibraryStore {
    private(set) var profiles: [PlayerProfile] = []
    private(set) var activeProfileID: UUID

    /// Every player's sessions, newest first.
    private var allSessions: [Session] = []

    /// The active player's sessions, newest first.
    var sessions: [Session] {
        allSessions.filter { $0.profileID == activeProfileID }
    }

    var activeProfile: PlayerProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    private let fileManager = FileManager.default
    private let encoder = AnalysisCoders.makeEncoder()
    private let decoder = AnalysisCoders.makeDecoder()
    private let defaults: UserDefaults

    /// Lazily computed, never persisted — legacy session JSON stays untouched.
    private var scoreCache: [UUID: (session: SessionScore, shots: [ShotScore])] = [:]

    private static let activeProfileKey = "activeProfileID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeProfileID = UUID()   // placeholder until the players are loaded
        createDirectories()
        loadProfiles()
        load()
        purgeWorkingFiles()
    }

    // MARK: - Sessions

    /// Any player's session — a route may outlive a player switch.
    func session(id: UUID) -> Session? {
        allSessions.first { $0.id == id }
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

    /// Oldest-first cross-session trend (speed-excluded form scores) for the
    /// active player.
    func progressTrend() -> [ProgressEngine.SessionProgress] {
        ProgressEngine.trend(sessions: sessions.map {
            ($0.id, $0.createdAt, scores(for: $0).shots)
        })
    }

    /// Recent range + current value per form component, active player.
    func componentTrends() -> [ProgressEngine.ComponentTrend] {
        ProgressEngine.componentTrends(sessions: sessions.map {
            ($0.id, $0.createdAt, scores(for: $0).shots)
        })
    }

    /// Copy the analyzed video into the library, persist the result, and return
    /// the new session — `player`'s, or the active player's (prepended to the list).
    @discardableResult
    func addSession(sourceVideoURL: URL, result: AnalysisResult, for player: PlayerProfile? = nil) -> Session {
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

        let owner = player.flatMap { p in profiles.first { $0.id == p.id } }?.id ?? activeProfileID
        let session = Session(id: id, createdAt: Date(), profileID: owner,
                              videoURL: storedURL, result: result)
        allSessions.insert(session, at: 0)
        write(session, videoFileName: videoFileName)
        return session
    }

    func delete(_ session: Session) {
        scoreCache[session.id] = nil
        allSessions.removeAll { $0.id == session.id }
        try? fileManager.removeItem(at: recordURL(session.id))
        if let videoURL = session.videoURL {
            try? fileManager.removeItem(at: videoURL)
        }
    }

    /// Give a session to another player — for the clip that was recorded
    /// while the wrong player was selected.
    func move(_ session: Session, to profile: PlayerProfile) {
        guard profile.id != session.profileID,
              let i = allSessions.firstIndex(where: { $0.id == session.id }) else { return }
        allSessions[i].profileID = profile.id
        rewriteRecord(of: allSessions[i])
    }

    // MARK: - Players

    /// How many sessions a player has — for the switcher, which shows every
    /// player, not just the active one.
    func sessionCount(for profile: PlayerProfile) -> Int {
        allSessions.count { $0.profileID == profile.id }
    }

    /// No player on this device has a session yet.
    var isEmpty: Bool { allSessions.isEmpty }

    /// A player's most recent graded form score, NaN if none.
    func latestFormScore(for profile: PlayerProfile) -> Double {
        let mine = allSessions.filter { $0.profileID == profile.id }
        let trend = ProgressEngine.trend(sessions: mine.map { ($0.id, $0.createdAt, scores(for: $0).shots) })
        return trend.last(where: { $0.formScore.isFinite })?.formScore ?? .nan
    }

    func switchTo(_ profile: PlayerProfile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        activeProfileID = profile.id
        defaults.set(profile.id.uuidString, forKey: Self.activeProfileKey)
    }

    /// Add a player and make them the active one.
    @discardableResult
    func addProfile(name: String, hand: HittingArm?, colorIndex: Int? = nil) -> PlayerProfile {
        let profile = PlayerProfile(
            name: String(name.prefix(PlayerProfile.nameLimit)),
            hand: hand,
            colorIndex: colorIndex ?? ProfilePalette.nextIndex(after: profiles))
        profiles.append(profile)
        saveProfiles()
        switchTo(profile)
        return profile
    }

    func update(_ profile: PlayerProfile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.name = String(profile.name.prefix(PlayerProfile.nameLimit))
        profiles[i] = updated
        saveProfiles()
    }

    /// Remove a player and everything of theirs. The last player can't be
    /// removed — there is always someone the next recording belongs to.
    func deleteProfile(_ profile: PlayerProfile) {
        guard profiles.count > 1, profiles.contains(where: { $0.id == profile.id }) else { return }
        for session in allSessions where session.profileID == profile.id {
            delete(session)
        }
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
        if activeProfileID == profile.id, let first = profiles.first {
            switchTo(first)
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
        if let i = allSessions.firstIndex(where: { $0.id == session.id }) {
            allSessions[i].videoURL = nil
        }
    }

    /// Bytes the clip occupies, or zero once it has been discarded.
    func videoBytes(_ session: Session) -> Int64 {
        guard let url = session.videoURL,
              let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64
        else { return 0 }
        return size
    }

    /// The active player's footage.
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
    private var profilesURL: URL { baseDir.appendingPathComponent("profiles.json") }

    private func recordURL(_ id: UUID) -> URL {
        recordsDir.appendingPathComponent("\(id.uuidString).json")
    }

    private func createDirectories() {
        for dir in [recordsDir, videosDir] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Players, or a first one when there are none yet. That first player is
    /// who everything recorded before players existed belongs to; they're
    /// named when the app asks (ProfileEditorView), not here.
    private func loadProfiles() {
        if let data = try? Data(contentsOf: profilesURL),
           let saved = try? JSONDecoder().decode([PlayerProfile].self, from: data),
           !saved.isEmpty {
            profiles = saved
        } else {
            profiles = [PlayerProfile(name: "", hand: nil, colorIndex: 0)]
            saveProfiles()
        }
        let saved = defaults.string(forKey: Self.activeProfileKey).flatMap(UUID.init(uuidString:))
        activeProfileID = profiles.first { $0.id == saved }?.id ?? profiles[0].id
    }

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: profilesURL, options: .atomic)
    }

    private func load() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: recordsDir, includingPropertiesForKeys: nil) else { return }
        let known = Set(profiles.map(\.id))
        let fallback = profiles[0].id
        var loaded: [Session] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  var record = try? decoder.decode(SessionRecord.self, from: data) else { continue }
            // A missing clip used to drop the whole session, taking its score
            // and its place in the trend with it. Now it just means the video
            // was discarded.
            let videoURL = videosDir.appendingPathComponent(record.videoFileName)
            let stored = fileManager.fileExists(atPath: videoURL.path) ? videoURL : nil
            // Sessions from before there were players, or whose player is
            // gone, go to the first player — once, on disk.
            if record.profileID.map(known.contains) != true {
                record.profileID = fallback
                if let data = try? encoder.encode(record) {
                    try? data.write(to: file, options: .atomic)
                }
            }
            loaded.append(Session(id: record.id, createdAt: record.createdAt,
                                  profileID: record.profileID ?? fallback,
                                  videoURL: stored, result: record.result))
        }
        allSessions = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    private func write(_ session: Session, videoFileName: String) {
        let record = SessionRecord(id: session.id, createdAt: session.createdAt,
                                   videoFileName: videoFileName, result: session.result,
                                   profileID: session.profileID)
        if let data = try? encoder.encode(record) {
            try? data.write(to: recordURL(session.id), options: .atomic)
        }
    }

    /// Re-save a session's record after its player changed. The record's
    /// video filename is read back from disk, because a discarded video's
    /// session no longer knows it.
    private func rewriteRecord(of session: Session) {
        let url = recordURL(session.id)
        guard let data = try? Data(contentsOf: url),
              var record = try? decoder.decode(SessionRecord.self, from: data) else { return }
        record.profileID = session.profileID
        if let out = try? encoder.encode(record) {
            try? out.write(to: url, options: .atomic)
        }
    }
}
