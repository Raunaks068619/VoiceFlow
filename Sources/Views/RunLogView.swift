import SwiftUI
import AVFoundation

/// Run Log tab — chronological history of dictation runs with full pipeline
/// transparency. Inspired by FreeFlow's Run Log.
struct RunLogView: View {
    @ObservedObject var runStore: RunStore
    @State private var selectedRunID: UUID?
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if runStore.summaries.isEmpty {
                emptyState
            } else {
                runList
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run Log")
                    .font(.title3.bold())
                Text("Stored locally. Only the \(runStore.maxRuns) most recent runs are kept.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Clear History") {
                showClearConfirm = true
            }
            .buttonStyle(.bordered)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.path")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No runs yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Hold Fn to start dictating. Each run will appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Run list

    private var runList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
        case .success: return .green
        case .failed: return .red
        case .noSpeech: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row header — always visible
            HStack(spacing: 10) {
                // Status indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor)
                    .frame(width: 4, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate(summary.createdAt))
                        .font(.subheadline.bold())
                    Text(summary.previewText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(formattedDuration(summary.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .alert("Delete this run?", isPresented: $showDeleteConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Expanded detail
            if isExpanded {
                Divider().padding(.horizontal, 12)
                RunDetailView(runID: summary.id, runStore: runStore)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(statusColor.opacity(summary.status == .failed ? 0.4 : 0.1), lineWidth: 1)
                )
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d/M/yyyy, h:mm:ss a"
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
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            run = runStore.loadRun(id: runID)
        }
    }

    @ViewBuilder
    private func detailContent(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Stage 1: Audio Capture
            pipelineStage(number: 1, title: "Audio Capture") {
                VStack(alignment: .leading, spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sent audio to")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(transcription.provider)
                                .font(.caption.bold())
                        }

                        metaLabel("Latency", value: "\(transcription.latencyMs)ms")

                        codeBlock(transcription.rawText)
                    }
                }
            }

            // Stage 3: Post-processing
            if let post = run.postProcessing {
                pipelineStage(number: 3, title: "Post-Process") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            capsule(post.mode, color: .blue)
                            capsule(post.style, color: .purple)
                            if post.droppedLanguageGuardTriggered {
                                capsule("guard triggered", color: .orange)
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
                                },
                                label: {
                                    Text("Show Prompt")
                                        .font(.caption.bold())
                                        .foregroundColor(.accentColor)
                                }
                            )
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
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                // Simple duration display (no scrubber in MVP)
                Text(formatDuration(audioPlayer?.duration ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { copyToClipboard(run) }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
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
            // Auto-reset when done
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.accentColor))
                Text(title)
                    .font(.subheadline.bold())
            }
            content()
                .padding(.leading, 28)
        }
    }

    @ViewBuilder
    private func metaLabel(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption2.bold())
        }
    }

    @ViewBuilder
    private func capsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor).opacity(0.5))
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
