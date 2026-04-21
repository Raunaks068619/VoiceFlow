import Foundation
import Combine

// MARK: - Wire models

/// Stargazer payload when we pass `Accept: application/vnd.github.v3.star+json`.
/// Shape: `{ starred_at: "2024-...", user: { login, avatar_url, html_url, id } }`.
struct GitHubStargazer: Codable, Identifiable, Equatable {
    let starredAt: String
    let user: GitHubUser

    var id: Int { user.id }

    enum CodingKeys: String, CodingKey {
        case starredAt = "starred_at"
        case user
    }
}

struct GitHubUser: Codable, Equatable {
    let id: Int
    let login: String
    let avatarUrl: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case id, login
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
    }

    /// GitHub allows `?s=64` for a 2x crisp thumbnail at 22pt.
    var avatarThumbnailUrl: URL? {
        URL(string: "\(avatarUrl)&s=64")
            ?? URL(string: "\(avatarUrl)?s=64")
    }
}

private struct GitHubRepoResponse: Codable {
    let stargazersCount: Int

    enum CodingKeys: String, CodingKey {
        case stargazersCount = "stargazers_count"
    }
}

// MARK: - Persisted cache shape

private struct CachedMetadata: Codable {
    let starCount: Int
    let recentStargazers: [GitHubStargazer]
    let fetchedAt: Date
}

/// Lightweight GitHub metadata fetcher for the star-ask card.
///
/// Why a singleton ObservableObject:
///   - One network fetch covers every view that renders the card
///     (right now just MainDashboardView, but the onboarding flow will reuse).
///   - GitHub's unauthenticated REST API is capped at 60 req/hr per IP.
///     Caching is mandatory; a 6-hour TTL is plenty for a star count that
///     changes ~hourly at best.
///   - Cache persisted in UserDefaults so cold launches show *something*
///     instead of a spinner, and we only hit GitHub once per work session.
///
/// Failure model: any network/decoding error silently falls back to the
/// cached value (if any). This is a cosmetic card — we never want it to
/// block the UI or log scary errors during someone's first launch.
///
/// Not actor-isolated: SwiftUI drives @Published access on main, and the
/// async fetch path uses Task without hopping actors. Mutations happen
/// inside `fetchAll` which is called from Task.init (inherits caller's
/// context, which for our call sites is main via SwiftUI's .task).
final class GitHubMetadataCache: ObservableObject {
    static let shared = GitHubMetadataCache()

    // Public repo — safe to hardcode.
    static let repoOwner = "Raunaks068619"
    static let repoName = "VoiceFlow"
    static let repoHTMLURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)")!

    @Published private(set) var starCount: Int?
    @Published private(set) var recentStargazers: [GitHubStargazer] = []
    @Published private(set) var isLoading: Bool = false

    private let cacheKey = "github_metadata_cache_v1"
    private let cacheTTL: TimeInterval = 6 * 60 * 60  // 6 hours
    private let session: URLSession
    private var inflight: Task<Void, Never>?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        loadFromDisk()
    }

    /// Call from any view's `.task` / `.onAppear`. Dedupes concurrent calls.
    /// Skips the network hit entirely if cache is still warm.
    func refreshIfStale() {
        if let cache = readCache(), !isStale(cache) {
            return
        }
        refresh()
    }

    /// Force refresh — used by a pull-to-refresh gesture if we ever add one.
    /// Currently not wired to UI, but cheap to expose.
    func refresh() {
        if inflight != nil { return }
        inflight = Task { [weak self] in
            await self?.fetchAll()
        }
    }

    // MARK: - Private

    private func fetchAll() async {
        self.isLoading = true
        defer {
            self.isLoading = false
            self.inflight = nil
        }

        // Run repo + stargazers in parallel. If either fails we keep the old value.
        async let repo = fetchRepo()
        async let stars = fetchStargazers()
        let (newCount, newStars) = await (repo, stars)

        if let newCount {
            self.starCount = newCount
        }
        if let newStars {
            self.recentStargazers = newStars
        }
        persistCache()
    }

    private func fetchRepo() async -> Int? {
        let url = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("VoiceFlow-macOS", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(GitHubRepoResponse.self, from: data)
            return decoded.stargazersCount
        } catch {
            return nil
        }
    }

    private func fetchStargazers() async -> [GitHubStargazer]? {
        // Stargazers are returned oldest-first; we need newest. Fetch last page.
        // Simpler: fetch first page with direction hack via Link header is
        // unavailable, so grab a wide page and take the tail.
        // For a repo with <30 stars this is a single request; for larger repos
        // we still get the N most recent by reading the last page.
        //
        // Strategy: fetch page 1 with per_page=100. If response has Link rel="last",
        // re-fetch that page and take the last 12 entries. This caps us at 2 requests.
        let base = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/stargazers"
        let firstURL = URL(string: "\(base)?per_page=100")!
        var req = URLRequest(url: firstURL)
        req.setValue("application/vnd.github.v3.star+json", forHTTPHeaderField: "Accept")
        req.setValue("VoiceFlow-macOS", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let decoder = JSONDecoder()
            let firstPage = try decoder.decode([GitHubStargazer].self, from: data)

            // Try to find last page link. If absent, firstPage IS the complete list.
            if let linkHeader = http.value(forHTTPHeaderField: "Link"),
               let lastURL = parseLastPageURL(from: linkHeader),
               lastURL != firstURL {
                var lastReq = URLRequest(url: lastURL)
                lastReq.setValue("application/vnd.github.v3.star+json", forHTTPHeaderField: "Accept")
                lastReq.setValue("VoiceFlow-macOS", forHTTPHeaderField: "User-Agent")
                let (lastData, lastResp) = try await session.data(for: lastReq)
                guard let lastHttp = lastResp as? HTTPURLResponse, lastHttp.statusCode == 200 else {
                    return Array(firstPage.suffix(12).reversed())
                }
                let lastPage = try decoder.decode([GitHubStargazer].self, from: lastData)
                return Array(lastPage.suffix(12).reversed())
            }

            return Array(firstPage.suffix(12).reversed())
        } catch {
            return nil
        }
    }

    /// Parse `<url>; rel="last"` from the Link header.
    private func parseLastPageURL(from header: String) -> URL? {
        let parts = header.split(separator: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("rel=\"last\"") {
                if let start = trimmed.firstIndex(of: "<"),
                   let end = trimmed.firstIndex(of: ">"),
                   start < end {
                    let urlStr = String(trimmed[trimmed.index(after: start)..<end])
                    return URL(string: urlStr)
                }
            }
        }
        return nil
    }

    // MARK: - Cache persistence

    private func loadFromDisk() {
        guard let cache = readCache() else { return }
        self.starCount = cache.starCount
        self.recentStargazers = cache.recentStargazers
    }

    private func readCache() -> CachedMetadata? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(CachedMetadata.self, from: data)
    }

    private func isStale(_ cache: CachedMetadata) -> Bool {
        Date().timeIntervalSince(cache.fetchedAt) > cacheTTL
    }

    private func persistCache() {
        guard let count = starCount else { return }
        let cache = CachedMetadata(
            starCount: count,
            recentStargazers: recentStargazers,
            fetchedAt: Date()
        )
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
