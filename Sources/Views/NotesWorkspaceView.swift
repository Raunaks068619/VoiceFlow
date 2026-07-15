import AppKit
import SwiftUI

struct NotesWorkspaceView: View {
    enum Surface {
        case dashboard
        case floating
    }

    private struct FloatingTab: Identifiable, Equatable {
        let id: UUID
        var noteID: UUID?

        init(id: UUID = UUID(), noteID: UUID?) {
            self.id = id
            self.noteID = noteID
        }
    }

    @ObservedObject var store: VoiceNoteStore
    let surface: Surface
    var onOpenFloatingNotes: (() -> Void)?
    var capturesDictation: Bool
    @AppStorage("floating_notes_capture_enabled") private var isFloatingCaptureEnabled = true

    @State private var search = ""
    @State private var hoveredNoteID: UUID?
    @State private var pendingDelete: VoiceNote?
    @State private var isDashboardSearchVisible = false
    @State private var isFloatingNotesListVisible = false
    @State private var isFloatingFormattingVisible = false
    @State private var floatingTabs: [FloatingTab] = []
    @State private var activeFloatingTabID: UUID?

    private let captureOwner = UUID().uuidString
    private let floatingRailWidth: CGFloat = 50

    init(
        store: VoiceNoteStore = .shared,
        surface: Surface = .dashboard,
        onOpenFloatingNotes: (() -> Void)? = nil,
        capturesDictation: Bool = true
    ) {
        self.store = store
        self.surface = surface
        self.onOpenFloatingNotes = onOpenFloatingNotes
        self.capturesDictation = capturesDictation
    }

    var body: some View {
        ZStack {
            Group {
                if surface == .dashboard {
                    dashboardBody
                } else {
                    floatingEditorBody
                }
            }

            if let pendingDelete {
                deleteOverlay(note: pendingDelete)
            }
        }
        .background(Theme.mainContent)
        .onAppear {
            if shouldCaptureDictation {
                store.beginDictationCapture(owner: captureOwner)
            }
            if surface == .floating && store.notes.isEmpty && !store.hasActiveDraftOrNote {
                store.startDraft()
            }
            if surface == .floating {
                bootstrapFloatingTabs()
            }
        }
        .onDisappear {
            if store.isCapturingDictation(owner: captureOwner) {
                store.endDictationCapture(owner: captureOwner)
            }
        }
        .onChange(of: store.activeNoteID) { _ in
            syncActiveFloatingTabWithStore()
        }
        .onChange(of: isFloatingCaptureEnabled) { _ in
            syncDictationCaptureState()
        }
    }

    private var shouldCaptureDictation: Bool {
        guard capturesDictation else { return false }
        return surface == .floating ? isFloatingCaptureEnabled : true
    }

    private func syncDictationCaptureState() {
        let isCapturing = store.isCapturingDictation(owner: captureOwner)
        if shouldCaptureDictation {
            if !isCapturing {
                store.beginDictationCapture(owner: captureOwner)
            }
        } else if isCapturing {
            store.endDictationCapture(owner: captureOwner)
        }
    }

