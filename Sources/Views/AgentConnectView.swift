import SwiftUI
import AppKit

/// Settings pane: one-click connect the bundled `vordi-mcp` helper to local AI
/// agents so they can read the user's dictation history. This is the moat made
/// tangible — "your agents can read what you said." Styled with the shared
/// VFFormSection design language so it matches the rest of Settings.
struct AgentConnectView: View {
    @StateObject private var manager = MCPConnectionManager.shared
    @State private var expanded: MCPConnectionManager.Client?
    @State private var copied: MCPConnectionManager.Client?
    @State private var note: String?

    private let clients = MCPConnectionManager.Client.allCases

    var body: some View {
        VStack(spacing: 0) {
            VFFormSection(header: "Agents") {
                ForEach(Array(clients.enumerated()), id: \.element) { index, client in
                    if index > 0 { VFDivider(inset: Theme.Space.xl) }
                    clientRow(client)
                    if expanded == client { snippetRow(client) }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                if let note {
                    Label(note, systemImage: "checkmark.circle.fill")
                        .font(.vfCalloutMedium)
                        .foregroundColor(Theme.success)
                }

                Label("Read-only. Agents can search and read your dictations — never write, delete, or access audio or screenshots.",
                      systemImage: "lock.shield")
                    .font(.vfDescription)
                    .foregroundColor(Theme.textSecondary)

                if !manager.isBundled {
                    Label("The helper isn't bundled in this build. Run scripts/build-and-install.sh, then reconnect.",
                          systemImage: "exclamationmark.triangle")
                        .font(.vfDescription)
                        .foregroundColor(.orange)
                }

                if let error = manager.lastError {
                    Text(error).font(.vfDescription).foregroundColor(Theme.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Layout.contentHPad)
            .padding(.top, Theme.Space.md)
        }
        .onAppear { manager.refresh() }
    }

    // MARK: - Row

    private func clientRow(_ client: MCPConnectionManager.Client) -> some View {
        let isInstalled = manager.installed[client] ?? false
        let isConnected = manager.connected[client] ?? false
        let status = isInstalled ? (isConnected ? "Connected" : "Not connected") : "Not detected"

        return VFFormRow(label: client.displayName, description: status) {
            HStack(spacing: Theme.Space.sm) {
                Button {
                    expanded = expanded == client ? nil : client
                } label: {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
                .help("Show manual config")

                if isConnected {
                    VFButton(title: "Disconnect", style: .secondary, isCompact: true) {
                        manager.disconnect(client)
                        note = "Disconnected from \(client.displayName)."
                    }
                } else {
                    VFButton(title: "Connect", icon: "link", style: .primary, isCompact: true,
                             isDisabled: !manager.isBundled) {
                        manager.connect(client)
                        if manager.lastError == nil {
                            note = "Connected. Restart \(client.displayName) to load Vordi, then ask it about your dictations."
                        }
                    }
                }
            }
        }
        .opacity(isInstalled ? 1 : 0.6)
    }

    // MARK: - Copy-paste fallback

    private func snippetRow(_ client: MCPConnectionManager.Client) -> some View {
        let snippet = manager.configSnippet(for: client)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Manual config")
                .font(.vfMicro)
                .foregroundColor(Theme.textTertiary)

            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Text(snippet)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    copied = client
                } label: {
                    Image(systemName: copied == client ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
                .help("Copy")
            }
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.mainContent))
        .padding(.horizontal, Theme.Space.xl)
        .padding(.bottom, Theme.Space.sm)
    }
}
