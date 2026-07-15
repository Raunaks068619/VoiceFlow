import SwiftUI
import AppKit

// MARK: - Design System
//
// This file EXTENDS the base Theme enum declared in MainDashboardView.swift
// with all design tokens derived from the Wispr Flow macOS app reference
// screenshots (47 screens captured 2026-05-25).
//
// It also houses shared UI components for new and migrated views.
//
// ─── Token reference ────────────────────────────────────────────────────────
//
//  BACKGROUNDS          DEFINED IN
//  canvas               MainDashboardView  — sidebar/chrome (cream #F5F1EA)
//  mainContent          MainDashboardView  — main pane (#FBFAF7)
//  surface              MainDashboardView  — cards (#FAF7F1)
//  surfaceElevated      MainDashboardView  — modals/popovers (white)
//  surfaceDark          MainDashboardView  — always-dark hero (#18150D)
//  surfaceDarkSoft      MainDashboardView  — layered dark element
//
//  TEXT
//  textPrimary          MainDashboardView  — near-black warm (#1A1714)
//  textSecondary        MainDashboardView  — muted brown (#5A5450)
//  textTertiary         MainDashboardView  — placeholder (#8E837C)
//  textOnDark           MainDashboardView  — cream on dark surfaces
//
//  BRAND
//  accent / accentSoft  MainDashboardView  — orange #FF8C1A
//  interactive          DesignSystem       — violet #7C4AED (focus, selected cards)
//  interactiveSoft      DesignSystem       — violet @ 12% opacity
//  dropdownSelectionFill DesignSystem      — softer violet for menu rows
//
//  SEMANTIC
//  success/warning/danger  MainDashboardView
//
//  UTILITY
//  divider / dividerStrong  MainDashboardView
//  secondaryButtonFill       DesignSystem   — warm gray secondary CTA fill
//  searchHighlight          DesignSystem   — yellow match highlight
//  promoTint / promoText    DesignSystem   — lavender promo chips
//
//  SCALES
//  Theme.Radius.*       MainDashboardView (chip=10, button=10, card=16, hero=20)
//                       DesignSystem extends with xs=4, sm=6, input=8, modal=12
//  Theme.Space.*        MainDashboardView (xs=4, sm=8, md=12, lg=16, xl=24, xxl=32)
//  Theme.Shadow.*       MainDashboardView (card, elevated)
//                       DesignSystem extends with tooltip
//  Theme.Layout.*       DesignSystem       — point measurements from 2x screenshots

// MARK: - Theme extensions ────────────────────────────────────────────────────

extension Theme {

    // ── Interactive accent (violet) ───────────────────────────────────────────
    // Used for: selection borders (mic picker, language grid), focus rings on
    // text inputs, selected cards, and checkmarks in dropdowns.
    // Based on the consistent purple-violet seen on selected items throughout
    // the Wispr Flow reference screens.

