import SwiftUI
import AppKit

/// Guided fix flow for the cursed Input Monitoring permission.
///
/// Why this exists: macOS's `CGRequestListenEventAccess` silently fails on
/// ad-hoc-signed apps, and `IOHIDRequestAccess` is our best shot but can
/// still no-op if TCC has cached a denial. This view gives the user a
/// deterministic manual fallback: (1) open Settings, (2) reveal VoiceFlow
/// in Finder, (3) drag it in. We poll permission state every 750ms via
/// PermissionService and auto-dismiss the moment it flips to granted.
///
/// Design goal: make the manual-drag path feel like a guided flow, not
/// like the app is broken.
struct InputMonitoringGuideView: View {
    @ObservedObject var permissionService: PermissionService
    let onDismiss: () -> Void

    @State private var hasRequestedOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title3)
                Text("Input Monitoring")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            if !permissionService.inputMonitoringState.isGranted {
                Text("macOS requires Input Monitoring for VoiceFlow to detect the Fn hotkey. If the prompt didn't appear automatically, grant it manually in 3 steps:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    step(
                        number: 1,
                        title: "Open Input Monitoring in System Settings",
                        action: "Open Settings",
                        systemImage: "gear"
                    ) {
                        permissionService.openPrivacyPane(.inputMonitoring)
                    }

                    step(
                        number: 2,
                        title: "Click + and choose VoiceFlow from Applications",
                        action: "Reveal VoiceFlow in Finder",
                        systemImage: "magnifyingglass"
                    ) {
                        permissionService.revealAppInFinder()
                    }

                    step(
                        number: 3,
                        title: "Toggle it ON — VoiceFlow will detect it automatically, no restart needed.",
                        action: nil,
                        systemImage: "checkmark.circle"
                    ) { }
                }

                HStack(spacing: 10) {
                    Button {
                        hasRequestedOnce = true
                        permissionService.requestInputMonitoringAccess()
                    } label: {
                        Label(hasRequestedOnce ? "Retry Auto-Prompt" : "Try Auto-Prompt First", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                    Text("Checking permission…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Granted. You can close this panel.")
                    .font(.caption)
                    .foregroundColor(.green)
                HStack {
                    Spacer()
                    Button("Dismiss", action: onDismiss)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(statusColor.opacity(0.4), lineWidth: 1)
                )
        )
        .onAppear {
            permissionService.refreshStatus()
        }
    }

    @ViewBuilder
    private func step(number: Int, title: String, action: String?, systemImage: String, onTap: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline)
                if let action {
                    Button(action: onTap) {
                        Label(action, systemImage: systemImage)
                    }
                    .buttonStyle(.link)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(permissionService.inputMonitoringState.isGranted ? "Granted" : "Missing")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((permissionService.inputMonitoringState.isGranted ? Color.green : Color.orange).opacity(0.2))
            .foregroundColor(permissionService.inputMonitoringState.isGranted ? .green : .orange)
            .clipShape(Capsule())
    }

    private var statusIcon: String {
        permissionService.inputMonitoringState.isGranted
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        permissionService.inputMonitoringState.isGranted ? .green : .orange
    }
}
