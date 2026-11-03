import SwiftUI

// MARK: - App sections

/// The main app sections. V2 removes the bottom tab bar entirely — the chat
/// is the always-visible root experience and every other section is
/// presented as a sheet (the Apple chat-first pattern used by Messages,
/// Mail and the ChatGPT app). The enum survives as the routing identity
/// shared by the drawer, deep links and the composer.
public enum AppTab: String, CaseIterable, Identifiable {
    case chat
    case skills
    case browser
    case files
    case settings

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .chat: return "message.fill"
        case .skills: return "puzzlepiece.extension.fill"
        case .browser: return "safari.fill"
        case .files: return "folder.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// Filled variant used by the drawer's capsule shortcut tiles — richer,
    /// more modern glyphs than the outline set.
    public var filledIcon: String {
        switch self {
        case .chat: return "plus.bubble.fill"
        case .skills: return "puzzlepiece.extension.fill"
        case .browser: return "safari.fill"
        case .files: return "folder.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// Outline variant used inside the drawer (quieter than filled glyphs).
    public var outlineIcon: String {
        switch self {
        case .chat: return "message"
        case .skills: return "puzzlepiece.extension"
        case .browser: return "safari"
        case .files: return "folder"
        case .settings: return "gearshape"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .chat: return L("tab.chat", "Shared")
        case .skills: return L("tab.skills", "Shared")
        case .browser: return L("tab.browser", "Shared")
        case .files: return L("tab.files", "Shared")
        case .settings: return L("tab.settings", "Shared")
        }
    }
}

// MARK: - Section sheet

/// Wraps a feature section in an Apple-style sheet: navigation bar with a
/// large title and a Done button. Presented over the persistent chat.
public struct SectionSheet: View {
    let section: AppTab
    var onDismiss: () -> Void

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager

    public init(section: AppTab, onDismiss: @escaping () -> Void) {
        self.section = section
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .chat:
                    ChatView()
                case .skills:
                    SkillsView()
                case .browser:
                    BrowserView()
                case .files:
                    FilesView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // The V3.5 redesigned back control — a glass orb with a
                    // custom return arrow (mirrors in RTL).
                    HStack(spacing: 10) {
                        GlassBackButton {
                            onDismiss()
                        }

                        Text(section.localizedTitle)
                            .font(AstralTheme.headline(17))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Text(L("common.done", "Shared"))
                            .font(AstralTheme.headline(15))
                            .foregroundStyle(AstralTheme.accent)
                    }
                    .accessibilityLabel(Text(L("common.done", "Shared")))
                }
            }
        }
        .environment(\.layoutDirection, language.layoutDirection)
        .environment(\.locale, Locale(identifier: language.effectiveCode))
        .preferredColorScheme(nil)
        .presentationDragIndicator(.visible)
    }
}