    private static func adaptiveInteractive(
        light: (Double, Double, Double),
        dark:  (Double, Double, Double)
    ) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }))
    }

    /// Violet accent for selected/focused states. Do not use for primary CTAs.
    static let interactive     = adaptiveInteractive(
        light: (0.486, 0.290, 0.929),   // #7C4AED — vivid violet
        dark:  (0.612, 0.451, 0.965)    // #9C73F6 — lightened for dark bg
    )
    static let interactiveSoft = Color(red: 0.486, green: 0.290, blue: 0.929).opacity(0.12)
    static let dropdownSelectionFill = Color(red: 0.486, green: 0.290, blue: 0.929).opacity(0.07)
    static let dropdownSelectionBorder = Color(red: 0.486, green: 0.290, blue: 0.929).opacity(0.10)

    // ── Sidebar active state ─────────────────────────────────────────────────
    // Sampled from the Wispr Flow Scratchpad selected nav row: #EEEBE4.
    // This is darker and warmer than card surfaces, so the active tab reads as
    // navigation state instead of a floating white card inside the sidebar.
    static let sidebarActiveFill = adaptiveInteractive(
        light: (0.933, 0.922, 0.894),   // #EEEBE4
        dark:  (0.180, 0.165, 0.149)    // #2E2A26
    )

    // ── Search highlight ───────────────────────────────────────────────────────
    // Yellow background on matching characters in Dictionary/Snippets search.
    static let searchHighlight = Color(red: 1.000, green: 0.898, blue: 0.541).opacity(0.70)

    // ── Promo tint ────────────────────────────────────────────────────────────
    // Lavender background for "2-week pro trial" and similar inline chips.
    static let promoTint = Color(red: 0.929, green: 0.910, blue: 1.000)   // #EDE8FF
    static let promoText = Color(red: 0.435, green: 0.259, blue: 0.863)   // #6F42DC

    // ── Insights accent ──────────────────────────────────────────────────────
    // Deep teal used only for usage charts and streak heatmaps. Keeping this
    // scoped prevents the app from becoming another global-accent dashboard.
    static let insightAccent = adaptiveInteractive(
        light: (0.086, 0.404, 0.388),   // #166763
        dark:  (0.438, 0.784, 0.753)    // #70C8C0
    )
    static let insightAccentSoft = adaptiveInteractive(
        light: (0.455, 0.765, 0.714),   // #74C3B6
        dark:  (0.263, 0.580, 0.541)    // #43948A
    )

    // ── Secondary CTA fill ────────────────────────────────────────────────────
    // Warm gray fill for secondary buttons. Darker than canvas so buttons read
    // clearly on grouped settings sections without becoming outlined controls.
    static let secondaryButtonFill = adaptiveInteractive(
        light: (0.929, 0.914, 0.882),   // #EDE9E1
        dark:  (0.259, 0.239, 0.216)    // #423D37
    )

    // Floating notes action controls intentionally invert in dark mode:
    // the pill stays cream and the label/icon stay warm black. This keeps
    // controls readable on the dark floating editor without changing global
    // button semantics.
    static let floatingActionFill = adaptiveInteractive(
        light: (0.102, 0.090, 0.078),   // #1A1714
        dark:  (0.961, 0.945, 0.918)    // #F5F1EA
    )
    static let floatingActionForeground = adaptiveInteractive(
        light: (0.961, 0.945, 0.918),   // #F5F1EA
        dark:  (0.102, 0.090, 0.078)    // #1A1714
    )
    static let floatingControlFill = adaptiveInteractive(
        light: (1.000, 1.000, 1.000),   // white toolbar in light mode
        dark:  (0.961, 0.945, 0.918)    // cream toolbar in dark mode
    )
    static let floatingControlForeground = adaptiveInteractive(
        light: (0.353, 0.329, 0.314),   // #5A5450
        dark:  (0.102, 0.090, 0.078)    // #1A1714
    )

    // ── Toggle fills ─────────────────────────────────────────────────────────
    // Explicit switch colors keep off-state controls visible on dark warm
    // surfaces. Avoid opacity-only fills here, because they collapse into the
    // surrounding dark card/background.
    static let compactToggleFill = adaptiveInteractive(
        light: (0.980, 0.968, 0.945),   // #FAF7F1
        dark:  (0.173, 0.157, 0.137)    // #2C2823
    )
    static let segmentedToggleTrackFill = adaptiveInteractive(
        light: (0.910, 0.894, 0.859),   // #E8E4DB
        dark:  (0.173, 0.157, 0.137)    // #2C2823
    )
    static let segmentedToggleActiveFill = adaptiveInteractive(
        light: (0.984, 0.980, 0.969),   // #FBFAF7
        dark:  (0.259, 0.239, 0.216)    // #423D37
    )
    static let switchOnFill = adaptiveInteractive(
        light: (0.102, 0.090, 0.078),   // #1A1714
        dark:  (0.090, 0.078, 0.063)    // #17140F
    )
    static let switchOffFill = adaptiveInteractive(
        light: (0.859, 0.839, 0.800),   // #DBD6CC
        dark:  (0.392, 0.361, 0.318)    // #645C51
    )
    static let switchOnThumbFill = adaptiveInteractive(
        light: (0.984, 0.980, 0.969),   // #FBFAF7
        dark:  (0.961, 0.945, 0.918)    // #F5F1EA
    )
    static let switchOffThumbFill = adaptiveInteractive(
        light: (0.984, 0.980, 0.969),   // #FBFAF7
        dark:  (0.180, 0.165, 0.149)    // #2E2A26
    )

    // ── Secondary text on dark surfaces ──────────────────────────────────────
    // Slightly muted cream for body copy inside dark hero banners.
    static let textOnDarkSecondary = Color(red: 0.706, green: 0.678, blue: 0.643).opacity(0.85)

    // ── Radius additions ──────────────────────────────────────────────────────
    // (Radius enum declared in MainDashboardView; add a parallel struct here
    //  for the sizes that weren't in the original scale.)
    enum RadiusExtra {
        static let xs:    CGFloat = 4    // badges, tiny tag chips
        static let sm:    CGFloat = 6    // dropdown menus, tooltips
        static let input: CGFloat = 8    // text fields
        static let modal: CGFloat = 12   // dialogs, sheets, popovers
    }

    // ── Shadow addition ───────────────────────────────────────────────────────
    enum ShadowExtra {
        static let tooltip = (color: Color.black.opacity(0.14), radius: CGFloat(10), y: CGFloat(4))
    }

    // ── Layout constants ──────────────────────────────────────────────────────
    // Point measurements observed from the 3024 x 1964 px reference screenshots.
    // The captures are 2x Retina, so these are original pixels divided by 2.
    enum Layout {
        static let appCaptureWidth:     CGFloat = 1512
        static let appCaptureHeight:    CGFloat = 982
        static let sidebarWidth:        CGFloat = 218
        static let contentHPad:         CGFloat = 44
        static let contentVPad:         CGFloat = 28
        static let centralContentWidth: CGFloat = 808
        static let settingsPanelWidth:  CGFloat = 960
        static let settingsPanelHeight: CGFloat = 640
        static let settingsNavWidth:    CGFloat = 212
        static let listRowHeight:       CGFloat = 56
        static let inputHeight:         CGFloat = 40
        static let actionButtonHeight:  CGFloat = 38
        static let modalWidth:          CGFloat = 528
        static let modalSmWidth:        CGFloat = 528
        static let modalEditorWidth:    CGFloat = 688
        static let confirmModalWidth:   CGFloat = 688
        static let languageModalWidth:  CGFloat = 852
        static let loadingModalWidth:   CGFloat = 720
        static let loadingModalHeight:  CGFloat = 504
    }
}

