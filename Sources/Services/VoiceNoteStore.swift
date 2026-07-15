import AppKit
import Combine
import Foundation

final class VoiceNoteStore: ObservableObject {
    static let shared = VoiceNoteStore()

    @Published private(set) var notes: [VoiceNote] = []
    @Published private(set) var activeNoteID: UUID?
    @Published private(set) var activeContent: NSAttributedString = NSAttributedString(string: "")
    @Published private(set) var draftTitle: String = ""

    private let queue = DispatchQueue(label: "com.vordi.notes", qos: .utility)
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var runCancellable: AnyCancellable?
    private weak var observedRunStore: RunStore?
    private var lastSeenRunID: UUID?
    private var dictationCaptureOwners = Set<String>()

    private var notesDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Vordi", isDirectory: true)
            .appendingPathComponent("notes", isDirectory: true)
    }

    private var contentDirectory: URL {
        notesDirectory.appendingPathComponent("content", isDirectory: true)
    }

    private var indexURL: URL {
        notesDirectory.appendingPathComponent("index.json")
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        ensureDirectories()
        loadInitial()
    }

    var activeNote: VoiceNote? {
        guard let activeNoteID else { return nil }
        return notes.first { $0.id == activeNoteID }
    }

    var activeTitleText: String {
        activeNote?.title ?? draftTitle
    }

    var hasActiveDraftOrNote: Bool {
        activeNoteID != nil
            || !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !activeContent.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Public API

    func observeDictationRuns(from runStore: RunStore) {
        guard runCancellable == nil else { return }

        observedRunStore = runStore
        runCancellable = runStore.$summaries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summaries in
                self?.handleRunSummaries(summaries)
            }
    }

    func beginDictationCapture(owner: String) {
        if lastSeenRunID == nil {
            lastSeenRunID = observedRunStore?.summaries.first?.id
        }
        dictationCaptureOwners.insert(owner)
    }

    func endDictationCapture(owner: String) {
        dictationCaptureOwners.remove(owner)
    }

    func isCapturingDictation(owner: String) -> Bool {
        dictationCaptureOwners.contains(owner)
    }

    func startDraft() {
        activeNoteID = nil
        draftTitle = ""
        activeContent = NSAttributedString(string: "")
        UserDefaults.standard.removeObject(forKey: Self.activeNoteDefaultsKey)
    }

    func reload() {
        let loaded = loadIndexSync().sorted { $0.updatedAt > $1.updatedAt }
        notes = loaded

        if let activeNoteID, let note = loaded.first(where: { $0.id == activeNoteID }) {
            activeContent = loadContentSync(for: note)
        } else if let first = loaded.first {
            select(first)
        } else {
            startDraft()
        }
    }

    func select(_ note: VoiceNote) {
        activeNoteID = note.id
        draftTitle = ""
        activeContent = loadContentSync(for: note)
        UserDefaults.standard.set(note.id.uuidString, forKey: Self.activeNoteDefaultsKey)
    }

    func updateActiveTitle(_ title: String) {
        if let activeNoteID, let index = notes.firstIndex(where: { $0.id == activeNoteID }) {
            notes[index].title = title
            notes[index].updatedAt = Date()
            sortNotes()
            persistIndex()
            return
        }

        draftTitle = title
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            createNote(content: activeContent, title: title)
        }
    }

    func updateActiveContent(_ content: NSAttributedString) {
        let normalized = Self.normalizedContent(content)
        activeContent = normalized

        if let activeNoteID, let index = notes.firstIndex(where: { $0.id == activeNoteID }) {
            let previousPlainText = notes[index].plainText
            let titleWasInferred = notes[index].title == VoiceNote.inferredTitle(from: previousPlainText)
                || notes[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            notes[index].plainText = normalized.string
            if titleWasInferred {
                notes[index].title = VoiceNote.inferredTitle(from: normalized.string)
            }
            notes[index].updatedAt = Date()
            sortNotes()
            guard let note = notes.first(where: { $0.id == activeNoteID }) else { return }
            persist(note: note, content: normalized)
            return
        }

        let hasBody = !normalized.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTitle = !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasBody || hasTitle {
            createNote(content: normalized, title: draftTitle)
        }
    }

    func appendTranscriptToActiveNote(_ transcript: String) {
        let incoming = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }

        let mutable = NSMutableAttributedString(attributedString: activeContent)
        if !mutable.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mutable.append(NSAttributedString(string: "\n\n", attributes: Self.defaultTypingAttributes))
        }
        mutable.append(NSAttributedString(string: incoming, attributes: Self.defaultTypingAttributes))
        updateActiveContent(mutable)
    }

    func delete(id: UUID) {
        guard let removed = notes.first(where: { $0.id == id }) else { return }
        notes.removeAll { $0.id == id }
        persistIndex()
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.contentURL(for: removed))
        }

        if activeNoteID == id {
            if let next = notes.first {
                select(next)
            } else {
                startDraft()
            }
        }
    }

    // MARK: - Internals

    private static let activeNoteDefaultsKey = "voice_notes_active_note_id"

    static let defaultFont = NSFont.systemFont(ofSize: 15)
    static let defaultParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        style.tailIndent = 0
        style.tabStops = []
        style.defaultTabInterval = 28
        style.textLists = []
        return style.copy() as! NSParagraphStyle
    }()

    static let defaultTypingAttributes: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: defaultParagraphStyle
    ]

    static func normalizedContent(_ content: NSAttributedString) -> NSAttributedString {
        guard content.length > 0 else { return content }

        let mutable = NSMutableAttributedString(attributedString: content)
        let fullRange = NSRange(location: 0, length: mutable.length)
        var ranges: [(attributes: [NSAttributedString.Key: Any], range: NSRange)] = []

        mutable.enumerateAttributes(in: fullRange) { attributes, range, _ in
            ranges.append((attributes, range))
        }

        for item in ranges {
            let attributes = item.attributes
            let range = item.range
            let font = attributes[.font] as? NSFont
            let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle

            mutable.addAttribute(.font, value: normalizedFont(from: font), range: range)
            mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            mutable.addAttribute(.paragraphStyle, value: normalizedParagraphStyle(from: paragraphStyle), range: range)
        }

        return mutable
    }

    static func normalizedTypingAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var normalized = attributes
        normalized[.font] = normalizedFont(from: attributes[.font] as? NSFont)
        normalized[.foregroundColor] = NSColor.labelColor
        normalized[.paragraphStyle] = defaultParagraphStyle
        return normalized
    }

    private static func normalizedFont(from sourceFont: NSFont?) -> NSFont {
        let sourceFont = sourceFont ?? defaultFont
        let traits = NSFontManager.shared.traits(of: sourceFont)
        var font = defaultFont

        if traits.contains(.boldFontMask) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if traits.contains(.italicFontMask) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        return font
    }

    private static func normalizedParagraphStyle(from paragraphStyle: NSParagraphStyle?) -> NSParagraphStyle {
        let mutable = (paragraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        mutable.textLists = []
        mutable.tabStops = []
        mutable.defaultTabInterval = 28
        mutable.firstLineHeadIndent = 0
        mutable.headIndent = 0
        mutable.tailIndent = 0
        mutable.lineSpacing = 2
        mutable.paragraphSpacing = 0
        mutable.paragraphSpacingBefore = 0
        return mutable.copy() as! NSParagraphStyle
    }

    private func handleRunSummaries(_ summaries: [RunSummary]) {
        guard let latest = summaries.first else { return }
        guard latest.id != lastSeenRunID else { return }
        lastSeenRunID = latest.id
        guard !dictationCaptureOwners.isEmpty else { return }
        guard latest.status == .success else { return }
        if let ownBundleID = Bundle.main.bundleIdentifier,
           latest.frontmostBundleID == ownBundleID {
            // The transcript was already pasted into a focused Vordi editor
            // by TextInjector. Mirroring it here would duplicate Notes input.
            return
        }
        appendTranscriptToActiveNote(latest.previewText)
    }

    private func createNote(content: NSAttributedString, title: String) {
        let normalized = Self.normalizedContent(content)
        let now = Date()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = VoiceNote(
            title: trimmedTitle.isEmpty ? VoiceNote.inferredTitle(from: normalized.string) : trimmedTitle,
            plainText: normalized.string,
            createdAt: now,
            updatedAt: now
        )

        notes.insert(note, at: 0)
        activeNoteID = note.id
        draftTitle = ""
        UserDefaults.standard.set(note.id.uuidString, forKey: Self.activeNoteDefaultsKey)
        persist(note: note, content: normalized)
    }

    private func sortNotes() {
        notes.sort { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
    }

    private func loadInitial() {
        let loaded = loadIndexSync().sorted { $0.updatedAt > $1.updatedAt }
        notes = loaded

        guard !loaded.isEmpty else { return }
        if
            let raw = UserDefaults.standard.string(forKey: Self.activeNoteDefaultsKey),
            let id = UUID(uuidString: raw),
            let saved = loaded.first(where: { $0.id == id })
        {
            select(saved)
        } else if let first = loaded.first {
            select(first)
        }
    }

    private func loadIndexSync() -> [VoiceNote] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? decoder.decode([VoiceNote].self, from: data)) ?? []
    }

    private func persistIndex() {
        let snapshot = notes
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try self.encoder.encode(snapshot)
                try data.write(to: self.indexURL, options: .atomic)
            } catch {
                print("VoiceNoteStore: failed to persist index - \(error)")
            }
        }
    }

    private func persist(note: VoiceNote, content: NSAttributedString) {
        let notesSnapshot = notes
        let contentCopy = NSAttributedString(attributedString: content)

        queue.async { [weak self] in
            guard let self else { return }
            do {
                let range = NSRange(location: 0, length: contentCopy.length)
                let data = try contentCopy.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                try data.write(to: self.contentURL(for: note), options: .atomic)

                let indexData = try self.encoder.encode(notesSnapshot)
                try indexData.write(to: self.indexURL, options: .atomic)
            } catch {
                print("VoiceNoteStore: failed to persist note - \(error)")
            }
        }
    }

    private func loadContentSync(for note: VoiceNote) -> NSAttributedString {
        let url = contentURL(for: note)
        guard let data = try? Data(contentsOf: url) else {
            return NSAttributedString(string: note.plainText, attributes: Self.defaultTypingAttributes)
        }

        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return Self.normalizedContent(attributed)
        }

        return NSAttributedString(string: note.plainText, attributes: Self.defaultTypingAttributes)
    }

    private func contentURL(for note: VoiceNote) -> URL {
        contentDirectory.appendingPathComponent(note.contentFilename)
    }
}
