import SwiftUI

/// Menu bar dropdown content, rendered inside SwiftUI's `MenuBarExtra`.
///
/// Observes `AppDelegate` via `@EnvironmentObject` — all state updates
/// (recording, permissions, hotkey status) are reflected automatically
/// through `@Published` properties. No manual refresh needed.
struct MenuBarView: View {
    @EnvironmentObject var appDelegate: AppDelegate

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // MenuBarExtra's material can be dark even while the app's
                // colorScheme reports light. Pin this surface to the white
                // transparent mark instead of guessing from colorScheme.
                VFBrandLogo(size: 26, variant: .dark, cornerRadius: 6)
                Text(AppBrand.name)
                    .font(.headline)
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Hold Fn to record", systemImage: "keyboard")
                    .font(.subheadline)
                Label("Release to transcribe", systemImage: "text.bubble")
                    .font(.subheadline)
            }

            if !appDelegate.permissionWarning.isEmpty {
                Text(appDelegate.permissionWarning)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Button(appDelegate.isRecording ? "Stop Recording" : "Test Record") {
                if appDelegate.isRecording {
                    appDelegate.isRecording = false
                    appDelegate.stopRecording()
                } else {
                    appDelegate.isRecording = true
                    appDelegate.startRecording()
                }
            }
            .keyboardShortcut("r")

            Divider()

            Button("Open Vordi") {
                appDelegate.openMainWindow()
            }
            .keyboardShortcut("o")

            Button("Settings...") {
                appDelegate.openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit Vordi") {
                appDelegate.allowTermination = true
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 250)
    }
}