// MARK: - App Brand ────────────────────────────────────────────────────────────

enum AppBrand {
    static let name = "Vordi"
    static let legacyName = "Vordi"
    static let logoImageName = "vordi_transparent_background"
    static let coloredLogoImageName = "vordi_transparent_background_colored_logo_less_padding"

    static var logoImage: NSImage? {
        image(named: logoImageName)
    }

    static var coloredLogoImage: NSImage? {
        image(named: coloredLogoImageName)
    }

    static var templateLogoImage: NSImage? {
        guard let image = logoImage?.copy() as? NSImage else { return nil }
        image.isTemplate = true
        return image
    }

    private static func image(named name: String) -> NSImage? {
        NSImage(named: NSImage.Name(name))
            ?? Bundle.main.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
}

enum VFBrandLogoVariant {
    case automatic
    case colored
    case light
    case dark
}

struct VFBrandLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: CGFloat = 24
    var variant: VFBrandLogoVariant = .automatic
    var cornerRadius: CGFloat?

    private var usesColoredMark: Bool {
        switch variant {
        case .automatic:
            return colorScheme == .light
        case .colored:
            return true
        case .light:
            return colorScheme == .light
        case .dark:
            return false
        }
    }

    private var resolvedImage: NSImage? {
        usesColoredMark ? AppBrand.coloredLogoImage : AppBrand.logoImage
    }

    var body: some View {
        ZStack {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .foregroundColor(usesColoredMark ? Theme.textPrimary : Theme.textOnDark)
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius ?? max(size * 0.18, 4),
                style: .continuous
            )
        )
        .accessibilityLabel(AppBrand.name)
    }
}

struct VFMenuBarBrandIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    // The brand glyph is the 5-bar waveform mark. We draw it directly as a
    // monochrome template at menu-bar scale instead of templating the square
    // app-icon PNG — that asset's opaque square fills solid white when used as
    // a template, producing an oversized white block in the menu bar.
    private static let barHeights: [CGFloat] = [7, 13, 17, 12, 7]

    private var menuBarColor: Color {
        colorScheme == .dark
            ? Color(nsColor: .white).opacity(0.96)
            : Color(nsColor: .black).opacity(0.86)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 1.8) {
            ForEach(Self.barHeights.indices, id: \.self) { index in
                Capsule()
                    .frame(width: 2.6, height: Self.barHeights[index])
            }
        }
        .frame(width: 22, height: 20, alignment: .center)
        .foregroundStyle(menuBarColor)
        .shadow(color: Color(nsColor: .black).opacity(colorScheme == .dark ? 0.28 : 0), radius: 0.5, x: 0, y: 0)
        .accessibilityLabel(AppBrand.name)
    }
}

// MARK: - Typography ──────────────────────────────────────────────────────────
//
// Named scale derived from pixel measurements in the Wispr Flow reference.
// Rules (enforced in code review):
//   • Always use Font.vf* — never .font(.caption) or bare .system(size:).
//   • Serif variants mix Georgia italic into hero headlines for editorial flair.
//   • vfCategoryLabel produces the "SETTINGS" / "ACCOUNT" sidebar header look
//     (must be combined with .textCase(.uppercase) at the call site).

extension Font {
    // Hero display — large headlines in dark banner cards.
    // Combine plain + italic segments for the Wispr Flow editorial look:
    //   "The stuff "  →  vfDisplay  (bold sans)
    //   "you"         →  vfDisplaySerif  (serif italic)
    //   " shouldn't…" →  vfDisplay
    static let vfDisplaySerif    = Font.custom("Georgia", size: 26).italic()
    static let vfDisplay         = Font.system(size: 26, weight: .semibold)

    // Page title — "Dictionary", "Snippets", "Scratchpad", "Settings"
    static let vfPageTitle       = Font.system(size: 20, weight: .semibold)

    // Settings content section header — "General", "System", "Account"
    static let vfSectionTitle    = Font.custom("Georgia", size: 24)

    // Primary body — nav items, list rows, form labels, modal titles
    static let vfBodyMedium      = Font.system(size: 14, weight: .medium)
    static let vfBody            = Font.system(size: 14, weight: .regular)

    // Supporting — control labels, dropdown values, modal body
    static let vfCallout         = Font.system(size: 13, weight: .regular)
    static let vfCalloutMedium   = Font.system(size: 13, weight: .medium)
    static let vfCalloutSemibold = Font.system(size: 13, weight: .semibold)

    // Settings row descriptions only. Keep controls on vfCallout/vfBody.
    static let vfDescription     = Font.system(size: 10, weight: .regular)

    // Tiny — timestamps, footnotes, version labels
    static let vfCaption         = Font.system(size: 11, weight: .regular)
    static let vfMicro           = Font.system(size: 10, weight: .medium)

    // Badge text
    static let vfBadge           = Font.system(size: 10, weight: .semibold)

    // Settings sidebar category labels ("SETTINGS", "ACCOUNT").
    // Pair with .textCase(.uppercase) and letter-spacing.
    static let vfCategoryLabel   = Font.system(size: 10, weight: .semibold)

