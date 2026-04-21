import Foundation
import Combine

/// A locally-hosted LLM discovered on the user's machine.
struct LocalModel: Identifiable, Hashable {
    /// Stable unique key: "lmstudio:qwen/qwen3.5-9b" or "ollama:llama3.2".
    /// Shape matches the `PolishBackend.id` format so the same string can
    /// round-trip through UserDefaults without a parser.
    let id: String
    /// Display name returned by the provider (e.g. "qwen/qwen3.5-9b").
    let name: String
    let provider: LocalProvider
}

/// Supported local-model providers. Each exposes an OpenAI-compatible
/// /v1/chat/completions endpoint, so PolishBackend can reuse the cloud
/// code path with only the base URL swapped.
enum LocalProvider: String, Hashable, Codable {
    case lmstudio
    case ollama

    var label: String {
        switch self {
        case .lmstudio: return "LM Studio"
        case .ollama:   return "Ollama"
        }
    }

    /// Base URL for chat completions (OpenAI-compatible path).
    var baseURL: URL {
        switch self {
        case .lmstudio: return URL(string: "http://localhost:1234/v1")!
        case .ollama:   return URL(string: "http://localhost:11434/v1")!
        }
    }

    /// Provider-specific endpoint for listing installed models.
    /// LM Studio returns OpenAI-style `{data: [{id: ...}]}`;
    /// Ollama returns its own `{models: [{name: ...}]}` shape.
    fileprivate var modelsListURL: URL {
        switch self {
        case .lmstudio: return URL(string: "http://localhost:1234/v1/models")!
        case .ollama:   return URL(string: "http://localhost:11434/api/tags")!
        }
    }
}

/// Detects LLMs running locally on the user's machine via OpenAI-compatible
/// endpoints. Detection is best-effort — if a server isn't running, that
/// provider contributes zero models to the result set and no error surfaces.
/// Users can start their server and hit "Refresh" in Settings.
///
/// Singleton because detection state is app-wide and we want Settings to
/// reflect the latest known state without redoing detection on every open.
final class LocalModelDetector: ObservableObject {
    @Published private(set) var models: [LocalModel] = []
    @Published private(set) var isDetecting: Bool = false
    @Published private(set) var lastCheckedAt: Date?

    static let shared = LocalModelDetector()

    /// Probe timeout is aggressive — we don't want the Settings pane to
    /// feel stalled when neither server is running. If a model is actually
    /// up but slow to respond to /models, the user can retry.
    private let probeTimeout: TimeInterval = 1.5

    private init() {}

    /// Probes LM Studio and Ollama in parallel, merges the results, and
    /// publishes them on the main queue. Safe to call from any thread.
    func detect() {
        DispatchQueue.main.async { [weak self] in
            self?.isDetecting = true
        }

        let group = DispatchGroup()
        var aggregated: [LocalModel] = []
        let lock = NSLock()

        group.enter()
        probeLMStudio { models in
            lock.lock(); aggregated.append(contentsOf: models); lock.unlock()
            group.leave()
        }

        group.enter()
        probeOllama { models in
            lock.lock(); aggregated.append(contentsOf: models); lock.unlock()
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.models = aggregated.sorted { $0.name.lowercased() < $1.name.lowercased() }
            self.isDetecting = false
            self.lastCheckedAt = Date()
        }
    }

    // MARK: - Provider probes

    private func probeLMStudio(completion: @escaping ([LocalModel]) -> Void) {
        probe(url: LocalProvider.lmstudio.modelsListURL) { data in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]] else {
                completion([])
                return
            }
            let models = list.compactMap { entry -> LocalModel? in
                guard let id = entry["id"] as? String else { return nil }
                // Embedding models can't do chat-completions; filter them out.
                if Self.isEmbeddingModel(id) { return nil }
                return LocalModel(
                    id: "lmstudio::\(id)",
                    name: id,
                    provider: .lmstudio
                )
            }
            completion(models)
        }
    }

    private func probeOllama(completion: @escaping ([LocalModel]) -> Void) {
        probe(url: LocalProvider.ollama.modelsListURL) { data in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["models"] as? [[String: Any]] else {
                completion([])
                return
            }
            let models = list.compactMap { entry -> LocalModel? in
                guard let name = entry["name"] as? String else { return nil }
                if Self.isEmbeddingModel(name) { return nil }
                return LocalModel(
                    id: "ollama::\(name)",
                    name: name,
                    provider: .ollama
                )
            }
            completion(models)
        }
    }

    // MARK: - HTTP primitive

    /// Single short-timeout GET. Swallows all errors — any failure surfaces
    /// as "no models for this provider", which is the correct UX: users see
    /// only what's actually available, no scary error states.
    private func probe(url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = probeTimeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                completion(data)
            } else {
                completion(nil)
            }
        }.resume()
    }

    // MARK: - Heuristics

    /// Heuristic filter for embedding models — they can't handle chat
    /// completions, so surfacing them in the polish-model picker would be
    /// a footgun. Matches "embed", "embedding", "bge-*", etc.
    private static func isEmbeddingModel(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        return lower.contains("embed") ||
               lower.contains("embedding") ||
               lower.hasPrefix("bge-") ||
               lower.hasPrefix("nomic-")
    }
}
