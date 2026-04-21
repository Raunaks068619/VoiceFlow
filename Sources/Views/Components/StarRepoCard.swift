import SwiftUI
import AppKit

/// "Star the repo" card for the General tab.
///
/// Design borrowed from FreeFlow's settings pane: show the repo as a
/// clickable identity, surface live star count as a social-proof badge,
/// list recent stargazer avatars to reinforce that it's a real growing
/// project. The whole card is a soft ask — the Star button deep-links
/// to GitHub, we never prompt modally.
///
/// Why this works as content marketing: it turns every user who opens
/// the app into a potential drive-by star, and the "recently starred"
/// row creates a recurring reason to relaunch (watch the row update).
struct StarRepoCard: View {
    // Observe the shared cache instead of owning a new one — @StateObject
    // would try to re-init on every view create, breaking the singleton.
    @ObservedObject private var github = GitHubMetadataCache.shared

    private let openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    // Author avatar — shown as the card's identity anchor.
    // This is Raunak's GitHub; hardcoding avoids a second API round-trip
    // just for a profile picture that changes ~never.
    private let authorAvatar = URL(string: "https://avatars.githubusercontent.com/\(GitHubMetadataCache.repoOwner)")

    var body: some View {
        VStack(spacing: 10) {
            headerRow
            if !github.recentStargazers.isEmpty {
                Divider().opacity(0.5)
                stargazerRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.yellow.opacity(0.15), lineWidth: 0.5)
                )
        )
        .task {
            github.refreshIfStale()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            AsyncImage(url: authorAvatar) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())

            Button {
                openURL(GitHubMetadataCache.repoHTMLURL)
            } label: {
                Text("\(GitHubMetadataCache.repoOwner)/\(GitHubMetadataCache.repoName)")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            starCountBadge
            starButton
        }
    }

    private var starCountBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.caption2)
            if github.isLoading && github.starCount == nil {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
            } else if let count = github.starCount {
                Text("\(count.formatted()) \(count == 1 ? "star" : "stars")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("GitHub")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.yellow.opacity(0.14)))
    }

    private var starButton: some View {
        Button {
            openURL(GitHubMetadataCache.repoHTMLURL)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star")
                Text("Star")
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.yellow.opacity(0.18)))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help("Open the VoiceFlow repo on GitHub — a star helps this project grow.")
    }

    // MARK: - Recent stargazers

    private var stargazerRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: -6) {
                ForEach(github.recentStargazers) { star in
                    Button {
                        if let url = URL(string: star.user.htmlUrl) {
                            openURL(url)
                        }
                    } label: {
                        AsyncImage(url: star.user.avatarThumbnailUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                Color(nsColor: .windowBackgroundColor),
                                lineWidth: 1.5
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(star.user.login)
                }
            }
            .clipped()

            Text("recently starred")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()

            Spacer()
        }
        .clipped()
    }
}