    // Hotkey chips ("fn", "fn Space") — monospaced for keyboard-key feel
    static let vfKeyLabel        = Font.system(size: 13, weight: .semibold, design: .monospaced)
    static let vfKeyLabelSm      = Font.system(size: 11, weight: .semibold, design: .monospaced)

    // Timestamp / date section headers in timeline
    static let vfTimestamp       = Font.system(size: 11, weight: .regular)
    static let vfDateHeader      = Font.system(size: 11, weight: .semibold)
}

// MARK: - Cursor helpers ───────────────────────────────────────────────────────

private struct VFHoverCursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                guard isHovering else { return }
                NSCursor.pop()
                isHovering = false
            }
    }
}

// MARK: - View modifier extensions ────────────────────────────────────────────

extension View {
    func vfCursor(_ cursor: NSCursor) -> some View {
        modifier(VFHoverCursorModifier(cursor: cursor))
    }

    @ViewBuilder
    func vfClickableCursor(_ enabled: Bool = true) -> some View {
        if enabled {
            vfCursor(.pointingHand)
        } else {
            self
        }
    }

    /// Modal / dialog surface — white fill, rounded, heavy shadow.
    func themedModalCard(padding: CGFloat = Theme.Space.xxl) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
            .shadow(color: Theme.Shadow.elevated.color,
                    radius: Theme.Shadow.elevated.radius,
                    x: 0, y: Theme.Shadow.elevated.y)
    }

    /// Popover / dropdown menu — white fill, hairline border, shadow.
    func themedPopover() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .shadow(color: Theme.Shadow.elevated.color,
                    radius: Theme.Shadow.elevated.radius,
                    x: 0, y: Theme.Shadow.elevated.y)
    }

    /// Standard 40 pt form input chrome. Apply to `TextField`, `SecureField`,
    /// or small custom controls that need to read as editable inputs.
    func vfInputChrome(isFocused: Bool = false) -> some View {
        self
            .padding(.horizontal, Theme.Space.md)
            .frame(height: Theme.Layout.inputHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .strokeBorder(isFocused ? Theme.interactive : Theme.dividerStrong, lineWidth: 1)
            )
    }

    /// Large editable box chrome, used for snippets and long-form text.
    func vfTextAreaChrome(minHeight: CGFloat = 220, isFocused: Bool = false) -> some View {
        self
            .padding(Theme.Space.md)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .strokeBorder(isFocused ? Theme.interactive : Theme.divider, lineWidth: 1)
            )
    }
}

// MARK: - VFTabBar ────────────────────────────────────────────────────────────
//
// Inline underline tab bar. Used for All / Personal / Shared with team.
//
//   Active:   black text + 2pt solid bottom border
//   Inactive: textSecondary, no border, no background
//
// Usage:
//   VFTabBar(options: [("all","All"),("personal","Personal")], selection: $tab)

struct VFTabBar: View {
    let options: [(id: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { opt in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = opt.id }
                } label: {
                    VStack(spacing: 0) {
                        Text(opt.label)
                            .font(.vfBody)
                            .foregroundColor(selection == opt.id
                                ? Theme.textPrimary
                                : Theme.textSecondary)
                            .padding(.horizontal, 2)
                            .padding(.bottom, 7)
                        Rectangle()
                            .fill(selection == opt.id ? Theme.textPrimary : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }
}

// MARK: - VFButton ────────────────────────────────────────────────────────────
//
// Every button in the app. Variants mirror all button patterns in Wispr Flow:
//
//   .primary     — black fill, white text. All primary CTAs:
//                  "Add new", "Save", "Upgrade to Pro", "Continue".
//   .secondary   — warm gray fill, dark text, no outline.
//                  Settings "Change" buttons, secondary actions.
//   .destructive — danger (coral-red) fill, white text.
//                  "Yes, delete it" buttons.
//   .ghost       — no background, textSecondary. Inline "Cancel".
//   .outline     — semi-transparent + white border. CTA inside hero cards.
//   .pill        — black pill with icon+text. Floating "Copy" action button.

enum VFButtonStyle {
    case primary, secondary, destructive, ghost, outline, pill
}

struct VFButton: View {
    let title: String
    var icon: String?              // optional SF Symbol before the label
    var style: VFButtonStyle = .primary
    var isCompact: Bool = false
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    private var font:  Font    { isCompact ? .vfCalloutMedium : .vfBodyMedium }
    private var hPad:  CGFloat { isCompact ? 16 : 24 }
    private var height: CGFloat { isCompact ? 36 : Theme.Layout.actionButtonHeight }
    private var radius: CGFloat {
        style == .pill ? 20 : Theme.Radius.button
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                        .frame(width: isCompact ? 10 : 12, height: isCompact ? 10 : 12)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: isCompact ? 11 : 13, weight: .medium))
                }
                Text(title).font(font)
            }
            .foregroundColor(fgColor)
            .padding(.horizontal, hPad)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(VFPressButtonStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.45 : 1.0)
        .vfClickableCursor(!isDisabled && !isLoading)
    }

    private var fgColor: Color {
        switch style {
        case .primary:     return Theme.mainContent
        case .secondary:   return Theme.textPrimary
        case .destructive: return .white
        case .ghost:       return Theme.textSecondary
        case .outline:     return Theme.textOnDark
        case .pill:        return Theme.mainContent
        }
    }

    private var bgColor: Color {
        switch style {
        case .primary:     return Theme.textPrimary
        case .secondary:   return Theme.secondaryButtonFill
        case .destructive: return Theme.danger
        case .ghost:       return .clear
        case .outline:     return Color.white.opacity(0.10)
        case .pill:        return Theme.textPrimary
        }
    }

    private var borderColor: Color {
        switch style {
        case .outline:   return Color.white.opacity(0.55)
        default:         return .clear
        }
    }

    private var borderWidth: CGFloat {
        switch style {
        case .outline: return 1
        default: return 0
        }
    }
}

