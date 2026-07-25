import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Fixed colors for the always-dark Magic Words hero. Page-level adaptive
/// tokens can become light in dark mode, creating white-on-white example chips.
private enum MagicWordsHeroPalette {
    static let primaryText = Theme.textOnDark
    static let secondaryText = Theme.textOnDark.opacity(0.82)
    static let triggerFill = Theme.textOnDark.opacity(0.96)
    static let triggerText = Color(red: 0.102, green: 0.090, blue: 0.078)
    static let expansionFill = Color.black.opacity(0.34)
    static let expansionBorder = Theme.textOnDark.opacity(0.18)
}

private enum MagicWordsTab: String {
    case all
    case commands
    case custom
}

private struct MagicWordsInstalledApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
}

private final class MagicWordsInstalledApps: ObservableObject {
    @Published var apps: [MagicWordsInstalledApp] = []

    init() {
        apps = Self.loadApps()
    }

    private static func loadApps() -> [MagicWordsInstalledApp] {
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: applicationsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let featuredApps = [
            "Codex", "Claude", "ChatGPT", "Google Chrome",
            "Slack", "Visual Studio Code", "Postman", "WhatsApp"
        ]

        return urls
            .filter { $0.pathExtension == "app" }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                let icon = (NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage)
                    ?? NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 64, height: 64)
                return MagicWordsInstalledApp(id: url.path, name: name, icon: icon)
            }
            .filter { featuredApps.contains($0.name) }
            .sorted { lhs, rhs in
                let lhsRank = featuredApps.firstIndex(of: lhs.name) ?? Int.max
                let rhsRank = featuredApps.firstIndex(of: rhs.name) ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}

/// Editor for the magic-word registry.
///
/// **Design language**: matches Settings page — ScrollView, Theme.Space.xl
/// padding, VStack spacing 20, every group in a `themedCard()`.
///
/// **Why a tab vs. inline in Settings**: the registry can grow to 50+ entries.
/// An inline list inside the Settings tab balloons the page and pushes other
/// settings off-screen. Better as a focused surface with import/export.
struct MagicWordsSettingsView: View {
    @AppStorage(TransformerRouter.Keys.magicWordsEnabled)
    private var magicWordsEnabled: Bool = true

    @ObservedObject var store: MagicWordStore = .shared
    @StateObject private var installedApps = MagicWordsInstalledApps()

