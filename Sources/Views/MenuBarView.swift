import SwiftUI

struct MenuBarView: View {
    var isRecording: Bool
    var onStartRecording: () -> Void
    var onStopRecording: () -> Void
    var onSettings: () -> Void
    var onOnboarding: () -> Void
    var onQuit: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("VoiceFlow")
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Label("Hold Fn or Right Option to record", systemImage: "keyboard")
                    .font(.subheadline)
                Label("Or use test button below", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
            }
            
            Divider()
            
            // Press-and-hold test recording
            Button(action: {}) {
                Text(isRecording ? "Release to Stop" : "Hold to Test Record")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(isRecording ? .red : .accentColor)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                if pressing {
                    onStartRecording()
                } else {
                    onStopRecording()
                }
            }, perform: {})

            Divider()

            Button("Settings...") {
                onSettings()
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Button("Onboarding...") {
                onOnboarding()
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            
            Divider()
            
            Button("Quit VoiceFlow") {
                onQuit()
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding()
        .frame(width: 250)
    }
}