private struct VFPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - VFBadge ─────────────────────────────────────────────────────────────
//
// Non-interactive label chips. Shared label treatments for plan, status, and
// cautious-access states:
//
//   .plan      "Basic" / "Pro" — warm surface bg, muted text
//   .feature   "Beta" — black fill, white text
//   .discount  "-20%" — danger fill, white text (annual pricing badge)
//   .promo     "2-week pro trial" — lavender fill, violet text
//   .experimental — purple fill, cream text

enum VFBadgeStyle { case plan, feature, discount, promo, experimental }

struct VFBadge: View {
    let label: String
    var style: VFBadgeStyle = .plan

    var body: some View {
        Text(label)
            .font(.vfBadge)
            .foregroundColor(fgColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.xs, style: .continuous)
                    .fill(bgColor)
            )
    }

    private var fgColor: Color {
        switch style {
        case .plan:         return Theme.textSecondary
        case .feature:      return Theme.mainContent
        case .discount:     return .white
        case .promo:        return Theme.promoText
        case .experimental: return Theme.textOnDark
        }
    }

    private var bgColor: Color {
        switch style {
        case .plan:         return Theme.surface
        case .feature:      return Theme.textPrimary
        case .discount:     return Theme.danger
        case .promo:        return Theme.promoTint
        case .experimental: return Theme.interactive
        }
    }
}

// MARK: - VFSectionLabel ──────────────────────────────────────────────────────
//
// The small uppercase group headers in the settings sidebar ("SETTINGS", "ACCOUNT")
// and inside panels to break rows into logical sections.
// Note: text is already uppercased programmatically.

struct VFSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.vfCategoryLabel)
            .foregroundColor(Theme.textTertiary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xs)
    }
}

// MARK: - VFPageHeader ────────────────────────────────────────────────────────
//
// Top of every main content page: left-aligned title + optional right CTA.
// Matches the Dictionary / Snippets / Scratchpad header exactly.
//
// Usage:
//   VFPageHeader(title: "Dictionary", actionTitle: "Add new") { ... }
//   VFPageHeader(title: "Scratchpad", titleBadge: "Beta")

struct VFPageHeader: View {
    let title: String
    var titleBadge: String?         // e.g. "Beta" — shown as dark pill next to title
    var actionTitle: String?        // CTA button label
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.vfPageTitle)
                    .foregroundColor(Theme.textPrimary)
                if let badge = titleBadge {
                    VFBadge(label: badge, style: .feature)
                }
            }
            Spacer()
            if let label = actionTitle, let handler = onAction {
                VFButton(title: label, style: .primary, action: handler)
            }
        }
        .padding(.horizontal, Theme.Layout.contentHPad)
        .padding(.top, Theme.Layout.contentVPad)
        .padding(.bottom, Theme.Space.lg)
    }
}

// MARK: - VFFormRow ───────────────────────────────────────────────────────────
//
// One settings row: label + optional description on the left, any control
// on the right. Covers toggle rows, button rows, and text-value rows —
// the three patterns visible throughout Wispr Flow's settings pages.

struct VFFormRow<Control: View>: View {
    let label: String
    var description: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.vfBody)
                    .foregroundColor(Theme.textPrimary)
                if let desc = description {
                    Text(desc)
                        .font(.vfDescription)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: Theme.Space.lg)
            control()
                .layoutPriority(1)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, 11)
        .frame(minHeight: Theme.Layout.listRowHeight)
    }
}

// MARK: - VFFormSection ───────────────────────────────────────────────────────
//
// A white rounded card wrapping a group of related settings rows.
// Matches the "App settings" / "Sound" / "Notifications" grouped card pattern.

struct VFFormSection<Content: View>: View {
    var header: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let h = header {
                Text(h)
                    .font(.vfCalloutSemibold)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, Theme.Layout.contentHPad)
                    .padding(.top, Theme.Space.xl)
                    .padding(.bottom, Theme.Space.sm)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .padding(.horizontal, Theme.Layout.contentHPad)
        }
    }
}

// MARK: - VFDivider ───────────────────────────────────────────────────────────
//
// Full-width 1px hairline separator between list items.
// Leading-inset matches the content horizontal padding.

struct VFDivider: View {
    var inset: CGFloat = Theme.Layout.contentHPad

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - VFSearchBar ─────────────────────────────────────────────────────────
//
// Inline search field shown in the toolbar area of Dictionary / Snippets.
// Magnifying glass prefix. × clear button appears when text is present.

struct VFSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                TextField(placeholder, text: $text)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textPrimary)
                    .textFieldStyle(.plain)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .vfClickableCursor()
                }
            }
            .frame(height: 32)

            Rectangle()
                .fill(Theme.dividerStrong)
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .frame(minWidth: 120, idealWidth: 160, maxWidth: 220)
    }
}