    private var dashboardBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                dashboardPageHeader
                dashboardHero
                dashboardToolbar
                dashboardNotesList
            }
            .frame(maxWidth: Theme.Layout.centralContentWidth, alignment: .leading)
            .padding(.horizontal, Theme.Layout.contentHPad)
            .padding(.top, Theme.Layout.contentVPad)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var floatingEditorBody: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                floatingSidebar

                VStack(spacing: 0) {
                    floatingTitleBar
                    floatingEditorCard
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if isFloatingNotesListVisible {
                floatingNotesListPanel
                    .padding(.leading, floatingRailWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .background(Theme.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var floatingSidebar: some View {
        VStack(spacing: 0) {
            VFBrandLogo(size: 30, variant: .light, cornerRadius: 7)
                .padding(.top, 4)
                .padding(.bottom, 16)

            VStack(spacing: 18) {
                floatingSidebarButton(
                    systemName: "sidebar.left",
                    help: "Show notes",
                    isActive: isFloatingNotesListVisible
                ) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isFloatingNotesListVisible.toggle()
                    }
                }

                floatingSidebarButton(systemName: "square.and.pencil", help: "New note") {
                    openNewFloatingTab()
                }

                floatingSidebarButton(
                    systemName: "magnifyingglass",
                    help: "Search notes",
                    isActive: isFloatingNotesListVisible && !search.isEmpty
                ) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isFloatingNotesListVisible = true
                    }
                }
            }

            Spacer()

            VStack(spacing: 18) {
                floatingSidebarButton(systemName: "sparkles", help: "Transforms") {}
                floatingSidebarButton(
                    systemName: "textformat",
                    help: "Formatting",
                    isActive: isFloatingFormattingVisible
                ) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isFloatingFormattingVisible.toggle()
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .frame(width: floatingRailWidth)
        .frame(maxHeight: .infinity)
    }

    private func floatingSidebarButton(
        systemName: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                        .fill(isActive ? Theme.surfaceElevated : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous))
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help(help)
    }

    private var floatingTitleBar: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            floatingTabsBar

            Spacer(minLength: Theme.Space.sm)

            if surface == .floating {
                floatingCaptureToggle
            }

            floatingTitleIcon("arrow.up.left.and.arrow.down.right", help: "Zoom window") {
                NSApp.keyWindow?.zoom(nil)
            }

            floatingTitleIcon("xmark", help: "Close window") {
                NSApp.keyWindow?.performClose(nil)
            }
        }
        .frame(height: 32)
        .padding(.trailing, 8)
    }

    private var floatingCaptureToggle: some View {
        Button {
            isFloatingCaptureEnabled.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isFloatingCaptureEnabled ? "mic.fill" : "mic.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text(isFloatingCaptureEnabled ? "Capture" : "Off")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isFloatingCaptureEnabled ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(isFloatingCaptureEnabled ? Theme.surfaceElevated : Theme.surface.opacity(0.58))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isFloatingCaptureEnabled ? Theme.dividerStrong : Theme.divider, lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help(isFloatingCaptureEnabled ? "Dictations append to this note" : "Dictations will not append to this note")
    }

    private var floatingTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(floatingTabs) { tab in
                    floatingTabView(tab)
                }

                floatingTitleIcon("plus", help: "New tab") {
                    openNewFloatingTab()
                }
            }
        }
        .frame(maxWidth: 340, alignment: .leading)
    }

    private func floatingTabView(_ tab: FloatingTab) -> some View {
        let isActive = tab.id == activeFloatingTabID

        return HStack(spacing: 6) {
            if isActive {
                TextField("Untitled", text: activeTitleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 92)
            } else {
                Text(floatingTabTitle(tab))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 92, alignment: .leading)
            }

            Button {
                closeFloatingTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isActive ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
            .help("Close tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                .fill(isActive ? Theme.surfaceElevated : Theme.surface.opacity(0.44))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                .strokeBorder(isActive ? Theme.dividerStrong : Color.clear, lineWidth: 1)
        )
        .shadow(color: isActive ? Theme.Shadow.card.color : Color.clear,
                radius: Theme.Shadow.card.radius,
                x: 0,
                y: Theme.Shadow.card.y)
        .contentShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous))
        .onTapGesture {
            activateFloatingTab(tab)
        }
        .vfClickableCursor()
    }

    private func floatingTitleIcon(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help(help)
    }

    private var floatingEditorCard: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    NotesRichTextEditor(store: store)

                    if store.activeContent.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Write your note here.")
                            .font(.vfCallout)
                            .foregroundColor(Theme.textTertiary)
                            .padding(.leading, NotesRichTextEditor.textInset.width)
                            .padding(.top, NotesRichTextEditor.textInset.height)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isFloatingFormattingVisible {
                    HStack {
                        NotesFormatToolbar()
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)
                    .background(Theme.surface)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            floatingCopyButton
                .padding(.trailing, 16)
                .padding(.bottom, isFloatingFormattingVisible ? 62 : 16)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous))
    }

    private var floatingCopyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.activeContent.string, forType: .string)
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                Text("Copy")
                    .font(.vfCalloutMedium)
            }
            .foregroundColor(Theme.floatingActionForeground)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Capsule(style: .continuous).fill(Theme.floatingActionFill))
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help("Copy note text")
    }

    private var floatingNotesListPanel: some View {
        notesRail
            .frame(width: 198)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .shadow(color: Theme.Shadow.elevated.color,
                    radius: Theme.Shadow.elevated.radius,
                    x: 0,
                    y: Theme.Shadow.elevated.y)
            .padding(.top, 32)
            .padding(.bottom, 10)
    }

    private var dashboardPageHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: Theme.Space.sm) {
                Text("Notes")
                    .font(.vfPageTitle)
                    .foregroundColor(Theme.textPrimary)
                VFBadge(label: "Beta", style: .feature)
                notesCommandHint
            }

            Spacer()

            VFButton(title: "Add new", icon: "plus", style: .primary) {
                startDraftAndOpenFloatingNotes()
            }
        }
    }

    private var notesCommandHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Say \"open Vordi Notes\"")
                .font(.vfCaption)
                .lineLimit(1)
        }
        .foregroundColor(Theme.textSecondary)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule(style: .continuous).fill(Theme.surfaceElevated))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        }
        .help("Say \"open Vordi Notes and type ...\" to create a note with dictated text.")
    }

    private var dashboardHero: some View {
        VFHeroBanner(
            segments: [
                .plain("Turn rough "),
                .italic("thoughts"),
                .plain(" into saved notes")
            ],
            bodyText: "Dictate or type into a floating note, keep it saved locally, and reopen it from Recents whenever you need it.",
            cta: ("New note", {
                startDraftAndOpenFloatingNotes()
            })
        )
        .frame(minHeight: 176)
    }

    private var dashboardToolbar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("RECENTS")
                    .font(.vfCategoryLabel)
                    .foregroundColor(Theme.textSecondary)
                    .tracking(0.5)

                Spacer(minLength: Theme.Space.lg)

                HStack(spacing: Theme.Space.sm) {
                    if isDashboardSearchVisible {
                        VFSearchBar(text: $search, placeholder: "Search")
                            .frame(width: 240)
                    }

                    notesToolbarIcon("magnifyingglass", help: "Search") {
                        withAnimation(.easeOut(duration: 0.16)) {
                            isDashboardSearchVisible.toggle()
                        }
                        if !isDashboardSearchVisible {
                            search = ""
                        }
                    }

                    notesToolbarIcon("arrow.clockwise", help: "Refresh") {
                        store.reload()
                    }
                }
            }
            .padding(.bottom, Theme.Space.sm)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
        }
    }

    private var dashboardNotesList: some View {
        VStack(spacing: 0) {
            if filteredNotes.isEmpty {
                dashboardEmptyState
            } else {
                ForEach(Array(filteredNotes.enumerated()), id: \.element.id) { index, note in
                    dashboardNoteRow(note)
                    if index < filteredNotes.count - 1 {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                    }
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    private var dashboardEmptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "note.text")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            Text(search.isEmpty ? "No notes yet" : "No matches")
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)
            Text(search.isEmpty ? "Fresh notes will appear here." : "Try a different search.")
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func dashboardNoteRow(_ note: VoiceNote) -> some View {
        let isHovered = hoveredNoteID == note.id

        return HStack(alignment: .center, spacing: Theme.Space.md) {
            Image(systemName: "note.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                        .fill(Theme.surfaceElevated)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.vfBodyMedium)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(note.preview)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(shortDate(note.updatedAt))
                    .font(.vfCaption)
                    .foregroundColor(Theme.textSecondary)
                Text(timeString(note.updatedAt))
                    .font(.vfCaption)
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(width: 74, alignment: .trailing)

            HStack(spacing: Theme.Space.xs) {
                notesRowIcon("pencil", help: "Edit") {
                    store.select(note)
                    openFloatingNotesFromDashboard()
                }
                notesRowIcon("trash", help: "Delete", color: Theme.danger) {
                    pendingDelete = note
                }
            }
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 72)
        .background(isHovered ? Theme.surfaceElevated.opacity(0.38) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.select(note)
            openFloatingNotesFromDashboard()
        }
        .vfClickableCursor()
        .onHover { isHovering in
            hoveredNoteID = isHovering ? note.id : nil
        }
    }

    private func notesToolbarIcon(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help(help)
    }

    private func notesRowIcon(
        _ systemName: String,
        help: String,
        color: Color = Theme.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help(help)
    }

    private func startDraftAndOpenFloatingNotes() {
        store.startDraft()
        openFloatingNotesFromDashboard()
    }

    private func bootstrapFloatingTabs() {
        guard surface == .floating else { return }
        if floatingTabs.isEmpty {
            let tab = FloatingTab(noteID: store.activeNoteID)
            floatingTabs = [tab]
            activeFloatingTabID = tab.id
            return
        }
        syncActiveFloatingTabWithStore()
    }

    private func syncActiveFloatingTabWithStore() {
        guard surface == .floating else { return }
        guard let activeFloatingTabID else {
            bootstrapFloatingTabs()
            return
        }

        if floatingTabs.isEmpty {
            bootstrapFloatingTabs()
            return
        }

        guard let noteID = store.activeNoteID else { return }

        if let existingIndex = floatingTabs.firstIndex(where: { $0.noteID == noteID }) {
            self.activeFloatingTabID = floatingTabs[existingIndex].id
            return
        }

        if let activeIndex = floatingTabs.firstIndex(where: { $0.id == activeFloatingTabID }) {
            floatingTabs[activeIndex].noteID = noteID
        } else {
            let tab = FloatingTab(noteID: noteID)
            floatingTabs.append(tab)
            self.activeFloatingTabID = tab.id
        }
    }

    private func openNewFloatingTab() {
        guard surface == .floating else {
            store.startDraft()
            return
        }

        let tab = FloatingTab(noteID: nil)
        floatingTabs.append(tab)
        activeFloatingTabID = tab.id
        store.startDraft()
        withAnimation(.easeOut(duration: 0.18)) {
            isFloatingNotesListVisible = false
        }
    }

    private func openFloatingTab(for note: VoiceNote) {
        guard surface == .floating else {
            store.select(note)
            openFloatingNotesFromDashboard()
            return
        }

        if let existing = floatingTabs.first(where: { $0.noteID == note.id }) {
            activeFloatingTabID = existing.id
        } else {
            let tab = FloatingTab(noteID: note.id)
            floatingTabs.append(tab)
            activeFloatingTabID = tab.id
        }

        store.select(note)
        withAnimation(.easeOut(duration: 0.18)) {
            isFloatingNotesListVisible = false
        }
    }

    private func activateFloatingTab(_ tab: FloatingTab) {
        activeFloatingTabID = tab.id
        if let noteID = tab.noteID, let note = store.notes.first(where: { $0.id == noteID }) {
            store.select(note)
        } else {
            store.startDraft()
        }
    }

    private func closeFloatingTab(_ tab: FloatingTab) {
        guard let index = floatingTabs.firstIndex(of: tab) else { return }
        let wasActive = activeFloatingTabID == tab.id
        floatingTabs.remove(at: index)

        if floatingTabs.isEmpty {
            openNewFloatingTab()
            return
        }

        guard wasActive else { return }
        let nextIndex = min(index, floatingTabs.count - 1)
        activateFloatingTab(floatingTabs[nextIndex])
    }

    private func floatingTabTitle(_ tab: FloatingTab) -> String {
        if let noteID = tab.noteID, let note = store.notes.first(where: { $0.id == noteID }) {
            return note.displayTitle
        }

        if tab.id == activeFloatingTabID {
            let explicitTitle = store.activeTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !explicitTitle.isEmpty {
                return explicitTitle
            }
            let inferred = VoiceNote.inferredTitle(from: store.activeContent.string)
            if inferred != "Untitled note" {
                return inferred
            }
        }

        return "Untitled"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                Text("Notes")
                    .font(.vfPageTitle)
                    .foregroundColor(Theme.textPrimary)
                VFBadge(label: "Rich text", style: .feature)
            }

            Spacer()

            HStack(spacing: Theme.Space.sm) {
                if surface == .dashboard, let onOpenFloatingNotes {
                    VFButton(
                        title: "Floating",
                        icon: "macwindow",
                        style: .secondary,
                        isCompact: true,
                        action: onOpenFloatingNotes
                    )
                }
                VFButton(
                    title: "Add new",
                    icon: "plus",
                    style: .primary,
                    isCompact: true
                ) {
                    store.startDraft()
                    openFloatingNotesFromDashboard()
                }
            }
        }
        .frame(minHeight: 32)
    }

    private var workspaceShell: some View {
        HStack(spacing: 0) {
            notesRail
                .frame(width: surface == .dashboard ? 248 : 220)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: surface == .dashboard ? 560 : 420)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var notesRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VFSearchBar(text: $search, placeholder: "Search notes")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.sm)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            if filteredNotes.isEmpty {
                railEmptyState
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(filteredNotes) { note in
                            noteRow(note)
                        }
                    }
                    .padding(Theme.Space.sm)
                }
            }
        }
        .background(Theme.canvas.opacity(0.58))
    }

    private var railEmptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "note.text")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            Text(search.isEmpty ? "No notes yet" : "No matches")
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)
            Text(search.isEmpty ? "Fresh notes will appear here." : "Try a different search.")
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.lg)
    }

    private func noteRow(_ note: VoiceNote) -> some View {
        let isSelected = store.activeNoteID == note.id
        let isHovered = hoveredNoteID == note.id

        return HStack(alignment: .top, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.vfBodyMedium)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(note.preview)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(relativeDate(note.updatedAt))
                    .font(.vfCaption)
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                pendingDelete = note
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.danger)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
            .opacity(isHovered ? 1 : 0)
            .help("Delete note")
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                .fill(isSelected ? Theme.interactiveSoft : (isHovered ? Theme.surfaceElevated.opacity(0.52) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                .strokeBorder(isSelected ? Theme.interactive.opacity(0.36) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous))
        .onTapGesture {
            if surface == .floating {
                openFloatingTab(for: note)
            } else {
                store.select(note)
                openFloatingNotesFromDashboard()
            }
        }
        .vfClickableCursor()
        .onHover { hovering in
            hoveredNoteID = hovering ? note.id : nil
        }
    }

    private func openFloatingNotesFromDashboard() {
        guard surface == .dashboard else { return }
        onOpenFloatingNotes?()
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            editorHeader

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            ZStack(alignment: .topLeading) {
                NotesRichTextEditor(store: store)

                if store.activeContent.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write your note here.")
                        .font(.vfCallout)
                        .foregroundColor(Theme.textTertiary)
                        .padding(.leading, NotesRichTextEditor.textInset.width)
                        .padding(.top, NotesRichTextEditor.textInset.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surfaceElevated.opacity(0.34))

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            editorFooter
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Name this note", text: activeTitleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: surface == .dashboard ? 20 : 18, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(activeSubtitle)
                    .font(.vfCaption)
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let note = store.activeNote {
                Button {
                    pendingDelete = note
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.danger)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Theme.surfaceElevated)
                        )
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
                .help("Delete note")
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
    }

    private var editorFooter: some View {
        HStack(spacing: Theme.Space.md) {
            NotesFormatToolbar()
            Spacer()
            Text(store.activeNote == nil ? "Draft" : "Autosaved")
                .font(.vfCaption)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .background(Theme.surface)
    }

    private var activeTitleBinding: Binding<String> {
        Binding(
            get: { store.activeTitleText },
            set: { store.updateActiveTitle($0) }
        )
    }

    private var activeSubtitle: String {
        if let note = store.activeNote {
            return "Edited \(relativeDate(note.updatedAt))"
        }
        return "Unsaved draft"
    }

    private var filteredNotes: [VoiceNote] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.notes }
        let query = trimmed.lowercased()
        return store.notes.filter {
            $0.title.lowercased().contains(query)
                || $0.plainText.lowercased().contains(query)
        }
    }

    private func deleteOverlay(note: VoiceNote) -> some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VFConfirmDialog(
                title: "Are you sure you want to delete this note?",
                message: "Once deleted it cannot be recovered",
                confirmLabel: "Yes, delete it",
                onCancel: { pendingDelete = nil },
                onConfirm: {
                    store.delete(id: note.id)
                    pendingDelete = nil
                }
            )
        }
    }

    private func relativeDate(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func shortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
