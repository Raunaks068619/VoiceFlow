import Foundation

// Minimal Codable mirrors of Vordi's on-disk JSON (Sources/Models/RunModel.swift).
// Intentionally a SUBSET — extra keys in the JSON are ignored, and these decode
// the same ISO8601 dates the app writes. Decoupled from the app target so the
// server stays a standalone binary.

struct RunSummaryLite: Codable {
    let id: UUID
    let createdAt: Date
    let durationSeconds: Double
    let status: String
    let previewText: String
    let frontmostAppName: String?
    let profileUsed: String?
    let wordCount: Int?
}

struct RunLite: Codable {
    let id: UUID
    let createdAt: Date
    let durationSeconds: Double
    let status: String
    let transcription: TranscriptionLite?
    let postProcessing: PostProcessingLite?
    let context: ContextLite?
    let profileUsed: String?
}

struct TranscriptionLite: Codable {
    let provider: String
    let rawText: String
    let latencyMs: Int
}

struct PostProcessingLite: Codable {
    let mode: String
    let style: String
    let model: String
    let finalText: String
    let latencyMs: Int
}

struct ContextLite: Codable {
    let frontmostAppName: String?
    let frontmostBundleID: String?
}