// MARK: - VFToggle ────────────────────────────────────────────────────────────
//
// Settings toggle row using a custom switch. Native SwiftUI toggles render
// blue on macOS; the reference uses black ON and warm gray OFF.

struct VFSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.switchOnFill : Theme.switchOffFill)
                    .frame(width: 43, height: 25)

                Circle()
                    .fill(isOn ? Theme.switchOnThumbFill : Theme.switchOffThumbFill)
                    .frame(width: 21, height: 21)
                    .padding(.horizontal, 2)
                    .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
            }
            .frame(width: 43, height: 25)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .accessibilityLabel(isOn ? "On" : "Off")
    }
}

struct VFToggle: View {
    let label: String
    var description: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.vfBody)
                    .foregroundColor(Theme.textPrimary)
                if let desc = description {
                    Text(desc)
                        .font(.vfDescription)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.lg)
            VFSwitch(isOn: $isOn)
        }
    }
}

// MARK: - VFDropdown ──────────────────────────────────────────────────────────
//
// Standard select field. Looks like an input, opens a normal option list, and
// uses the violet focus ring only while expanded.

struct VFDropdown<ID: Hashable>: View {
    let options: [(id: ID, label: String)]
    @Binding var selection: ID
    var width: CGFloat? = nil
    @State private var isOpen = false

    private var selectedLabel: String {
        options.first(where: { $0.id == selection })?.label ?? ""
    }

    private var menuWidth: CGFloat {
        width ?? 220
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Text(selectedLabel)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Space.sm)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(width: width, height: Theme.Layout.inputHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .strokeBorder(isOpen ? Theme.interactive : Theme.dividerStrong, lineWidth: isOpen ? 1.5 : 1)
            )
            .shadow(
                color: isOpen ? Theme.interactive.opacity(0.18) : Color.clear,
                radius: isOpen ? 3 : 0,
                x: 0,
                y: 0
            )
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.id) { opt in
                    Button {
                        selection = opt.id
                        isOpen = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(opt.label)
                                .font(.vfBody)
                                .foregroundColor(selection == opt.id ? Theme.interactive : Theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.interactive)
                                .opacity(selection == opt.id ? 1 : 0)
                                .frame(width: 14)
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 36)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                                .fill(selection == opt.id ? Theme.dropdownSelectionFill : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                                .strokeBorder(selection == opt.id ? Theme.dropdownSelectionBorder : Color.clear, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .vfClickableCursor()
                }
            }
            .padding(Theme.Space.sm)
            .frame(width: menuWidth)
            .themedPopover()
        }
    }
}

// MARK: - VFContextMenuItem ───────────────────────────────────────────────────
//
// Item inside a "More options" three-dot popover.
// Matches the "Undo AI edit / Retry transcript / Delete transcript" menu.
// Destructive items render in red.

struct VFContextMenuItem: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                    .foregroundColor(isDestructive ? Theme.danger : Theme.textPrimary)
                Text(label)
                    .font(.vfBody)
                    .foregroundColor(isDestructive ? Theme.danger : Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .vfClickableCursor(!isDisabled)
    }
}

struct VFActionMenuAction {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var isDivider: Bool {
        icon.isEmpty && label.isEmpty
    }

    static func divider() -> VFActionMenuAction {
        VFActionMenuAction(icon: "", label: "") {}
    }
}

struct VFActionMenu: View {
    let actions: [VFActionMenuAction]
    var icon: String = "ellipsis"
    var iconColor: Color = Theme.textSecondary
    var menuWidth: CGFloat = 224
    var buttonSize: CGFloat = 28
    var help: String = "More actions"

    @State private var isOpen = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                isOpen.toggle()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isOpen ? Theme.textPrimary : iconColor)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(isOpen ? Theme.surfaceElevated : Color.clear)
                )
                .overlay(
                    Circle()
                        .strokeBorder(isOpen ? Theme.dividerStrong : Color.clear, lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help(help)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                    if item.isDivider {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                            .padding(.vertical, 4)
                    } else {
                        VFContextMenuItem(
                            icon: item.icon,
                            label: item.label,
                            isDestructive: item.isDestructive,
                            isDisabled: item.isDisabled
                        ) {
                            guard !item.isDisabled else { return }
                            item.action()
                            isOpen = false
                        }
                    }
                }
            }
            .padding(Theme.Space.sm)
            .frame(width: menuWidth)
            .themedPopover()
        }
    }
}

// MARK: - VFConfirmDialog ─────────────────────────────────────────────────────
//
// Small destructive confirmation dialog. Two patterns seen in Wispr Flow:
//   "Delete from personal snippets?" → Cancel + "Yes, delete it"
//   "Are you sure you want to delete this note?" → Cancel + "Yes, delete it"
//
// Always a Cancel (ghost) + primary or destructive button pair.

struct VFConfirmDialog: View {
    let title: String
    var message: String?
    var confirmLabel: String = "Confirm"
    var isDestructive: Bool = true
    var width: CGFloat = Theme.Layout.confirmModalWidth
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack {
                Text(title)
                    .font(.vfBodyMedium)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
            }
            if let msg = message {
                Text(msg)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Space.sm) {
                VFButton(title: "Cancel", style: .ghost, action: onCancel)
                Spacer()
                VFButton(
                    title: confirmLabel,
                    style: isDestructive ? .destructive : .primary,
                    action: onConfirm
                )
            }
        }
        .themedModalCard(padding: Theme.Space.xxl)
        .frame(width: width)
    }
}

