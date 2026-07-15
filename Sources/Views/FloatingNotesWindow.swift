import AppKit
import SwiftUI

final class FloatingNotesWindow: NSPanel {
    private static let defaultSize = NSSize(width: 540, height: 420)
    private static let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

    init(store: VoiceNoteStore = .shared) {
        let rootView = FloatingNotesRootView(store: store)
        let hostingController = NSHostingController(rootView: rootView)

        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = "\(AppBrand.name) Notes"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        contentViewController = hostingController
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = Self.overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        minSize = NSSize(width: 460, height: 340)
        setContentSize(Self.defaultSize)
        center()
        setFrameAutosaveName("VordiNotesCompactWindow")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        alphaValue = 1
        level = Self.overlayLevel
        deminiaturize(nil)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
    }

}

private struct FloatingNotesRootView: View {
    @ObservedObject var store: VoiceNoteStore
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        NotesWorkspaceView(store: store, surface: .floating, capturesDictation: true)
            .preferredColorScheme(themeManager.colorScheme)
            .ignoresSafeArea(.container, edges: .top)
    }
}
