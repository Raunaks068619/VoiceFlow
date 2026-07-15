import Foundation

/// Anonymous usage analytics via Aptabase.
///
/// Design rules (this is a dictation app — privacy is paramount):
///   • NEVER sends transcript content. Only event names + coarse, non-identifying
///     metadata (durations, provider name, word counts, app/OS version).
///   • Anonymous: identified only by a random `clientID` minted on first launch
///     and a per-process `sessionID`. No name/email.
///   • Opt-out honored: when `analytics_enabled` is false every call is a no-op.
///     Default is ON (anonymous-on) so we measure the whole population minus
///     explicit opt-outs.
///   • Fire-and-forget + fail-silent (but LOGGED): a failed POST never touches
///     the app, yet non-2xx / transport errors print to Console so a
///     misconfigured key/host can't fail invisibly.
///   • Dormant until configured: with an empty App Key `track()` is a no-op.
///
/// Aptabase ingest: events POST as JSON to `https://<region>.aptabase.com/api/v0/event`
/// with an `App-Key` header. Hosts are `eu.aptabase.com` / `us.aptabase.com`
/// (NO `api-` prefix). The App Key is write-only ingest — safe to embed in the
/// shipped app, same trust model as the embedded Groq key.
final class AnalyticsClient {
    static let shared = AnalyticsClient()

    // MARK: - Aptabase credentials
    //
    //   App Key:  Aptabase → your app → "App Key" (A-EU-… / A-US-… / A-SH-…)
    //   Host:     match the region the key encodes (A-EU- → eu, A-US- → us).
    private enum Aptabase {
        static let appKey = "A-EU-7257572944"
        static let ingestURL = URL(string: "https://eu.aptabase.com/api/v0/event")!

        static var isConfigured: Bool { !appKey.isEmpty }
    }

    private static let clientIDKey = "ga4_client_id"   // reused: stable per-install id
    static let analyticsEnabledKey = "analytics_enabled"

    /// Stable per-install anonymous id. Minted once, persisted.
    let clientID: String
    /// Per-process session id — Aptabase groups events into sessions by this.
    private let sessionID: String
    private let session: URLSession
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {
        if let existing = UserDefaults.standard.string(forKey: Self.clientIDKey) {
            clientID = existing
        } else {
            let minted = UUID().uuidString
            UserDefaults.standard.set(minted, forKey: Self.clientIDKey)
            clientID = minted
        }
        sessionID = UUID().uuidString
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Default opt-in (anonymous-on); honors an explicit opt-out.
    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.analyticsEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.analyticsEnabledKey)
    }

    /// Fire one event. No-op when opted out or unconfigured. Never blocks the
    /// caller; safe to call from anywhere including the main thread. `params`
    /// must contain ONLY bounded, content-free values (counts, enums, timings).
    func track(_ name: String, params: [String: Any] = [:]) {
        guard isEnabled, Aptabase.isConfigured else { return }

        let body: [String: Any] = [
            "timestamp": iso.string(from: Date()),
            "sessionId": sessionID,
            "eventName": Self.sanitizeName(name),
            "systemProps": Self.systemProps,
            "props": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: Aptabase.ingestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Aptabase.appKey, forHTTPHeaderField: "App-Key")
        request.httpBody = data
        // Fire-and-forget; log failures so a bad key/host can't hide.
        session.dataTask(with: request) { _, response, error in
            if let error {
                print("AnalyticsClient: send failed — \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("AnalyticsClient: ingest rejected — HTTP \(http.statusCode)")
            }
        }.resume()
    }

    // MARK: - Helpers

    /// Event names: ≤40 chars, lowercase letters/digits/underscore. Our call
    /// sites already pass snake_case; this is a guard.
    private static func sanitizeName(_ name: String) -> String {
        let cleaned = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9_]", with: "_", options: .regularExpression)
        return String(cleaned.prefix(40))
    }

    private static var systemProps: [String: Any] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        return [
            "isDebug": isDebug,
            "osName": "macOS",
            "osVersion": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "locale": Locale.current.identifier,
            "appVersion": appVersion,
            "sdkVersion": "vordi-inhouse@1"
        ]
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
