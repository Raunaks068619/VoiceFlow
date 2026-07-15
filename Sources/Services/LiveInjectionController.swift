import Foundation
import AppKit
import Carbon

/// PROTOTYPE (Option B): live "type-as-you-speak" injection.
///
/// While a realtime stream is producing partial transcripts, this controller
/// types those partials **directly into the frontmost app** — the way macOS
/// dictation does — then reconciles the provisional preview to the final,
/// post-processed text when the utterance completes.
///
/// How it stays sane:
///   - The realtime `onPartial` callback is *cumulative* (the whole transcript
///     so far, revised). So on each update we diff the new text against what we
///     already typed, delete only the changed suffix (backspaces), and type the
///     new suffix. That minimises flicker and matches how a streaming decoder
///     revises earlier words.
///   - On finalize we diff once more against the polished final text and let the
///     same suffix-replace land it — so magic-words / polish / language-guard
///     still get the last word, literally.
///   - On failure/fallback we can `cancel()` to yank the provisional text back
///     out, leaving the field clean for the batch path to paste into.
///
/// Why this is behind a default-OFF flag (`live_inject_enabled`):
///   - It synthesises keystrokes into whatever is focused. If focus moves
///     mid-utterance, backspaces could eat real user content. This is the
///     inherent fragility we flagged for Option B — the flag keeps it opt-in
///     until it's proven per-app.
///
/// Focus assumption: Vordi's recording chips are `nonactivatingPanel`s
/// (`canBecomeKey == false`), so the target app keeps key focus while we type.
/// This whole approach depends on that staying true.
///
/// Threading: main-thread only. `onPartial` and the finalize path both dispatch
/// onto main before calling in; the CGEvent posts must run on main too.
final class LiveInjectionController {

    /// UserDefaults flag. Default OFF — this is an opt-in prototype.
    static let enabledKey = "live_inject_enabled"

    /// Whether a live session is currently tracking provisional text.
    private(set) var isActive = false

    /// The exact string we have currently typed into the target field as a
    /// preview. The source of truth for the next diff.
    private var provisional = ""

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Begin a live session. Call when a realtime stream starts and the flag is
    /// on. Resets provisional state; nothing is typed yet.
    func begin() {
        assertMain()
        isActive = true
        provisional = ""
    }

    /// Update the on-screen preview to `cumulativeText` (the full transcript so
    /// far). Types only the changed suffix. No-op if not active.
    func update(to cumulativeText: String) {
        assertMain()
        guard isActive else { return }
        let next = Self.sanitize(cumulativeText)
        applyDiff(from: provisional, to: next)
        provisional = next
    }

    /// Reconcile the preview to the final, post-processed `finalText` and end the
    /// session. Returns true if it handled injection — the caller must then NOT
    /// paste, or the final text would land twice.
    @discardableResult
    func finalize(with finalText: String) -> Bool {
        assertMain()
        guard isActive else { return false }
        let target = Self.sanitize(finalText)
        applyDiff(from: provisional, to: target)
        provisional = ""
        isActive = false
        return true
    }

    /// Pull the provisional preview back out (delete everything we typed) and end
    /// the session. Use when the pipeline is going to recover some other way
    /// (hard transcription failure) so the field isn't left holding a half-baked
    /// preview. No-op if not active.
    func cancel() {
        assertMain()
        guard isActive else { return }
        applyDiff(from: provisional, to: "")
        provisional = ""
        isActive = false
    }

    // MARK: - Diff + edit

    /// Turn `old` into `new` in the focused field using the fewest edits: keep the
    /// common prefix, backspace the rest of `old`, type the rest of `new`.
    /// Works in grapheme clusters so one backspace maps to one visible character.
    private func applyDiff(from old: String, to new: String) {
        guard old != new else { return }
        let oldChars = Array(old)   // [Character] — grapheme clusters
        let newChars = Array(new)

        var common = 0
        let limit = min(oldChars.count, newChars.count)
        while common < limit && oldChars[common] == newChars[common] { common += 1 }

        let deletions = oldChars.count - common
        if deletions > 0 { KeystrokeSynth.backspace(times: deletions) }

        if common < newChars.count {
            KeystrokeSynth.type(String(newChars[common...]))
        }
    }

    /// Keep the preview single-line and free of control characters. A stray
    /// newline mid-stream would submit chat inputs / break indentation, and we
    /// can't reliably backspace across a committed newline in every app.
    private static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private func assertMain() {
        assert(Thread.isMainThread, "LiveInjectionController must be driven on the main thread")
    }
}

/// Minimal synthetic-keystroke helper for the live-injection prototype. Posts
/// Unicode characters and backspaces to the frontmost app via the HID event tap.
enum KeystrokeSynth {

    /// Type an arbitrary string. Uses the virtualKey-0 + `keyboardSetUnicodeString`
    /// trick so any Unicode (including non-ASCII) lands regardless of keyboard
    /// layout. One down/up pair per grapheme cluster.
    static func type(_ string: String) {
        guard !string.isEmpty, let source = CGEventSource(stateID: .hidSystemState) else { return }
        for character in string {
            let utf16 = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            utf16.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
                    up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
                }
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Send `times` backspaces (kVK_Delete = 0x33).
    static func backspace(times: Int) {
        guard times > 0, let source = CGEventSource(stateID: .hidSystemState) else { return }
        for _ in 0..<times {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) else { continue }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
