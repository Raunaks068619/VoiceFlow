import SwiftUI
import AppKit

/// Guided fix flow for the Accessibility permission.
///
/// Why this exists: Accessibility is required for VoiceFlow to inject the
/// transcribed text into the active app (via CGEvent / synthetic keystrokes).
/// Without it, the Fn hotkey will record audio but the transcribed text has
/// nowhere to go.
///
/// Unlike Input Monitoring, `AXIsProcessTrustedWithOptions(prompt: true)`
/// generally does fire the TCC prompt reliably — but users on ad-hoc-signed
/// builds can still hit edge cases where the prompt shows a stale bundle or
/// the user dismissed it earlier. We give the same 3-step guided fallback as
/// Input Monitoring and auto-dismiss the moment the 0.75s poll sees it flip.
struct AccessibilityGuideView: View {
    @ObservedObject var permissionService: PermissionService
    let onDismiss: () -> Void

    @State private var hasRequestedOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title3)
                Text("Accessibility")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            if !permissionService.accessibilityState.isGranted {
                Text("Accessibility lets VoiceFlow paste the transcribed text into the active app. If the prompt didn't appear, grant it in 3 steps:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    step(
                        number: 1,
                        title: "Open Accessibility in System Settings",
                        action: "Open Settings",
                        systemImage: "gear"
                    ) {
                        permissionService.openPrivacyPane(.accessibility)
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
                        permissionService.requestAccessibilityAccess()
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
        Text(permissionService.accessibilityState.isGranted ? "Granted" : "Missing")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((permissionService.accessibilityState.isGranted ? Color.green : Color.orange).opacity(0.2))
            .foregroundColor(permissionService.accessibilityState.isGranted ? .green : .orange)
            .clipShape(Capsule())
    }

    private var statusIcon: String {
        permissionService.accessibilityState.isGranted
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        permissionService.accessibilityState.isGranted ? .green : .orange
    }
}