// MARK: - VFLoadingOverlay ────────────────────────────────────────────────────
//
// Full-window loading state. Centered white card over a dimmed backdrop.
// App icon → "Loading…" text → animated indeterminate progress bar.
// Matches the Wispr Flow loading modal exactly.

struct VFLoadingOverlay: View {
    var message: String = "Loading…"

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 34) {
                VFBrandLogo(size: 40, variant: .light, cornerRadius: 10)
                Text(message)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Theme.dividerStrong)
                        .frame(height: 3)
                    IndeterminateBar()
                        .frame(height: 3)
                }
                .frame(width: 220, height: 3)
                .clipped()
            }
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.vertical, Theme.Space.xxl)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
            .shadow(color: Theme.Shadow.elevated.color,
                    radius: Theme.Shadow.elevated.radius,
                    x: 0, y: Theme.Shadow.elevated.y)
            .frame(width: Theme.Layout.loadingModalWidth,
                   height: Theme.Layout.loadingModalHeight)
        }
    }
}

private struct IndeterminateBar: View {
    @State private var offset: CGFloat = -80

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.textPrimary)
                .frame(width: 80, height: 3)
                .offset(x: offset)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        offset = geo.size.width + 80
                    }
                }
        }
    }
}

// MARK: - VFMicRowItem ────────────────────────────────────────────────────────
//
// Selectable row inside the Microphone picker modal.
// Selected state: violet left bar + interactiveSoft background + violet border.

struct VFMicRowItem: View {
    let label: String
    var description: String?
    var isSelected: Bool = false
    var levelDots: Int = 0    // 0 = no dots; 1–5 = how many are lit (live level)
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.vfBody)
                        .foregroundColor(Theme.textPrimary)
                    if let desc = description {
                        Text(desc)
                            .font(.vfCaption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                Spacer()
                if levelDots > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Circle()
                                .fill(i < levelDots ? Theme.interactive : Theme.dividerStrong)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .fill(isSelected ? Theme.interactiveSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.interactive.opacity(0.45) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
    }
}

// MARK: - VFStatItem ──────────────────────────────────────────────────────────
//
// One metric in the Home page right-side stats column:
//   952  total words
//    57  wpm
//     1  week
//
// Also used inside the "You've been Flowing. Hard." 2×2 milestone modal.

struct VFStatItem: View {
    let value: String
    let label: String
    var icon: String?    // optional SF Symbol appended after value

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accent)
                }
            }
            Text(label)
                .font(.vfCaption)
                .foregroundColor(Theme.textSecondary)
        }
    }
}

// MARK: - VFHeroBanner ────────────────────────────────────────────────────────
//
// Full-width dark promo card. Supports the editorial headline technique from
// Wispr Flow: mixing bold sans-serif with Georgia italic for emphasis words.
//
//   "Flow spells the way " + italic("you") + " do."
//   "The stuff " + italic("your team") + " shouldn't have to re-type."
//   "Hold down " + hotkey("fn") + " to dictate"
//
// Usage:
//   VFHeroBanner(
//       segments: [.plain("Flow spells the way "), .italic("you"), .plain(" do.")],
//       bodyText: "Flow learns your unique words...",
//       cta: ("See how it works", { }),
//       onDismiss: { }
//   )

enum VFHeroBannerSegment {
    case plain(String)    // bold sans
    case italic(String)   // Georgia serif italic
    case bold(String)     // bold sans (same as plain, alias for clarity)
}

