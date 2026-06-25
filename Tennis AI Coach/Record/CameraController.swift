//
//  CameraController.swift
//  Tennis AI Coach
//
//  AVCaptureSession orchestration. UI-facing state lives on the main actor;
//  all session mutation/start/stop runs on a dedicated serial queue (the AV
//  objects it touches are queue-confined and marked nonisolated(unsafe)).
//

import Foundation
import AVFoundation
import Observation

@Observable
@MainActor
final class CameraController: NSObject, AVCaptureFileOutputRecordingDelegate {

    enum Permission { case unknown, authorized, denied }

    // UI state (main actor).
    var permission: Permission = .unknown
    var isRecording = false
    var recordedURL: URL?
    var cameraPosition: AVCaptureDevice.Position = .back
    var elapsed: TimeInterval = 0

    // Queue-confined capture objects.
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var isConfigured = false

    private let sessionQueue = DispatchQueue(label: "tennis.camera.session")
    private var startDate: Date?
    private var timer: Timer?

    // MARK: - Lifecycle

    func prepare() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            permission = granted ? .authorized : .denied
        default:
            permission = .denied
        }
        if permission == .authorized {
            startSession()
        }
    }

    func startSession() {
        let position = cameraPosition
        sessionQueue.async { [self] in
            configureIfNeeded(position: position)
            if !session.isRunning { session.startRunning() }
        }
    }

    func stopSession() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func toggleCamera() {
        let newPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        cameraPosition = newPosition
        sessionQueue.async { [self] in
            session.beginConfiguration()
            if let videoInput { session.removeInput(videoInput) }
            if let device = Self.camera(for: newPosition),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            }
            session.commitConfiguration()
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        startDate = Date()
        startTimer()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec_\(UUID().uuidString).mov")
        let mirror = cameraPosition == .front
        sessionQueue.async { [self] in
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirror
                }
            }
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [self] in
            movieOutput.stopRecording()
        }
    }

    func resetForRetake() {
        recordedURL = nil
        elapsed = 0
    }

    // MARK: - Delegate (nonisolated Obj-C callback)

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.stopTimer()
            if error == nil {
                self.recordedURL = outputFileURL
            }
        }
    }

    // MARK: - Helpers

    nonisolated private func configureIfNeeded(position: AVCaptureDevice.Position) {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = Self.camera(for: position),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        }
        if let audio = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        session.commitConfiguration()
        isConfigured = true
    }

    nonisolated private static func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
