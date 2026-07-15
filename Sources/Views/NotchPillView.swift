import SwiftUI

struct NotchPillView: View {
    @ObservedObject var model: NotchPillModel
    @ObservedObject private var runStore = RunStore.shared
    @ObservedObject private var noteStore = VoiceNoteStore.shared
    @State private var modeSlideForward = true
    @State private var memoryCounts: (items: Int, entities: Int)?

    private let lanePadding: CGFloat = 10
    private let statusTrailingPadding: CGFloat = 18
    private let stateWidthBreathingRoom: CGFloat = 8
    private let notchMarkWidth: CGFloat = 18
    private let statusSpacing: CGFloat = 6
    private let statusFontSize: CGFloat = 10
    private let recordingMeterWidth: CGFloat = 38
    private let thinkingDotsWidth: CGFloat = 24
    private let doneTickWidth: CGFloat = 18
    private let pulseWidth: CGFloat = 24
    private let canvasWidth = NotchPillScreenGeometry.maxSurfaceWidth
    private let expandedPanelHeight = NotchPillScreenGeometry.expandedPanelHeight
    private let listeningPanelHeight = NotchPillScreenGeometry.listeningPanelHeight
    private let errorPanelHeight = NotchPillScreenGeometry.errorPanelHeight
    private let permissionsPanelHeight = NotchPillScreenGeometry.permissionsPanelHeight
    // Single interactive spring drives the whole morph — size, corner radii,
    // and content together — exactly like the comparison island. No separate
    // window-frame animation fights it, so corners stay rounded throughout.
    private var morphAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.50, dampingFraction: 0.82)
    }
    private var stateMorphAnimation: Animation {
        isEnteringListeningFeedback ? listeningFeedbackAnimation : morphAnimation
    }
    private var listeningFeedbackAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.10)
            : .spring(response: 0.22, dampingFraction: 0.86)
    }
    private let panelContentAnimation = Animation.easeOut(duration: 0.22).delay(0.06)

    private var backgroundSideExpansion: CGFloat {
        NotchPillScreenGeometry.backgroundSideExpansion(
            state: model.state,
            isExternalDock: model.isExternalDock
        )
    }

    private var centerGapWidth: CGFloat {
        NotchPillScreenGeometry.centerGapWidth(
            state: model.state,
            notchSize: model.hardwareNotchSize,
            isExternalDock: model.isExternalDock,
            defaultPillWidth: defaultPillWidth
        )
    }

    private var rowHeight: CGFloat {
        NotchPillScreenGeometry.rowHeight(
            state: model.state,
            notchSize: model.hardwareNotchSize,
            isExternalDock: model.isExternalDock
        )
    }

    private var defaultPillWidth: CGFloat {
        NotchPillScreenGeometry.defaultPillWidth(
            state: model.state,
            notchSize: model.hardwareNotchSize,
            isExternalDock: model.isExternalDock
        )
    }

    private var backgroundWidth: CGFloat {
        min(canvasWidth, pillWidth + backgroundSideExpansion * 2)
    }

    private var surfaceHeight: CGFloat {
        rowHeight + inlineTranscriptHeight + expandedPanelHeightValue
    }

    private var inlineTranscriptHeight: CGFloat {
        showsInlineTranscript ? 26 : 0
    }

    private var expandedPanelHeightValue: CGFloat {
        switch model.state {
        case .panelHover:
            return model.hasAllPermissions ? model.activePanelMode.panelHeight : permissionsPanelHeight
        case .panelTranscript:
            return listeningPanelHeight
        case .panelError:
            return errorPanelHeight
        default:
            return 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            notchSurface
                .help(helpText)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(stateMorphAnimation, value: model.state)
        .animation(morphAnimation, value: model.activePanelMode)
        .animation(morphAnimation, value: showsInlineTranscript)
    }

    private var notchSurface: some View {
        ZStack {
            notchShape
                .fill(NotchPillPalette.fill.opacity(isExternalCompactResting ? 0.42 : 1.0))
                .overlay {
                    if isExternalCompactResting {
                        notchShape
                            .stroke(NotchPillPalette.mark.opacity(0.50), lineWidth: 0.5)
                    } else {
                        notchShape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        NotchPillPalette.mark.opacity(0.07),
                                        stateGlowColor.opacity(glowOpacity * 0.32),
                                        NotchPillPalette.mark.opacity(0.025)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.7
                            )
                    }
                }

            NotchStateGlowView(
                color: stateGlowColor,
                secondaryColor: secondaryGlowColor,
                intensity: stateGlowIntensity
            )
            .frame(width: backgroundWidth, height: surfaceHeight, alignment: .trailing)
            .clipShape(notchShape)

            if let activeGlowMode {
                NotchActiveStateGlowView(
                    color: stateGlowColor,
                    secondaryColor: secondaryGlowColor,
                    mode: activeGlowMode
                )
                .frame(width: backgroundWidth, height: surfaceHeight, alignment: .trailing)
                .clipShape(notchShape)
                .transition(.opacity)
            }

            VStack(spacing: 0) {
                pillRow
                    .frame(width: pillWidth, height: rowHeight)

                inlineTranscriptStrip
                    .frame(width: pillWidth, height: inlineTranscriptHeight)
                    .opacity(showsInlineTranscript ? 1 : 0)
                    .clipped()

                expandedHoverPanel
                    .frame(width: pillWidth, height: expandedPanelHeightValue)
                    .opacity(showsExpandedPanel ? 1 : 0)
                    .clipped()
                    .animation(panelContentAnimation, value: showsExpandedPanel)
            }
            .frame(width: pillWidth, height: surfaceHeight, alignment: .top)
        }
        .frame(width: backgroundWidth, height: surfaceHeight)
        .overlay(alignment: .bottom) {
            glowStrip
        }
        // Clip the whole surface to the morphing shape so panel content is
        // revealed by the growing pill instead of floating outside it.
        .clipShape(notchShape)
        .contentShape(notchShape)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                model.onHoverChanged?(true)
            case .ended:
                model.onHoverChanged?(false)
            }
        }
    }

    @ViewBuilder
    private var pillRow: some View {
        if isExternalCompactResting {
            Color.clear
                .frame(width: pillWidth, height: rowHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)
                .vfClickableCursor()
        } else {
            HStack(spacing: 0) {
                leftVisibleLane
                    .frame(width: visibleLaneWidth, alignment: .leading)

                Color.clear
                    .frame(width: centerGapWidth, height: rowHeight)

                rightVisibleLane
                    .frame(width: visibleLaneWidth, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
            .vfClickableCursor()
        }
    }

    @ViewBuilder
    private var inlineTranscriptStrip: some View {
        if showsInlineTranscript {
            HStack(spacing: 3) {
                // Marquee-style: keep the *newest* words in view. As the live
                // transcript grows past the pill width, older words scroll off
                // the left so the trailing end (what's being said now) stays
                // visible next to the cursor — instead of freezing on the start.
                TrailingScrollText(
                    text: inlineTranscriptText,
                    font: .system(size: 11, weight: .regular),
                    color: NotchPillPalette.mark.opacity(0.48)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 15)

                NotchTranscriptCursorView(color: pulseColor)
                    .frame(width: 2, height: 13)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var expandedHoverPanel: some View {
        if showsExpandedPanel {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(NotchPillPalette.mark.opacity(0.07))
                    .frame(height: 1)

                switch model.state {
                case .panelTranscript:
                    listeningPanelContent
                case .panelError(let title, let desc, let tip):
                    errorPanelContent(title: title, desc: desc, tip: tip)
                default:
                    if model.hasAllPermissions {
                        hoverPanelContent
                    } else {
                        permissionsPanelContent
                    }
                }
            }
            .allowsHitTesting(true)
        } else {
            Color.clear
        }
    }

    private var hoverPanelContent: some View {
        VStack(spacing: 0) {
            panelHeader

            Group {
                switch model.activePanelMode {
                case .transcriptions:
                    VStack(spacing: 0) {
                        latestTranscriptionsList
                        panelFeatureRow
                    }
                case .notes:
                    notesModeContent
                case .memory:
                    memoryModeContent
                case .stats:
                    statsModeContent
                }
            }
            // Inset the sliding content so the mode chevrons live in their own
            // side gutters instead of overlapping the rows.
            .padding(.horizontal, chevronGutterWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(modeSlideTransition)

            panelFooterStepper
        }
        .clipped()
        .overlay(modeChevrons)
        .background(
            NotchTrackpadSwipeOverlay(enabled: isPanelHoverOpen) { direction in
                cyclePanelMode(forward: direction == .left)
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    cyclePanelMode(forward: value.translation.width < 0)
                }
        )
    }

    // Mirrors `errorPanelContent` exactly (paddings, spacings, text treatment)
    // so the permissions notice resolves to the same layout as every other
    // error state (e.g. "no transcription"). Only the content differs: the
    // Setup badge, Fix/close actions, and the Missing-permissions box.
    private var permissionsPanelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 9.5, weight: .semibold))

                    Text("Setup")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.2)
                }
                .foregroundColor(NotchPillPalette.warning.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(NotchPillPalette.warning.opacity(0.10))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(NotchPillPalette.warning.opacity(0.18), lineWidth: 1)
                }

                Spacer(minLength: 0)

                Button {
                    openPermissionsFlow()
                } label: {
                    Text("Fix")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 58, height: 22)
                }
                .buttonStyle(NotchErrorPrimaryButtonStyle(accent: NotchPillPalette.warning))
                .vfClickableCursor()

                Button {
                    closePanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(NotchErrorSecondaryButtonStyle())
                .vfClickableCursor()
                .help("Close")
            }
            .padding(.bottom, 7)

            Text("Permissions required")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(NotchPillPalette.mark.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, 4)

            Text("Complete permissions before using transcriptions.")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(NotchPillPalette.mark.opacity(0.48))
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(NotchPillPalette.warning.opacity(0.76))
                    .frame(width: 12, height: 14)

                Text("Missing: \(missingPermissionsText)")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(NotchPillPalette.mark.opacity(0.46))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(NotchPillPalette.mark.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(NotchPillPalette.mark.opacity(0.055), lineWidth: 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
    }

    private var isPanelHoverOpen: Bool {
        if case .panelHover = model.state { return true }
        return false
    }

    private var modeSlideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: modeSlideForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: modeSlideForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func cyclePanelMode(forward: Bool) {
        guard isPanelHoverOpen else { return }
        modeSlideForward = forward
        withAnimation(morphAnimation) {
            model.activePanelMode = forward ? model.activePanelMode.next : model.activePanelMode.previous
        }
    }

    private func selectPanelMode(_ mode: NotchPanelMode) {
        guard mode != model.activePanelMode else { return }
        let all = NotchPanelMode.allCases
        let from = all.firstIndex(of: model.activePanelMode) ?? 0
        let to = all.firstIndex(of: mode) ?? 0
        modeSlideForward = to > from
        withAnimation(morphAnimation) {
            model.activePanelMode = mode
        }
    }

    // Width reserved on each side of the panel for the mode chevrons:
    // 4pt margin + 18pt button + 4pt gap to the content.
    private var chevronGutterWidth: CGFloat { 26 }

    private var modeChevrons: some View {
        HStack {
            modeChevronButton(forward: false)
            Spacer(minLength: 0)
            modeChevronButton(forward: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 32)
    }

    private var panelFooterStepper: some View {
        HStack {
            Spacer(minLength: 0)
            modePageDots
            Spacer(minLength: 0)
        }
        .frame(height: 14)
        .padding(.bottom, 2)
        .allowsHitTesting(true)
    }

    private func modeChevronButton(forward: Bool) -> some View {
        Button {
            cyclePanelMode(forward: forward)
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(NotchPanelCircleButtonStyle())
        .vfClickableCursor()
        .help(forward ? "Next" : "Previous")
    }

    private var modePageDots: some View {
        HStack(spacing: 4) {
            ForEach(NotchPanelMode.allCases, id: \.self) { mode in
                Button {
                    selectPanelMode(mode)
                } label: {
                    Circle()
                        .fill(NotchPillPalette.mark.opacity(mode == model.activePanelMode ? 0.66 : 0.16))
                        .frame(width: 4, height: 4)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
                .help(mode.title)
            }
        }
    }

    private var listeningPanelContent: some View {
        VStack(spacing: 0) {
            listeningPanelHeader

            listeningPanelFooter
        }
    }

    private var listeningPanelHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(NotchPillPalette.blue)
                .frame(width: 6, height: 6)
                .opacity(0.85)

            Text("Listening")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NotchPillPalette.blue.opacity(0.86))

            Spacer(minLength: 0)

            WaveformBarsView(audioLevel: model.audioLevel, color: NotchPillPalette.blue)
                .frame(width: 34, height: 14)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotchPillPalette.mark.opacity(0.065))
                .frame(height: 1)
        }
    }

    private var listeningPanelFooter: some View {
        HStack(spacing: 6) {
            Text("Release")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundColor(NotchPillPalette.mark.opacity(0.26))

            Text("Fn")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(NotchPillPalette.mark.opacity(0.42))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(NotchPillPalette.mark.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(NotchPillPalette.mark.opacity(0.10), lineWidth: 1)
                )

            Text("to send")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundColor(NotchPillPalette.mark.opacity(0.26))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NotchPillPalette.mark.opacity(0.055))
                .frame(height: 1)
        }
    }

    private func errorPanelContent(title: String, desc: String, tip: String) -> some View {
        let presentation = panelNoticePresentation(title: title, desc: desc, tip: tip)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: presentation.icon)
                        .font(.system(size: 9.5, weight: .semibold))

                    Text(presentation.badge)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.2)
                }
                .foregroundColor(presentation.accent.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(presentation.accent.opacity(0.10))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(presentation.accent.opacity(0.18), lineWidth: 1)
                }

                Spacer(minLength: 0)

                if presentation.isClipboardFallback {
                    Button {
                        model.state = .idle
                    } label: {
                        Text("Done")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 58, height: 22)
                    }
                    .buttonStyle(NotchErrorPrimaryButtonStyle(accent: presentation.accent))
                    .vfClickableCursor()
                } else {
                    Button {
                        retryAfterError()
                    } label: {
                        Text("Try again")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 74, height: 22)
                    }
                    .buttonStyle(NotchErrorPrimaryButtonStyle(accent: presentation.accent))
                    .vfClickableCursor()

                    Button {
                        openRunLogFromError()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Logs")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .frame(width: 58, height: 22)
                    }
                    .buttonStyle(NotchErrorSecondaryButtonStyle())
                    .vfClickableCursor()
                }
            }
            .padding(.bottom, 7)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(NotchPillPalette.mark.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, 4)

            Text(desc)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(NotchPillPalette.mark.opacity(0.48))
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(presentation.accent.opacity(0.76))
                    .frame(width: 12, height: 14)

                Text(tip)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(NotchPillPalette.mark.opacity(0.46))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(NotchPillPalette.mark.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(NotchPillPalette.mark.opacity(0.055), lineWidth: 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
    }

    private struct PanelNoticePresentation {
        let badge: String
        let icon: String
        let accent: Color
        let isClipboardFallback: Bool
    }

    private func panelNoticePresentation(title: String, desc: String, tip: String) -> PanelNoticePresentation {
        let lower = "\(title) \(desc) \(tip)".lowercased()
        if lower.contains("clipboard") || lower.contains("copied") || lower.contains("input field") {
            return PanelNoticePresentation(
                badge: "Copied",
                icon: "doc.on.clipboard.fill",
                accent: NotchPillPalette.violet,
                isClipboardFallback: true
            )
        }
        return PanelNoticePresentation(
            badge: "Error",
            icon: "exclamationmark.triangle.fill",
            accent: compactErrorColor(for: title),
            isClipboardFallback: false
        )
    }

    private var panelHeader: some View {
        ZStack {
            Text(model.activePanelMode.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(NotchPillPalette.mark.opacity(0.34))
                .textCase(.uppercase)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .id("panelTitle-\(model.activePanelMode.rawValue)")
                .transition(.opacity)

            HStack(spacing: 8) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(NotchPanelIconButtonStyle())
                .vfClickableCursor()
                .help("Settings")

                Spacer(minLength: 0)

                Button {
                    closePanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(NotchPanelIconButtonStyle())
                .vfClickableCursor()
                .help("Close")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(height: 32)
    }

    private var latestTranscriptionsList: some View {
        VStack(spacing: 3) {
            let summaries = Array(runStore.summaries.prefix(3))
            if summaries.isEmpty {
                emptyTranscriptionRow
            } else {
                ForEach(summaries) { summary in
                    latestTranscriptionRow(summary)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var emptyTranscriptionRow: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                NotchPillPalette.blue.opacity(0.16),
                                NotchPillPalette.cyan.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                WaveformBarsView(audioLevel: 0.58, color: NotchPillPalette.cyan)
                    .frame(width: 24, height: 16)
                    .opacity(0.88)
            }
            .frame(width: 34, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(NotchPillPalette.cyan.opacity(0.12), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Start your first transcription")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(NotchPillPalette.mark.opacity(0.84))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("Hold")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(NotchPillPalette.mark.opacity(0.42))

                    Text("fn")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(NotchPillPalette.mark.opacity(0.60))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(NotchPillPalette.mark.opacity(0.075))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(NotchPillPalette.mark.opacity(0.12), lineWidth: 1)
                        }

                    Text("speak, then release")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(NotchPillPalette.mark.opacity(0.42))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(NotchPanelIconButtonStyle())
            .vfClickableCursor()
            .help("Check transcription settings")
        }
        .frame(height: 52)
        .padding(.horizontal, 9)
        .background(NotchPanelRowBackground())
    }

    private func latestTranscriptionRow(_ summary: RunSummary) -> some View {
        Button {
            openRunLog()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: summary.status))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color(for: summary.status))
                    .frame(width: 15)

                Text(transcriptionPreview(for: summary))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(NotchPillPalette.mark.opacity(0.66))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(relativeTime(for: summary.createdAt))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(NotchPillPalette.mark.opacity(0.28))
                    .lineLimit(1)
            }
            .frame(height: 25)
            .padding(.horizontal, 8)
            .background(NotchPanelRowBackground())
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
    }

    private var panelFeatureRow: some View {
        HStack(spacing: 6) {
            featureButton(title: "Memory", icon: "circle.grid.cross", tab: "memory")
            notesFeatureButton
            featureButton(title: "Magic Words", icon: "wand.and.stars", tab: "magicWords")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // MARK: - Panel modes

    private var notesModeContent: some View {
        VStack(spacing: 3) {
            let notes = Array(noteStore.notes.prefix(3))
            if notes.isEmpty {
                emptyModeRow(icon: "note.text", text: "No notes yet")
            } else {
                ForEach(notes) { note in
                    noteRow(note)
                }
            }

            Button {
                openNotes()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                    Text("New note")
                        .font(.system(size: 10.5, weight: .medium))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 25)
                .background(NotchPanelRowBackground())
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
        }
        .padding(.horizontal, 8)
    }

    private func noteRow(_ note: VoiceNote) -> some View {
        Button {
            openNotes()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(NotchPillPalette.mark.opacity(0.40))
                    .frame(width: 15)

                Text(notePreview(for: note))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(NotchPillPalette.mark.opacity(0.66))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(relativeTime(for: note.updatedAt))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(NotchPillPalette.mark.opacity(0.28))
                    .lineLimit(1)
            }
            .frame(height: 25)
            .padding(.horizontal, 8)
            .background(NotchPanelRowBackground())
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
    }

    private func notePreview(for note: VoiceNote) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let text = note.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(untitled)" : text
    }

    private var memoryModeContent: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                modeStatTile(
                    value: memoryCounts.map { "\($0.items)" } ?? "—",
                    label: "Memories"
                )
                modeStatTile(
                    value: memoryCounts.map { "\($0.entities)" } ?? "—",
                    label: "Entities"
                )
            }

            Button {
                openDashboardTab("memory")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "circle.grid.cross")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Open knowledge graph")
                        .font(.system(size: 10.5, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(NotchPillPalette.mark.opacity(0.30))
                }
                .padding(.horizontal, 8)
                .frame(height: 25)
                .background(NotchPanelRowBackground())
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .onAppear(perform: loadMemoryCounts)
    }

    private func loadMemoryCounts() {
        let items = MemoryStore.shared.itemCount(includeAgentContext: false)
        let entities = MemoryStore.shared.entityCount()
        memoryCounts = (items: items, entities: entities)
    }

    private var statsModeContent: some View {
        let stats = runStatsSummary

        return HStack(spacing: 6) {
            modeStatTile(value: "\(stats.today)", label: "Runs today")
            modeStatTile(value: "\(stats.total)", label: "Total runs")
            modeStatTile(value: stats.total == 0 ? "—" : "\(stats.successPct)%", label: "Success")
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var runStatsSummary: (today: Int, total: Int, successPct: Int) {
        let summaries = runStore.summaries
        let today = summaries.filter { Calendar.current.isDateInToday($0.createdAt) }.count
        let success = summaries.filter { $0.status == .success }.count
        let pct = summaries.isEmpty
            ? 0
            : Int((Double(success) / Double(summaries.count) * 100).rounded())
        return (today, summaries.count, pct)
    }

    private func modeStatTile(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(NotchPillPalette.mark.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(NotchPillPalette.mark.opacity(0.36))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(NotchPanelRowBackground())
    }

    private func emptyModeRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(NotchPillPalette.mark.opacity(0.36))
                .frame(width: 15)

            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(NotchPillPalette.mark.opacity(0.46))

            Spacer(minLength: 0)
        }
        .frame(height: 25)
        .padding(.horizontal, 8)
        .background(NotchPanelRowBackground())
    }

    private var notesFeatureButton: some View {
        Button {
            openNotes()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .semibold))
                Text("Notes")
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 37)
        }
        .buttonStyle(NotchPanelFeatureButtonStyle())
        .vfClickableCursor()
    }

    private func featureButton(title: String, icon: String, tab: String) -> some View {
        Button {
            openDashboardTab(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 37)
        }
        .buttonStyle(NotchPanelFeatureButtonStyle())
        .vfClickableCursor()
    }

    private var notchShape: NotchPillBaseShape {
        NotchPillBaseShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    private var leftVisibleLane: some View {
        HStack(spacing: statusSpacing) {
            VFLogoView()
                .frame(width: notchMarkWidth, height: 14)

            if showsStatusLabel {
                Text(statusLabel)
                    .font(.system(size: statusFontSize, weight: .regular))
                    .foregroundColor(Color(red: 0.88, green: 0.88, blue: 0.90))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.leading, visibleLaneWidth <= 34 ? 5 : 10)
        .clipped()
    }

    @ViewBuilder
    private var rightVisibleLane: some View {
        HStack(spacing: 8) {
            switch model.state {
            case .panelTranscript, .panelError:
                topRowCloseButton
                    .frame(width: recordingMeterWidth, height: 24, alignment: .trailing)
            case .listening, .handsFree:
                WaveformBarsView(audioLevel: model.audioLevel, color: pulseColor)
                    .frame(width: recordingMeterWidth, height: 14)
            case .thinking:
                ThinkingDotsView(color: stateGlowColor)
                    .frame(width: thinkingDotsWidth, height: 14)
            case .done:
                GreenTickView()
                    .frame(width: doneTickWidth, height: 14)
            default:
                NotchPulseView(color: pulseColor)
                    .frame(width: pulseWidth, height: 8)
            }
        }
        .padding(.trailing, visibleLaneWidth <= 34 ? 5 : 10)
        .clipped()
    }

    private var topRowCloseButton: some View {
        Button {
            closeTopRowPanel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(NotchPanelCircleButtonStyle())
        .vfClickableCursor()
        .help("Close panel")
    }

    @ViewBuilder
    private var glowStrip: some View {
        if model.state != .idle || !model.hasAllPermissions {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            stateGlowColor.opacity(glowOpacity * 0.50),
                            secondaryGlowColor.opacity(glowOpacity)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(28, pillWidth * 0.14), height: 2)
                .blur(radius: 0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
                .offset(y: 1)
                .allowsHitTesting(false)
        }
    }

    private var pillWidth: CGFloat {
        if model.hasAllPermissions {
            switch model.state {
            case .idle, .proximity:
                return defaultPillWidth
            default:
                break
            }
        }

        switch model.state {
        case .panelHover, .panelTranscript, .panelError:
            return min(
                canvasWidth,
                contentDerivedPillWidth(
                    label: statusLabel,
                    rightContentWidth: rightContentWidth
                ) + NotchPillScreenGeometry.openPanelWidthExpansion
            )
        default:
            return contentDerivedPillWidth(
                label: statusLabel,
                rightContentWidth: rightContentWidth
            )
        }
    }

    private var rightContentWidth: CGFloat {
        switch model.state {
        case .listening, .handsFree, .panelTranscript:
            return lanePadding + recordingMeterWidth
        case .thinking:
            return lanePadding + thinkingDotsWidth
        case .done:
            return lanePadding + doneTickWidth
        default:
            return lanePadding + pulseWidth
        }
    }

    private func contentDerivedPillWidth(
        label: String,
        rightContentWidth: CGFloat
    ) -> CGFloat {
        let leftContentWidth = lanePadding
            + notchMarkWidth
            + statusSpacing
            + measuredStatusTextWidth(label)
            + statusTrailingPadding
        let laneWidth = max(leftContentWidth, rightContentWidth) + stateWidthBreathingRoom
        return max(defaultPillWidth, ceil(centerGapWidth + laneWidth * 2))
    }

    private func measuredStatusTextWidth(_ label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: statusFontSize, weight: .regular)
        return ceil((label as NSString).size(withAttributes: [.font: font]).width)
    }

    private var visibleLaneWidth: CGFloat {
        max((pillWidth - centerGapWidth) / 2, 0)
    }

    private var showsInlineTranscript: Bool {
        // Show the live-transcript strip while actively dictating and we have
        // partial text to show. Driven by whatever feeds `liveTranscript` — the
        // on-device preview (any provider, incl. hands-free) or the OpenAI
        // realtime stream (push-to-talk). Was previously stubbed to `false`,
        // which silently dropped every live partial.
        guard !inlineTranscriptText.isEmpty else { return false }
        switch model.state {
        case .listening, .handsFree:
            return true
        default:
            return false
        }
    }

    private var showsExpandedPanel: Bool {
        if case .panelHover = model.state { return true }
        if case .panelTranscript = model.state { return true }
        if case .panelError = model.state { return true }
        return false
    }

    private var isEnteringListeningFeedback: Bool {
        switch model.state {
        case .listening, .panelTranscript:
            return true
        default:
            return false
        }
    }

    private var inlineTranscriptText: String {
        model.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var topCornerRadius: CGFloat {
        if isExternalCompactResting {
            return rowHeight / 2
        }
        return max((bottomCornerRadius - 4) * 1.2, 0)
    }

    private var bottomCornerRadius: CGFloat {
        if isExternalCompactResting {
            return rowHeight / 2
        }
        return showsExpandedPanel ? 18 : rowHeight / 3
    }

    private var isExternalCompactResting: Bool {
        NotchPillScreenGeometry.isExternalCompactResting(
            state: model.state,
            isExternalDock: model.isExternalDock
        )
    }

    private var showsStatusLabel: Bool {
        if case .panelTranscript = model.state { return false }
        if case .panelError = model.state { return false }
        return visibleLaneWidth > 70
    }

    private var statusLabel: String {
        switch model.state {
        case .listening:
            return "Listening"
        case .thinking:
            return "Thinking"
        case .done:
            return "Done"
        case .handsFree:
            return "Hands free"
        case .errorMini(let message):
            return compactErrorLabel(for: message)
        case .panelError(let title, _, _):
            return compactErrorLabel(for: title)
        case .panelTranscript:
            return "Listening"
        case .panelHover:
            return model.hasAllPermissions ? AppBrand.name : "Permissions required"
        case .idle, .proximity:
            return model.hasAllPermissions ? "Ready" : "Permissions required"
        }
    }

    private var glowOpacity: Double {
        switch model.state {
        case .listening, .handsFree, .panelTranscript:
            return 0.46
        case .thinking:
            return 0.44
        case .done:
            return 0.34
        case .errorMini, .panelError:
            return 0.42
        case .panelHover, .idle, .proximity:
            return model.hasAllPermissions ? 0.18 : 0.36
        }
    }

    private var stateGlowIntensity: Double {
        if isExternalCompactResting {
            return 0
        }

        switch model.state {
        case .listening, .handsFree, .panelTranscript:
            return 0.66
        case .thinking:
            return 0.62
        case .done:
            return 0.36
        case .errorMini, .panelError:
            return 0.46
        case .panelHover:
            return 0.28
        case .idle, .proximity:
            return model.hasAllPermissions ? 0.12 : 0.36
        }
    }

    private var activeGlowMode: NotchActiveGlowMode? {
        switch model.state {
        case .listening, .handsFree, .panelTranscript:
            return .listening
        case .thinking:
            return .thinking
        default:
            return nil
        }
    }

    private var stateGlowColor: Color {
        switch model.state {
        case .errorMini(let message):
            return compactErrorColor(for: message)
        case .panelError(let title, _, _):
            return compactErrorColor(for: title)
        case .thinking:
            return NotchPillPalette.violet
        case .done:
            return NotchPillPalette.success
        case .idle, .proximity, .panelHover:
            return model.hasAllPermissions ? NotchPillPalette.blue : NotchPillPalette.warning
        case .listening, .handsFree, .panelTranscript:
            return NotchPillPalette.blue
        }
    }

    private var secondaryGlowColor: Color {
        switch model.state {
        case .thinking:
            return NotchPillPalette.magenta
        case .errorMini(let message):
            return compactErrorColor(for: message)
        case .panelError(let title, _, _):
            return compactErrorColor(for: title)
        case .done:
            return NotchPillPalette.cyan
        default:
            return NotchPillPalette.cyan
        }
    }

    private var pulseColor: Color {
        switch model.state {
        case .errorMini(let message):
            return compactErrorColor(for: message)
        case .panelError(let title, _, _):
            return compactErrorColor(for: title)
        case .thinking:
            return NotchPillPalette.thinking
        case .done:
            return NotchPillPalette.success
        case .idle, .proximity, .panelHover:
            return model.hasAllPermissions ? NotchPillPalette.cyan : NotchPillPalette.warning
        case .listening, .handsFree, .panelTranscript:
            return NotchPillPalette.blue
        }
    }

    private var helpText: String {
        switch model.state {
        case .errorMini(let message):
            return helpText(forError: message)
        case .panelError(let title, _, _):
            return helpText(forError: title)
        case .thinking:
            return "\(AppBrand.name) is processing"
        case .listening:
            return "\(AppBrand.name) is listening"
        case .done:
            return "Done"
        case .handsFree:
            return "Hands-free mode is active"
        case .idle, .proximity, .panelHover:
            return model.hasAllPermissions ? "Open quick panel" : "Complete permissions to use transcriptions"
        case .panelTranscript:
            return "\(AppBrand.name) is listening"
        }
    }

    private func handleTap() {
        switch model.state {
        case .idle where !model.hasAllPermissions,
             .proximity where !model.hasAllPermissions,
             .panelHover where !model.hasAllPermissions:
            openPermissionsFlow()
        case .errorMini(let message):
            routeErrorTap(message)
        case .panelError(let title, _, _):
            routeErrorTap(title)
        case .idle, .proximity, .panelHover, .done:
            model.state = .panelHover
        default:
            break
        }
    }

    private func relativeTime(for date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }

    private func transcriptionPreview(for summary: RunSummary) -> String {
        let text = summary.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(no transcript)" : text
    }

    private func iconName(for status: RunStatus) -> String {
        switch status {
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .noSpeech:
            return "waveform.slash"
        }
    }

    private func color(for status: RunStatus) -> Color {
        switch status {
        case .success:
            return NotchPillPalette.success.opacity(0.86)
        case .failed:
            return NotchPillPalette.failure.opacity(0.86)
        case .noSpeech:
            return NotchPillPalette.warning.opacity(0.86)
        }
    }

    private func openSettings() {
        NotificationCenter.default.post(name: Notification.Name("Vordi.OpenSettings"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            model.state = .idle
        }
    }

    private func openNotes() {
        model.state = .idle
        NotificationCenter.default.post(name: Notification.Name("Vordi.OpenFloatingNotes"), object: nil)
    }

    private func openRunLog() {
        model.state = .idle
        NotificationCenter.default.post(name: Notification.Name("Vordi.OpenRunLog"), object: nil)
    }

    private func closePanel() {
        model.state = .idle
    }

    private func closeTopRowPanel() {
        switch model.state {
        case .panelTranscript:
            model.state = .listening
        default:
            model.state = .idle
        }
    }

    private func retryAfterError() {
        model.state = .idle
    }

    private func openRunLogFromError() {
        model.state = .idle
        NotificationCenter.default.post(name: Notification.Name("Vordi.OpenRunLog"), object: nil)
    }

    private func openPermissionsFlow() {
        model.state = .idle
        NotificationCenter.default.post(name: Notification.Name("Vordi.OpenOnboardingPermissions"), object: nil)
    }

    private func openDashboardTab(_ tab: String) {
        model.state = .idle
        NotificationCenter.default.post(name: Notification.Name("Vordi.OpenMainWindow"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: Notification.Name("Vordi.SelectTab"),
                object: nil,
                userInfo: ["tab": tab]
            )
        }
    }

    private func compactErrorLabel(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("microphone") || lower.contains("permission") {
            return "Permissions"
        }
        if lower.contains("input") {
            return "No input"
        }
        if lower.contains("clipboard") || lower.contains("copied") {
            return "Copied"
        }
        if lower.contains("audio") {
            return "No audio"
        }
        return "No output"
    }

    private func compactErrorColor(for text: String) -> Color {
        let lower = text.lowercased()
        if lower.contains("clipboard") || lower.contains("copied") {
            return NotchPillPalette.violet
        }
        return lower.contains("output") ? NotchPillPalette.failure : NotchPillPalette.warning
    }

    private func helpText(forError text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("permission") || lower.contains("microphone") {
            return "Grant permissions to dictate"
        }
        if lower.contains("clipboard") || lower.contains("copied") {
            return "Transcript copied. Use Cmd+V to paste it."
        }
        if lower.contains("audio") {
            return "No audio detected. Click to adjust microphone sensitivity."
        }
        if lower.contains("input") {
            return "No text field detected. Click to open Settings."
        }
        return "No output generated. Click to open Run Log."
    }

    private func routeErrorTap(_ text: String) {
        let lower = text.lowercased()
        if lower.contains("clipboard") || lower.contains("copied") {
            model.state = .idle
        } else if lower.contains("permission") || lower.contains("microphone") {
            openPermissionsFlow()
        } else if lower.contains("audio") || lower.contains("input") {
            NotificationCenter.default.post(name: Notification.Name("Vordi.OpenSettings"), object: nil)
        } else {
            NotificationCenter.default.post(name: Notification.Name("Vordi.OpenRunLog"), object: nil)
        }
    }

    private var missingPermissionsText: String {
        let names = model.missingPermissionNames
        if names.isEmpty {
            return "Microphone, Accessibility, and Input Monitoring"
        }
        return names.joined(separator: ", ")
    }
}

/// A single line of text pinned to its **trailing** (newest) end. When the text
/// is wider than the available width, older words scroll off the left so the
/// most-recent words stay in view — a live-caption marquee that follows the
/// speaker instead of freezing on the sentence's start.
///
/// How it works: the text is laid out at its natural width, shifted left by
/// exactly its overflow so the trailing edge lands at the container's right
/// edge, then clipped. The shift is animated, so growing text slides smoothly.
/// A short fade on the left edge signals there's more text scrolled off-screen.
private struct TrailingScrollText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflow = max(0, textWidth - geo.size.width)
            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TrailingTextWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                )
                .offset(x: -overflow)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: overflow > 0
                            ? [.init(color: .clear, location: 0),
                               .init(color: .black, location: 0.10),
                               .init(color: .black, location: 1)]
                            : [.init(color: .black, location: 0),
                               .init(color: .black, location: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .animation(.easeOut(duration: 0.18), value: overflow)
        }
        .onPreferenceChange(TrailingTextWidthKey.self) { textWidth = $0 }
    }
}

private struct TrailingTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
