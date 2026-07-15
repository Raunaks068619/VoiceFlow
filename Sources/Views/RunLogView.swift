import SwiftUI
import AppKit
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
    @State private var pendingDeleteRunID: UUID?

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header

                if runStore.summaries.isEmpty {
                    emptyState
                } else {
                    runList
                }
            }
            .frame(maxWidth: 960, alignment: .top)
            .padding(.horizontal, Theme.Layout.contentHPad)
            .padding(.top, 36)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.mainContent)

            if showClearConfirm {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { showClearConfirm = false }
                VFConfirmDialog(
                    title: "Clear all run history?",
                    message: "This will delete all saved audio and transcripts. This cannot be undone.",
                    confirmLabel: "Yes, clear it",
                    onCancel: { showClearConfirm = false },
                    onConfirm: {
                        runStore.clearAll()
                        selectedRunID = nil
                        showClearConfirm = false
                    }
                )
            }

            if let pendingDeleteRunID {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { self.pendingDeleteRunID = nil }
                VFConfirmDialog(
                    title: "Delete this run?",
                    message: "This removes the saved audio, transcript, and pipeline trace for this dictation.",
                    confirmLabel: "Yes, delete it",
                    onCancel: { self.pendingDeleteRunID = nil },
                    onConfirm: {
                        if selectedRunID == pendingDeleteRunID { selectedRunID = nil }
                        runStore.deleteRun(id: pendingDeleteRunID)
                        self.pendingDeleteRunID = nil
                    }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .center, spacing: Theme.Space.sm) {
                Text("Run Log")
                    .font(.vfPageTitle)
                    .foregroundColor(Theme.textPrimary)
                VFBadge(label: "Local", style: .plan)
                Spacer()
                VFButton(title: "Clear history", icon: "trash", style: .destructive, isCompact: true, isDisabled: runStore.summaries.isEmpty) {
                    showClearConfirm = true
                }
            }
            Text(retentionCaption)
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.bottom, Theme.Space.xl)
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
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)
            Text("Hold fn anywhere to start dictating. Each run will appear here with its full pipeline trace.")
                .font(.vfCallout)
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
                            pendingDeleteRunID = summary.id
                        }
                    )
                }
            }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate(summary.createdAt))
                        .font(.vfCaption)
                        .foregroundColor(Theme.textPrimary)
                    Text(summary.previewText.isEmpty ? "—" : summary.previewText)
                        .font(.vfCallout)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                statusBadge

                Text(formattedDuration(summary.durationSeconds))
                    .font(.vfKeyLabelSm)
                    .foregroundColor(Theme.textTertiary)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)

                VFActionMenu(
                    actions: transcriptActions,
                    iconColor: Theme.textTertiary,
                    buttonSize: 22
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }
            .vfClickableCursor()
            .padding(.horizontal, Theme.Space.xl)
            .frame(minHeight: Theme.Layout.listRowHeight)

            // Expanded detail
            if isExpanded {
                Divider().background(Theme.divider).padding(.horizontal, Theme.Space.xl)
                RunDetailView(runID: summary.id, runStore: runStore)
                    .padding(Theme.Space.xl)
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

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.vfBadge)
            .foregroundColor(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.xs, style: .continuous)
                    .fill(statusColor.opacity(0.12))
            )
    }

    private var transcriptActions: [VFActionMenuAction] {
        [
            VFActionMenuAction(
                icon: "arrow.clockwise",
                label: "Retry transcript",
                isDisabled: summary.status == .failed
            ) {
                retryTranscript()
            },
            VFActionMenuAction(
                icon: "arrow.down.circle",
                label: "Download audio"
            ) {
                downloadAudio()
            },
            .divider(),
            VFActionMenuAction(
                icon: "trash",
                label: "Delete transcript",
                isDestructive: true
            ) {
                onDelete()
            }
        ]
    }

    private var statusLabel: String {
        switch summary.status {
        case .success: return "Saved"
        case .failed: return "Failed"
        case .noSpeech: return "No speech"
        }
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

    // MARK: - Row actions (three-dot menu)

    /// Re-run polish on the existing audio. We re-use the stored audio file
    /// + current settings (provider, style, processing mode). Notification
    /// is broadcast so AppDelegate can pick it up — keeps the row view
    /// decoupled from the recording/transcription orchestration layer.
    private func retryTranscript() {
        NotificationCenter.default.post(
            name: Notification.Name("Vordi.RetryRun"),
            object: nil,
            userInfo: ["runID": summary.id]
        )
    }

    /// Copy the audio for this run to ~/Downloads with a human-readable
    /// filename. Uses the same FileManager copy path the rest of the app
    /// uses; no permission gates needed since it's the user's own
    /// Downloads folder.
    private func downloadAudio() {
        guard let run = runStore.loadRun(id: summary.id),
              let sourceURL = runStore.audioURL(for: run) else { return }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stem = "\(AppBrand.name)_\(formatter.string(from: summary.createdAt))"
        var dest = downloads.appendingPathComponent("\(stem).wav")

        // Avoid clobbering — append a counter if a same-named file exists.
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = downloads.appendingPathComponent("\(stem)_\(counter).wav")
            counter += 1
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            // Reveal the file in Finder so the user knows it landed.
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            print("RunRowView: download failed — \(error)")
        }
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
    @State private var showContextPrompt = false
    // Default expanded — the prompt is the highest-debug-value piece of
    // info on this card. Hiding it behind a click added one round trip of
    // friction every time someone opened a run to debug *why* the output
    // looked the way it did. With the fast-path skip marker now showing
    // in this same field, we ALWAYS want this content visible — it's the
    // single source of truth for "what (or nothing) was done to my text."
    @State private var showPostProcessPrompt = true
    @State private var contextImage: NSImage?

    var body: some View {
        Group {
            if let run = run {
                detailContent(run)
            } else {
                ProgressView("Loading…")
                    .controlSize(.small)
                    .tint(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            run = runStore.loadRun(id: runID)
            if let loadedRun = run,
               let url = runStore.screenshotURL(for: loadedRun) {
                contextImage = NSImage(contentsOf: url)
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Stage 1: Context + Audio Capture
            pipelineStage(number: 1, title: "Capture Context") {
                VStack(alignment: .leading, spacing: 10) {
                    contextCaptureBlock(run)
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
                            chip(post.mode, color: Theme.textPrimary)
                            chip(post.style, color: Theme.interactive)
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
                                        .foregroundColor(Theme.textPrimary)
                                }
                            )
                            .tint(Theme.textPrimary)
                        }

                        codeBlock(post.finalText.isEmpty ? "(empty — filtered)" : post.finalText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextCaptureBlock(_ run: Run) -> some View {
        if let context = run.context {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    metaLabel("App", value: context.frontmostAppName ?? "unknown")
                    if let title = context.windowTitle, !title.isEmpty {
                        metaLabel("Window", value: title)
                    }
                }

                if let screenshot = context.screenshot {
                    switch screenshot.status {
                    case .captured:
                        if let contextImage {
                            Image(nsImage: contextImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 170)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Theme.divider, lineWidth: 1)
                                )
                        }
                    case .denied:
                        metaLabel("Screenshot", value: "Screen Recording not granted")
                    case .disabled:
                        metaLabel("Screenshot", value: "disabled")
                    case .unavailable:
                        metaLabel("Screenshot", value: "no active window")
                    case .failed:
                        metaLabel("Screenshot", value: "capture failed")
                    case .skippedApp:
                        metaLabel("Screenshot", value: "skipped for this app")
                    }
                }

                if let summary = context.summary {
                    HStack {
                        metaLabel("Context model", value: summary.model)
                        Spacer()
                        metaLabel("Latency", value: "\(summary.latencyMs)ms")
                    }

                    DisclosureGroup(
                        isExpanded: $showContextPrompt,
                        content: {
                            codeBlock(summary.prompt)
                                .padding(.top, 6)
                        },
                        label: {
                            Text("Show prompt")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                        }
                    )
                    .tint(Theme.textPrimary)

                    Text(summary.text)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if context.hasUsefulContext {
                    Text("Captured app context; screenshot summary was not available for this run.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        } else {
            Text("No app context captured for this run.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - Audio player

    @ViewBuilder
    private func audioPlayerRow(_ run: Run) -> some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .vfClickableCursor()

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
            .vfClickableCursor()
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
                    .background(Circle().fill(Theme.textPrimary))
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