    @State private var editing: MagicWord?
    @State private var search: String = ""
    @State private var selectedTab: String = MagicWordsTab.all.rawValue
    @State private var hoveredEntryID: UUID?
    @State private var showAddSheet = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDoc: MagicWordExportDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                magicWordsPageHeader
                magicWordsToolbar
                if selectedTab != MagicWordsTab.custom.rawValue {
                    snippetHero
                }
                if selectedTab != MagicWordsTab.commands.rawValue {
                    customMagicWordsList
                }
            }
            .frame(maxWidth: Theme.Layout.centralContentWidth, alignment: .leading)
            .padding(.horizontal, Theme.Layout.contentHPad)
            .padding(.top, Theme.Layout.contentVPad)
            .padding(.bottom, 48)
        }
        .background(Theme.mainContent)
        .sheet(isPresented: $showAddSheet) {
            MagicWordEditorSheet(
                word: nil,
                onSave: { store.add($0); showAddSheet = false },
                onCancel: { showAddSheet = false }
            )
        }
        .sheet(item: $editing) { word in
            MagicWordEditorSheet(
                word: word,
                onSave: { store.update($0); editing = nil },
                onCancel: { editing = nil }
            )
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result: result)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .json,
            defaultFilename: "\(AppBrand.name.lowercased())-magic-words.json"
        ) { _ in }
    }

    // MARK: - Header

    private var magicWordsPageHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: Theme.Space.sm) {
                Text("Magic Words")
                    .font(.vfPageTitle)
                    .foregroundColor(Theme.textPrimary)
                VFBadge(label: magicWordsEnabled ? "Listening" : "Off",
                        style: magicWordsEnabled ? .promo : .plan)
            }

            Spacer()

            HStack(spacing: Theme.Space.md) {
                HStack(spacing: Theme.Space.sm) {
                    Text("Enabled")
                        .font(.vfCalloutMedium)
                        .foregroundColor(Theme.textPrimary)
                    VFSwitch(isOn: $magicWordsEnabled)
                }
                .padding(.leading, Theme.Space.md)
                .padding(.trailing, Theme.Space.sm)
                .padding(.vertical, Theme.Space.sm)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.compactToggleFill)
                )

                VFButton(title: "Add new", style: .primary) {
                    showAddSheet = true
                }
            }
        }
    }

    private var magicWordsToolbar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VFTabBar(
                    options: [
                        ("all", "All"),
                        ("commands", "App commands"),
                        ("custom", "Custom snippets"),
                    ],
                    selection: $selectedTab
                )

                Spacer(minLength: Theme.Space.lg)

                HStack(spacing: Theme.Space.sm) {
                    VFSearchBar(text: $search, placeholder: "Search")
                        .opacity(selectedTab == MagicWordsTab.commands.rawValue ? 0.45 : 1)
                        .disabled(selectedTab == MagicWordsTab.commands.rawValue)
                    magicToolbarIcon("square.and.arrow.down", help: "Import") {
                        showImporter = true
                    }
                    magicToolbarIcon("square.and.arrow.up", help: "Export") {
                        exportDoc = MagicWordExportDocument(entries: store.snapshot())
                        showExporter = true
                    }
                }
            }
            .padding(.bottom, Theme.Space.sm)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
        }
    }

    private var snippetHero: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                snippetHeroTitle
                Text("Save the phrases you repeat. When you say the short version, \(AppBrand.name) expands it before typing.")
                    .font(.vfCallout)
                    .foregroundColor(MagicWordsHeroPalette.secondaryText)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            snippetHeroFlow(
                trigger: "project intro",
                expansion: "Thanks for the context. Here is the short version of the plan and the next steps."
            )
            .padding(.top, Theme.Space.xs)

            commandExecutionInline
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .background {
            VFBlueMeshHeroBackground()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(Theme.dividerStrong, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.elevated.color,
                radius: Theme.Shadow.elevated.radius,
                x: 0,
                y: Theme.Shadow.elevated.y)
    }

    private var commandExecutionInline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Rectangle()
                .fill(MagicWordsHeroPalette.primaryText.opacity(0.18))
                .frame(height: 1)
                .padding(.top, Theme.Space.xs)

            executeCommandQuote

            if installedApps.apps.isEmpty {
                Text("No apps found in /Applications.")
                    .font(.vfCallout)
                    .foregroundColor(MagicWordsHeroPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Space.sm)
            } else {
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    ForEach(installedApps.apps) { app in
                        installedAppIcon(app)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, Theme.Space.xs)
    }

    private func installedAppIcon(_ app: MagicWordsInstalledApp) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(app.name)
                .font(.vfCaption)
                .foregroundColor(MagicWordsHeroPalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 58)
        }
        .help("Say \"Open \(app.name)\" followed by the action or text you want.")
    }

    private var snippetHeroTitle: some View {
        (Text("Snippets turn ")
            .font(.system(size: 26, weight: .semibold, design: .serif))
         + Text("short phrases")
            .font(.custom("Georgia", size: 26).italic())
         + Text(" into full text.")
            .font(.system(size: 26, weight: .semibold, design: .serif)))
            .foregroundColor(MagicWordsHeroPalette.primaryText)
    }

    private var executeCommandQuote: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Image(systemName: "quote.opening")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MagicWordsHeroPalette.secondaryText)
            Text("“open Claude and draft a release checklist”")
                .font(.vfCalloutSemibold)
                .foregroundColor(MagicWordsHeroPalette.primaryText)
        }
        .padding(.top, Theme.Space.xs)
    }

    private func snippetHeroFlow(trigger: String, expansion: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(trigger)
                .font(.vfCalloutSemibold)
                .foregroundColor(MagicWordsHeroPalette.triggerText)
                .lineLimit(1)
                .padding(.horizontal, Theme.Space.md)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                        .fill(MagicWordsHeroPalette.triggerFill)
                )
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MagicWordsHeroPalette.secondaryText)
            Text("“\(expansion)”")
                .font(.vfCalloutMedium)
                .foregroundColor(MagicWordsHeroPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .truncationMode(.tail)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                        .fill(MagicWordsHeroPalette.expansionFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                        .strokeBorder(MagicWordsHeroPalette.expansionBorder, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var customMagicWordsList: some View {
        VStack(spacing: 0) {
            if filteredEntries.isEmpty {
                emptyState
            } else {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                    row(for: entry)
                    if index < filteredEntries.count - 1 {
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

    private func magicToolbarIcon(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "text.quote")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            Text(store.entries.isEmpty ? "No custom snippets yet" : "No matches")
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)
            Text(store.entries.isEmpty
                 ? "Add a phrase like \"git wip\" and \(AppBrand.name) will expand it when you speak."
                 : "Try a different search.")
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for entry: MagicWord) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            Text("\(entry.phrase) → \(entry.expansion)")
                .font(.vfBody)
                .foregroundColor(entry.enabled ? Theme.textPrimary : Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !entry.enabled {
                disabledPill
            }

            HStack(spacing: Theme.Space.xs) {
                magicRowIcon("pencil", help: "Edit") {
                    editing = entry
                }
                magicRowIcon("trash", help: "Delete", color: Theme.danger) {
                    store.delete(id: entry.id)
                }
            }
            .opacity(hoveredEntryID == entry.id ? 1 : 0)
        }
        .padding(.horizontal, 18)
        .frame(height: Theme.Layout.listRowHeight)
        .background(hoveredEntryID == entry.id ? Theme.surfaceElevated.opacity(0.38) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            editing = entry
        }
        .vfClickableCursor()
        .onHover { isHovering in
            hoveredEntryID = isHovering ? entry.id : nil
        }
    }

    // MARK: - Pills

    private var disabledPill: some View {
        Text("disabled")
            .font(.system(size: 10))
            .foregroundColor(Theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.divider.opacity(0.6)))
    }

    // MARK: - Helpers

    private var filteredEntries: [MagicWord] {
        let all = store.entries.sorted { $0.updatedAt > $1.updatedAt }
        if selectedTab == MagicWordsTab.commands.rawValue {
            return []
        }
        guard !search.isEmpty else { return all }
        let q = search.lowercased()
        return all.filter {
            $0.phrase.lowercased().contains(q)
                || $0.expansion.lowercased().contains(q)
                || ($0.tag ?? "").lowercased().contains(q)
        }
    }

    private func magicRowIcon(
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

    private func handleImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let imported = try? decoder.decode([MagicWord].self, from: data) {
                store.replaceAll(imported)
            }
        case .failure(let err):
            print("Magic Words import failed: \(err)")
        }
    }
}

// MARK: - Editor sheet

struct MagicWordEditorSheet: View {
    @State private var phrase: String
    @State private var expansion: String
    @State private var tag: String
    @State private var scope: AppSurface?
    @State private var enabled: Bool
    private let original: MagicWord?
    private let onSave: (MagicWord) -> Void
    private let onCancel: () -> Void

    init(
        word: MagicWord?,
        onSave: @escaping (MagicWord) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.original = word
        self.onSave = onSave
        self.onCancel = onCancel
        _phrase = State(initialValue: word?.phrase ?? "")
        _expansion = State(initialValue: word?.expansion ?? "")
        _tag = State(initialValue: word?.tag ?? "")
        _scope = State(initialValue: word?.surfaceScope)
        _enabled = State(initialValue: word?.enabled ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            editorHeader
            editorFormCard
            editorFooter
        }
        .padding(Theme.Space.xl)
        .frame(width: Theme.Layout.modalEditorWidth, height: 480)
        .background(Theme.mainContent)
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(original == nil ? "New snippet" : "Edit snippet")
                .font(.vfSectionTitle)
                .foregroundColor(Theme.textPrimary)
            Text("Set the phrase, expansion, and where \(AppBrand.name) should apply it.")
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editorFormCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                editorFieldHeader("Phrase", "The short phrase you say.")
                editorTextField("project intro", text: $phrase)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.md)

            editorDivider

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                editorFieldHeader("Expansion", "The text \(AppBrand.name) inserts.")
                expansionEditor
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.md)

            editorDivider

            HStack(alignment: .bottom, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    editorFieldHeader("Tag", "Optional grouping.")
                    editorTextField("git, k8s, sql", text: $tag, width: 210)
                }
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    editorFieldHeader("Scope", "Where it can trigger.")
                    VFDropdown(options: scopeOptions, selection: scopeSelection, width: 180)
                }

                Spacer()

                HStack(spacing: Theme.Space.sm) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Enabled")
                            .font(.vfBody)
                            .foregroundColor(Theme.textPrimary)
                        Text(enabled ? "Active" : "Paused")
                            .font(.vfDescription)
                            .foregroundColor(Theme.textSecondary)
                    }
                    VFSwitch(isOn: $enabled)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.md)
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

    private var editorFooter: some View {
        HStack(spacing: Theme.Space.sm) {
            Spacer()
            VFButton(title: "Cancel", style: .secondary, isCompact: true, action: onCancel)
                .keyboardShortcut(.cancelAction)
            VFButton(
                title: "Save",
                style: .primary,
                isCompact: true,
                isDisabled: !canSave,
                action: save
            )
            .keyboardShortcut(.defaultAction)
        }
    }

    private var expansionEditor: some View {
        ZStack(alignment: .topLeading) {
            if expansion.isEmpty {
                Text("Thanks for the context. Here is the short version of the plan and the next steps.")
                    .font(.vfCallout)
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $expansion)
                .font(.vfCallout)
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(height: 112)
        .background(inputBackground)
        .overlay(inputBorder)
    }

    private var editorDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .padding(.leading, Theme.Space.xl)
    }

    private var scopeOptions: [(id: String, label: String)] {
        [(id: "any", label: "Any surface")]
            + AppSurface.allKnown.map { (id: $0.rawValue, label: $0.rawValue.capitalized) }
    }

    private var scopeSelection: Binding<String> {
        Binding(
            get: { scope?.rawValue ?? "any" },
            set: { newValue in
                scope = newValue == "any" ? nil : AppSurface(rawValue: newValue)
            }
        )
    }

    private var canSave: Bool {
        !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
            .fill(Theme.surfaceElevated)
    }

    private var inputBorder: some View {
        RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
            .strokeBorder(Theme.dividerStrong, lineWidth: 1)
    }

    private func editorFieldHeader(_ title: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)
            Text(description)
                .font(.vfDescription)
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: Theme.Space.md)
        }
    }

    private func editorTextField(
        _ placeholder: String,
        text: Binding<String>,
        width: CGFloat? = nil
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.vfCallout)
            .foregroundColor(Theme.textPrimary)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .frame(width: width, height: Theme.Layout.inputHeight)
            .background(inputBackground)
            .overlay(inputBorder)
    }

    private func save() {
        guard canSave else { return }
        let word = MagicWord(
            id: original?.id ?? UUID(),
            phrase: phrase.trimmingCharacters(in: .whitespacesAndNewlines),
            expansion: expansion,
            tag: tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : tag.trimmingCharacters(in: .whitespacesAndNewlines),
            surfaceScope: scope,
            enabled: enabled,
            updatedAt: Date()
        )
        onSave(word)
    }
}

extension AppSurface {
    /// Surfaces that make sense as a scope filter — exclude `.unknown`
    /// because filtering on "unknown" means "this should never trigger
    /// when we couldn't detect", which is a bug magnet.
    static var allKnown: [AppSurface] {
        [.ide, .terminal, .browser, .chat, .mail, .notes, .office, .database, .design]
    }
}

// MARK: - Export document

struct MagicWordExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let entries: [MagicWord]

    init(entries: [MagicWord]) {
        self.entries = entries
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.entries = (try? decoder.decode([MagicWord].self, from: data)) ?? []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        return FileWrapper(regularFileWithContents: data)
    }
}
