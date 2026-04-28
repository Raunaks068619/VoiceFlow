import SwiftUI

/// Dashboard for usage stats. Pure view layer — every number is computed
/// from `RunStore.summaries` on the fly. No background jobs, no caching
/// layer of its own; the index file is the source of truth.
///
/// **Design language**: matches Settings exactly — ScrollView with
/// `padding(Theme.Space.xl)` (=24), VStack `spacing: 20`, every section
/// in a `themedCard()`. Header uses serif font + subtitle, consistent
/// with `settingsHeader`.
///
/// **Empty state**: shown when there are zero runs in the store. Avoids
/// the awful "0 runs · 0 words · NaN WPM" first-launch UI.
///
/// **Backwards-compat**: pre-existing runs in the store don't have
/// `wordCount` / `frontmostBundleID` / `profileUsed` populated. We compute
/// `wordCount` from `previewText` lazily so the totals don't read 0 on
/// upgrade. App / profile breakdowns gracefully degrade to "no data yet"
/// blocks until the next dictation populates them.
struct InsightsView: View {
    @ObservedObject var runStore: RunStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if runStore.summaries.isEmpty {
                    emptyStateCard
                } else {
                    heroStatsCard
                    todayCard
                    activityCard
                    appBreakdownCard
                    profileBreakdownCard
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Insights")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundColor(Theme.textPrimary)
            Text("How you dictate, where you dictate, and what you spend.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - Empty state

    private var emptyStateCard: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Theme.textSecondary)
            Text("No dictations yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text("Hold Fn anywhere to start. Stats appear here as soon as you do.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .themedCard()
    }

    // MARK: - Hero stats

    private var heroStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Lifetime")
            HStack(spacing: Theme.Space.md) {
                statTile(
                    icon: "text.bubble",
                    label: "Runs",
                    value: "\(stats.totalRuns)"
                )
                statTile(
                    icon: "abc",
                    label: "Words",
                    value: stats.totalWords.formatted()
                )
                statTile(
                    icon: "flame",
                    label: "Day streak",
                    value: stats.currentStreakDays > 0 ? "\(stats.currentStreakDays) 🔥" : "—"
                )
                statTile(
                    icon: "dollarsign.circle",
                    label: "LLM spend",
                    value: stats.totalSpendUSD > 0
                        ? String(format: "$%.3f", stats.totalSpendUSD)
                        : "—"
                )
            }
        }
        .themedCard()
    }

    // MARK: - Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Today")
            HStack(spacing: Theme.Space.md) {
                miniStat(label: "Dictations", value: "\(stats.todayRuns)")
                miniStat(label: "Words", value: stats.todayWords.formatted())
                miniStat(label: "Avg WPM", value: stats.todayAvgWPM > 0 ? "\(stats.todayAvgWPM)" : "—")
                miniStat(label: "Top app", value: stats.todayTopApp ?? "—")
            }
        }
        .themedCard()
    }

    // MARK: - Activity sparkline

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Last 14 days")
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(stats.activitySparkline, id: \.day) { entry in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.runs > 0 ? Theme.accent : Theme.textTertiary.opacity(0.2))
                            .frame(height: max(6, CGFloat(min(entry.runs, 12)) * 6))
                            .frame(maxHeight: 80)
                            .help("\(entry.runs) runs · \(entry.day)")
                        Text(entry.shortDay)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
        .themedCard()
    }

    // MARK: - App breakdown

    private var appBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Where you dictate")
            if stats.topApps.isEmpty {
                hintRow("No app data yet — dictate again with Context Capture on (Dev Mode → Context Capture).")
            } else {
                VStack(spacing: 10) {
                    ForEach(stats.topApps, id: \.bundleID) { entry in
                        breakdownRow(label: entry.name, count: entry.count, total: stats.totalRuns)
                    }
                }
            }
        }
        .themedCard()
    }

    // MARK: - Profile breakdown

    private var profileBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Which features you use")
            if stats.topProfiles.isEmpty {
                hintRow("Profile usage will appear after your first context-aware dictation.")
            } else {
                VStack(spacing: 10) {
                    ForEach(stats.topProfiles, id: \.profile) { entry in
                        breakdownRow(label: entry.label, count: entry.count, total: stats.totalRuns)
                    }
                }
            }
        }
        .themedCard()
    }

    // MARK: - Building blocks

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Theme.textPrimary)
    }

    private func statTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func breakdownRow(label: String, count: Int, total: Int) -> some View {
        let pct = total > 0 ? Double(count) / Double(total) : 0
        return HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 180, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.textTertiary.opacity(0.18))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accent)
                        .frame(width: max(2, geo.size.width * pct), height: 6)
                }
            }
            .frame(height: 6)
            Text("\(count)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(Theme.textSecondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func hintRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Stats

    private var stats: ComputedStats {
        ComputedStats.compute(from: runStore.summaries)
    }
}

// MARK: - Stats computation

