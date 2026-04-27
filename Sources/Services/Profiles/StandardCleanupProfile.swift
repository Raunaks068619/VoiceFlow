import Foundation

/// Default profile — wraps the existing WhisperService polish pipeline.
///
/// **Why have it at all** when the legacy code path still works?
/// The router needs every output path to look identical so downstream
/// (RunRecorder, TextInjector) can be branch-free. This is the adapter
/// from the new TransformerProfile shape to the legacy callbacks.
///
/// **Note on call shape**: this profile does NOT do its own STT. STT
/// happens upstream; we accept the raw transcript and run the polish step.
/// That's the contract every profile honors.
final class StandardCleanupProfile: TransformerProfile {
    let kind: ProfileKind = .standardCleanup
    let displayLabel = ProfileKind.standardCleanup.displayLabel

    private let whisper: WhisperService

    init(whisper: WhisperService) {
        self.whisper = whisper
    }

    func transform(
        _ input: TransformerInput,
        completion: @escaping (Result<TransformerOutput, Error>) -> Void
    ) {
        // Legacy path: hand to WhisperService.polishOnlyWithMetadata so we
        // get exactly the existing semantics (Hindi guardrails, fast-path
        // skip, hallucination filter).
        whisper.polishOnlyWithMetadata(
            rawTranscript: input.rawTranscript,
            providerLabel: "router/standard",
            transcriptionLatencyMs: 0,        // already measured upstream
            style: input.style,
            processingMode: input.mode
        ) { result in
            switch result {
            case .success(let metadata):
                let trace: [String] = [
                    "Profile: standard cleanup",
                    "Style: \(metadata.postProcessStyle ?? "n/a")",
                    "Mode: \(metadata.postProcessMode ?? "n/a")",
                    "Model: \(metadata.postProcessModel ?? "n/a")",
                ]
                let output = TransformerOutput(
                    finalText: metadata.finalText,
                    summary: "Standard cleanup",
                    modelUsed: metadata.postProcessModel,
                    costUSD: 0,                 // polish path doesn't track cost yet
                    llmLatencyMs: metadata.postProcessLatencyMs,
                    usedAgentic: false,
                    trace: trace
                )
                completion(.success(output))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
