import SwiftUI
import AVFoundation

/// Run Log tab — chronological history of dictation runs with full pipeline
/// transparency. Each row collapses by default; expanding reveals the
/// audio + transcription + post-processing breakdown.
///
/// Visual treatment matches the Home dashboard: cream canvas, soft cards,
/// no stark black surfaces. Code blocks are tinted-cream (not dark
/// terminal-style) so they sit naturally inside the warm palette.
struct RunLogView: View {
    @ObservedObject var runStore: RunStore
    @State private var selectedRunID: UUID?
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if runStore.summaries.isEmpty {
                emptyState
            } else {
                runList
            }
        }
        .background(Theme.canvas)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Run Log")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.textPrimary)
                Text(retentionCaption)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                showClearConfirm = true
            } label: {
                Text("Clear history")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(runStore.summaries.isEmpty ? Theme.textTertiary : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .fill(runStore.summaries.isEmpty ? Theme.divider : Theme.danger)
                    )
            }
            .buttonStyle(.plain)
            .disabled(runStore.summaries.isEmpty)
            .alert("Clear all run history?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    runStore.clearAll()
                    selectedRunID = nil
                }
            } message: {
                Text("This will delete all saved audio and transcripts. This cannot be undone.")
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.lg)
    }

    /// Caption explaining current retention. `runStore.maxRuns` is `Int?`:
    /// nil → unlimited, otherwise → ring-buffer cap. We branch the copy
    /// instead of force-unwrapping because the unlimited case is real.
    private var retentionCaption: String {
        if let cap = runStore.maxRuns {
            return "Stored locally. Only the \(cap) most recent runs are kept."
        }
        return "Stored locally. No cap — history grows until you clear it."
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "waveform.path")
                .font(.system(size: 36))
                .foregroundColor(Theme.textTertiary)
            Text("No runs yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text("Hold fn anywhere to start dictating. Each run will appear here with its full pipeline trace.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Run list

    private var runList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Space.sm) {
                ForEach(runStore.summaries) { summary in
                    RunRowView(
                        summary: summary,
                        isExpanded: selectedRunID == summary.id,
                        runStore: runStore,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedRunID = selectedRunID == summary.id ? nil : summary.id
                            }
                        },
                        onDelete: {
                            if selectedRunID == summary.id { selectedRunID = nil }
                            runStore.deleteRun(id: summary.id)
                        }
                    )
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.bottom, Theme.Space.xl)
        }
    }
}

// MARK: - Row

struct RunRowView: View {
    let summary: RunSummary
    let isExpanded: Bool
    let runStore: RunStore
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    private var statusColor: Color {
        switch summary.status {
        case .success:  return Theme.success
        case .failed:   return Theme.danger
        case .noSpeech: return Theme.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            HStack(spacing: 12) {
                // Status pill — tiny vertical bar in the status color
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(statusColor)
                    .frame(width: 3, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate(summary.createdAt))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text(summary.previewText.isEmpty ? "—" : summary.previewText)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(formattedDuration(summary.durationSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .alert("Delete this run?", isPresented: $showDeleteConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Expanded detail
            if isExpanded {
                Divider().background(Theme.divider).padding(.horizontal, 16)
                RunDetailView(runID: summary.id, runStore: runStore)
                    .padding(16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, h:mm a"
        return f.string(from: date)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Detail

struct RunDetailView: View {
    let runID: UUID
    let runStore: RunStore
    @State private var run: Run?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var showTranscriptionPrompt = false
    @State private var showPostProcessPrompt = false

    var body: some View {
        Group {
            if let run = run {
                detailContent(run)
            } else {
                ProgressView("Loading…")
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            run = runStore.loadRun(id: runID)
        }
    }

    @ViewBuilder
    private func detailContent(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Stage 1: Audio Capture
            pipelineStage(number: 1, title: "Audio Capture") {
                VStack(alignment: .leading, spacing: 10) {
                    audioPlayerRow(run)

                    HStack(spacing: 16) {
                        metaLabel("Size", value: formatBytes(run.capture.audioSizeBytes))
                        if let range = run.capture.voicedBufferRange {
                            metaLabel("Voiced", value: range)
                        }
                    }
                }
            }

            // Stage 2: Transcription
            if let transcription = run.transcription {
                pipelineStage(number: 2, title: "Transcribe Audio") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Text("Sent audio to")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                            Text(transcription.provider)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                        }

                        metaLabel("Latency", value: "\(transcription.latencyMs)ms")

                        codeBlock(transcription.rawText)
                    }
                }
            }

            // Stage 3: Post-processing
            if let post = run.postProcessing {
                pipelineStage(number: 3, title: "Post-Process") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            chip(post.mode, color: Theme.accent)
                            chip(post.style, color: Color(red: 0.580, green: 0.345, blue: 0.722))
                            if post.droppedLanguageGuardTriggered {
                                chip("guard triggered", color: Theme.warning)
                            }
                        }

                        HStack {
                            metaLabel("Model", value: post.model)
                            Spacer()
                            metaLabel("Latency", value: "\(post.latencyMs)ms")
                        }

                        if !post.prompt.isEmpty {
                            DisclosureGroup(
                                isExpanded: $showPostProcessPrompt,
                                content: {
                                    codeBlock(post.prompt)
                                        .padding(.top, 6)
                                },
                                label: {
                                    Text("Show prompt")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.accent)
                                }
                            )
                            .tint(Theme.accent)
                        }

                        codeBlock(post.finalText.isEmpty ? "(empty — filtered)" : post.finalText)
                    }
                }
            }
        }
    }

    // MARK: - Audio player

    @ViewBuilder
    private func audioPlayerRow(_ run: Run) -> some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)

            Text(formatDuration(audioPlayer?.duration ?? 0))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textSecondary)

            Spacer()

            Button(action: { copyToClipboard(run) }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Copy final text to clipboard")
        }
        .onAppear { preparePlayer(for: run) }
        .onDisappear { stopPlayback() }
    }

    private func preparePlayer(for run: Run) {
        guard let url = runStore.audioURL(for: run) else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            print("RunDetailView: failed to create audio player — \(error)")
        }
    }

    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            // Auto-reset when done. Polling is crude but sufficient for the
            // <2min audio clips we deal with — no need for a delegate dance.
            DispatchQueue.global().async {
                while player.isPlaying { Thread.sleep(forTimeInterval: 0.1) }
                DispatchQueue.main.async { isPlaying = false }
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    private func copyToClipboard(_ run: Run) {
        let text = run.postProcessing?.finalText ?? run.transcription?.rawText ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func pipelineStage<Content: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.accent))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            content()
                .padding(.leading, 30)
        }
    }

    @ViewBuilder
    private func metaLabel(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    /// Inline code/transcript block. Uses `Theme.canvas` (slightly darker
    /// than `Theme.surface`) for subtle contrast inside the row card.
    /// Keeping this LIGHT — not a dark terminal — preserves the warm
    /// document aesthetic of the rest of the app.
    @ViewBuilder
    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(Theme.textPrimary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .textSelection(.enabled)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