struct VFBlueMeshHeroBackground: View {
    private struct Star: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
    }

    private let stars: [Star] = [
        Star(id: 0, x: 0.34, y: 0.12, size: 1.2, opacity: 0.35),
        Star(id: 1, x: 0.40, y: 0.08, size: 1.4, opacity: 0.28),
        Star(id: 2, x: 0.48, y: 0.16, size: 1.1, opacity: 0.34),
        Star(id: 3, x: 0.58, y: 0.10, size: 1.3, opacity: 0.30),
        Star(id: 4, x: 0.67, y: 0.18, size: 1.1, opacity: 0.26),
        Star(id: 5, x: 0.28, y: 0.28, size: 1.0, opacity: 0.30),
        Star(id: 6, x: 0.36, y: 0.32, size: 1.4, opacity: 0.38),
        Star(id: 7, x: 0.45, y: 0.30, size: 1.1, opacity: 0.32),
        Star(id: 8, x: 0.52, y: 0.36, size: 1.5, opacity: 0.42),
        Star(id: 9, x: 0.62, y: 0.31, size: 1.0, opacity: 0.31),
        Star(id: 10, x: 0.72, y: 0.34, size: 1.2, opacity: 0.28),
        Star(id: 11, x: 0.32, y: 0.48, size: 1.2, opacity: 0.32),
        Star(id: 12, x: 0.41, y: 0.51, size: 1.0, opacity: 0.27),
        Star(id: 13, x: 0.49, y: 0.47, size: 1.5, opacity: 0.40),
        Star(id: 14, x: 0.57, y: 0.53, size: 1.1, opacity: 0.34),
        Star(id: 15, x: 0.65, y: 0.48, size: 1.3, opacity: 0.36),
        Star(id: 16, x: 0.76, y: 0.52, size: 1.0, opacity: 0.24),
        Star(id: 17, x: 0.38, y: 0.66, size: 1.2, opacity: 0.34),
        Star(id: 18, x: 0.46, y: 0.70, size: 1.0, opacity: 0.28),
        Star(id: 19, x: 0.54, y: 0.66, size: 1.6, opacity: 0.45),
        Star(id: 20, x: 0.61, y: 0.72, size: 1.1, opacity: 0.36),
        Star(id: 21, x: 0.70, y: 0.68, size: 1.0, opacity: 0.25),
        Star(id: 22, x: 0.43, y: 0.84, size: 1.2, opacity: 0.30),
        Star(id: 23, x: 0.50, y: 0.88, size: 1.0, opacity: 0.28),
        Star(id: 24, x: 0.59, y: 0.84, size: 1.3, opacity: 0.36),
        Star(id: 25, x: 0.68, y: 0.82, size: 1.1, opacity: 0.24)
    ]

    var body: some View {
        GeometryReader { proxy in
            let falloff = max(proxy.size.width, proxy.size.height)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.006, green: 0.008, blue: 0.025),
                        Color(red: 0.036, green: 0.034, blue: 0.155),
                        Color(red: 0.010, green: 0.010, blue: 0.032)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.425, green: 0.360, blue: 1.000).opacity(0.84),
                        Color(red: 0.220, green: 0.205, blue: 0.680).opacity(0.50),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.54, y: 1.05),
                    startRadius: 8,
                    endRadius: falloff * 0.72
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [
                        Color(red: 0.145, green: 0.180, blue: 0.520).opacity(0.62),
                        Color(red: 0.090, green: 0.105, blue: 0.320).opacity(0.24),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.52, y: 0.28),
                    startRadius: 4,
                    endRadius: falloff * 0.58
                )
                .blendMode(.screen)

                LinearGradient(
                    colors: [
                        Theme.surfaceDark.opacity(0.88),
                        Theme.surfaceDark.opacity(0.18),
                        Theme.surfaceDark.opacity(0.74)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                ForEach(stars) { star in
                    Circle()
                        .fill(Color(red: 0.920, green: 0.930, blue: 1.000).opacity(star.opacity))
                        .frame(width: star.size, height: star.size)
                        .position(
                            x: proxy.size.width * star.x,
                            y: proxy.size.height * star.y
                        )
                }

                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(red: 0.920, green: 0.920, blue: 1.000).opacity(0.58))
                    .position(x: proxy.size.width * 0.46, y: proxy.size.height * 0.62)

                Image(systemName: "sparkle")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(Color(red: 0.920, green: 0.920, blue: 1.000).opacity(0.46))
                    .position(x: proxy.size.width * 0.63, y: proxy.size.height * 0.44)
            }
        }
        .background(Theme.surfaceDark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct VFHeroBanner: View {
    let segments: [VFHeroBannerSegment]
    var bodyText: String?
    var cta: (label: String, action: () -> Void)?
    var onDismiss: (() -> Void)?
    var backgroundImageName: String? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                headlineText
                if let b = bodyText {
                    Text(b)
                        .font(.vfCallout)
                        .foregroundColor(Theme.textOnDarkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let cta {
                    VFButton(
                        title: cta.label,
                        style: .outline,
                        isCompact: true,
                        action: cta.action
                    )
                    .padding(.top, Theme.Space.xs)
                }
            }
            .padding(Theme.Space.xxl)
            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textOnDark.opacity(0.55))
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
                .padding(Theme.Space.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            heroBackground
        }
        .background(Theme.surfaceDark)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(Theme.dividerStrong, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.elevated.color,
                radius: Theme.Shadow.elevated.radius,
                x: 0, y: Theme.Shadow.elevated.y)
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let backgroundImage {
            Image(nsImage: backgroundImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    ZStack {
                        Theme.surfaceDark.opacity(0.34)
                        LinearGradient(
                            colors: [
                                Theme.surfaceDark.opacity(0.68),
                                Theme.surfaceDark.opacity(0.22),
                                Theme.surfaceDark.opacity(0.06)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            VFBlueMeshHeroBackground()
        }
    }

    private var backgroundImage: NSImage? {
        guard let backgroundImageName else { return nil }
        if let namedImage = NSImage(named: backgroundImageName) {
            return namedImage
        }

        let path = backgroundImageName as NSString
        let fileExtension = path.pathExtension.isEmpty ? "jpg" : path.pathExtension
        let resourceName = path.deletingPathExtension
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var headlineText: Text {
        segments.reduce(Text("")) { acc, seg in
            switch seg {
            case .plain(let s), .bold(let s):
                return acc + Text(s)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.textOnDark)
            case .italic(let s):
                return acc + Text(s)
                    .font(.custom("Georgia", size: 22).italic())
                    .foregroundColor(Theme.textOnDark)
            }
        }
    }
}

// HotkeyBadge lives in MainDashboardView.swift (unchanged).
// Use Font.vfKeyLabel / Font.vfKeyLabelSm for any custom keyboard key rendering.
