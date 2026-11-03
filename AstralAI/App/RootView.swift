import SwiftUI

/// V2 root shell — the Apple chat-first architecture:
///
/// - The chat experience is the app. It fills the screen permanently and
///   never sits above a bottom bar (the bar is gone entirely).
/// - Every other section (Skills, Browser, Files, Settings) is presented
///   as a sheet from the drawer — the pattern used by Messages, Mail and
///   the ChatGPT app, and the one Apple's HIG actually prescribes for
///   communication-centric apps.
/// - Onboarding and deep-link routing stay as they were.
struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "astral.hasOnboarded")

    var body: some View {
        ZStack {
            AstralTheme.background.ignoresSafeArea()

            // The one permanent surface: chat.
            ChatView()
        }
        // Sections ride above the chat as Apple-style sheets.
        .sheet(item: $env.presentedSection) { section in
            SectionSheet(section: section) {
                env.presentedSection = nil
            }
            .environmentObject(env)
            .environmentObject(language)
            .environment(\.layoutDirection, language.layoutDirection)
            .environment(\.locale, Locale(identifier: language.effectiveCode))
        }
        // The astra-os terminal — the user's window into the agent's
        // work environment.
        .sheet(isPresented: $env.showTerminal) {
            TerminalView()
                .environmentObject(env)
                .environmentObject(language)
                .environment(\.layoutDirection, language.layoutDirection)
        }
        // V4.6.0 Quick Launch — the Action Button overlay (astral://quick).
        .fullScreenCover(isPresented: $env.showQuickLaunch) {
            QuickLaunchView()
                .environmentObject(env)
                .environmentObject(language)
                .environment(\.layoutDirection, language.layoutDirection)
                .environment(\.locale, Locale(identifier: language.effectiveCode))
        }
        .onOpenURL { url in
            env.handleDeepLink(url)
        }
        .onChange(of: scenePhase) { _, newPhase in
            env.scenePhaseChanged(newPhase)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { openSettings in
                UserDefaults.standard.set(true, forKey: "astral.hasOnboarded")
                showOnboarding = false
                if openSettings {
                    env.presentedSection = .settings
                }
            }
            .environmentObject(env)
            .environmentObject(language)
            .environment(\.layoutDirection, language.layoutDirection)
            .environment(\.locale, Locale(identifier: language.effectiveCode))
        }
    }
}
