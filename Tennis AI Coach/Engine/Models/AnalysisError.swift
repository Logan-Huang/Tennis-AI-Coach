//
//  AnalysisError.swift
//  Tennis AI Coach
//

import Foundation

nonisolated enum AnalysisError: LocalizedError, Sendable {
    case unreadableVideo
    case zeroDimensions
    case noFramesDecoded
    case videoTooShort
    case decodeFailed(String?)
    case exportFailed(String?)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "This video couldn't be opened. Try a different clip."
        case .zeroDimensions:
            return "The video has no usable picture dimensions."
        case .noFramesDecoded:
            return "No frames could be read from this video."
        case .videoTooShort:
            return "This clip is too short to analyze. Record at least a few seconds of play."
        case .decodeFailed(let why):
            return why ?? "The video could not be decoded."
        case .exportFailed(let why):
            return why ?? "The annotated video could not be exported."
        case .cancelled:
            return "Analysis was cancelled."
        }
    }
}