/// Pure-function rollup of summaries → display numbers.
///
/// **Defensive computation**: pre-Phase1 summaries don't have `wordCount` /
/// `frontmostBundleID`. We fall back gracefully — wordCount derives from
/// `previewText` tokenization, which is the same source the encoder uses
/// for new entries. Bundle ID has no fallback so older runs simply don't
/// show up in the "where you dictate" card.
struct ComputedStats {
    let totalRuns: Int
    let totalWords: Int
    let totalSpendUSD: Double
    let currentStreakDays: Int

    let todayRuns: Int
    let todayWords: Int
    let todayAvgWPM: Int
    let todayTopApp: String?

    let activitySparkline: [DayEntry]
    let topApps: [AppEntry]
    let topProfiles: [ProfileEntry]

    struct DayEntry { let day: String; let shortDay: String; let runs: Int }
    struct AppEntry { let bundleID: String; let name: String; let count: Int }
    struct ProfileEntry { let profile: String; let label: String; let count: Int }

    /// Fallback word count for summaries persisted before `wordCount`
    /// was added. Tokenizes on whitespace — same approach as RunStore.save.
    static func wordCount(of summary: RunSummary) -> Int {
        if let cached = summary.wordCount { return cached }
        return summary.previewText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    static func compute(from summaries: [RunSummary]) -> ComputedStats {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let totalRuns = summaries.count
        let totalWords = summaries.reduce(0) { $0 + wordCount(of: $1) }
        let totalSpend = summaries.reduce(0.0) { $0 + ($1.llmCostUSD ?? 0) }

        // Streak: consecutive days going back from today with ≥1 run.
        let runDays: Set<Date> = Set(summaries.map { calendar.startOfDay(for: $0.createdAt) })
        var streak = 0
        var cursor = startOfToday
        while runDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }

        // Today's numbers — WPM is per-run mean (not global wallclock).
        let todayRuns = summaries.filter { calendar.isDateInToday($0.createdAt) }
        let todayWordsTotal = todayRuns.reduce(0) { $0 + wordCount(of: $1) }
        let todayAvgWPM: Int = {
            guard !todayRuns.isEmpty else { return 0 }
            // Mean of per-run WPM, NOT total words / total time. Per-run
            // is more representative of a user's actual speech rate; the
            // total form gets dragged down by short pauses between runs.
            let perRunWPMs = todayRuns.compactMap { run -> Double? in
                let wc = wordCount(of: run)
                guard run.durationSeconds > 0, wc > 0 else { return nil }
                return Double(wc) * 60.0 / run.durationSeconds
            }
            guard !perRunWPMs.isEmpty else { return 0 }
            let mean = perRunWPMs.reduce(0, +) / Double(perRunWPMs.count)
            return Int(mean.rounded())
        }()

        let todayTopApp: String? = {
            let appCounts = Dictionary(grouping: todayRuns) { $0.frontmostAppName ?? "" }
                .filter { !$0.key.isEmpty }
                .mapValues { $0.count }
            return appCounts.max { $0.value < $1.value }?.key
        }()

        // 14-day sparkline.
        var sparkline: [DayEntry] = []
        let dayFormatterFull = DateFormatter()
        dayFormatterFull.dateFormat = "yyyy-MM-dd"
        let dayFormatterShort = DateFormatter()
        dayFormatterShort.dateFormat = "EE"
        for offset in (0..<14).reversed() {
            let date = calendar.date(byAdding: .day, value: -offset, to: startOfToday)!
            let next = calendar.date(byAdding: .day, value: 1, to: date)!
            let count = summaries.filter { $0.createdAt >= date && $0.createdAt < next }.count
            sparkline.append(DayEntry(
                day: dayFormatterFull.string(from: date),
                shortDay: dayFormatterShort.string(from: date),
                runs: count
            ))
        }

        // Top apps — bundle ID grouping but we display the name.
        // Filter out runs with no captured app (pre-Phase1 history).
        let appBuckets = Dictionary(grouping: summaries.filter { $0.frontmostBundleID != nil }) {
            $0.frontmostBundleID!
        }
        let topApps = appBuckets.map { (bundleID, runs) in
            AppEntry(
                bundleID: bundleID,
                name: runs.first?.frontmostAppName ?? bundleID,
                count: runs.count
            )
        }
        .sorted { $0.count > $1.count }
        .prefix(5)

        // Top profiles.
        let profileBuckets = Dictionary(grouping: summaries.filter { $0.profileUsed != nil }) {
            $0.profileUsed!
        }
        let topProfiles = profileBuckets
            .map { (raw, runs) in
                let label = ProfileKind(rawValue: raw)?.displayLabel ?? raw
                return ProfileEntry(profile: raw, label: label, count: runs.count)
            }
            .sorted { $0.count > $1.count }
            .prefix(5)

        return ComputedStats(
            totalRuns: totalRuns,
            totalWords: totalWords,
            totalSpendUSD: totalSpend,
            currentStreakDays: streak,
            todayRuns: todayRuns.count,
            todayWords: todayWordsTotal,
            todayAvgWPM: todayAvgWPM,
            todayTopApp: todayTopApp,
            activitySparkline: sparkline,
            topApps: Array(topApps),
            topProfiles: Array(topProfiles)
        )
    }
}
