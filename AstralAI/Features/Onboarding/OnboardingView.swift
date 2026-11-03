import SwiftUI
import UserNotifications

// MARK: - Onboarding (V5 System-Adaptive iOS 27 Liquid Glass)

/// First-launch onboarding: welcome, language selection and provider setup.
/// The completion closure reports whether the user wants to jump straight
/// into provider Settings.
struct OnboardingView: View {
    var onFinished: (Bool) -> Void

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager

    @State private var page = 0
    @State private var spinning = false

    var body: some View {
        ZStack {
            AstralTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage
                        .tag(0)
                    languagePage
                        .tag(1)
                    connectPage
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                bottomBar
            }
        }
    }

    // MARK: Page 1 — Welcome

    private var welcomePage: some View {
        VStack(spacing: AstralTheme.Spacings.l) {
            ZStack {
                // Slowly orbiting ring with a satellite dot around the mark.
                ZStack {
                    Circle()
                        .stroke(AstralTheme.auroraCyan.opacity(0.45), lineWidth: 1.2)
                    Circle()
                        .fill(AstralTheme.auroraCyan)
                        .frame(width: 6, height: 6)
                        .offset(x: 82)
                }
                .frame(width: 164, height: 164)
                .rotationEffect(.degrees(spinning ? 360 : 0))

                ZStack {
                    Circle()
                        .frame(width: 140, height: 140)
                        .liquidGlass(in: Circle(), interactive: true)
                    Image("AstralMark")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 108, height: 108)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }

            AstralWordmark(fontSize: 34)

            Text(L("onboarding.welcomeTitle", "Onboarding"))
                .font(AstralTheme.title(22))
                .foregroundStyle(AstralTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(L("onboarding.welcomeBody", "Onboarding"))
                .font(AstralTheme.body(14))
                .foregroundStyle(AstralTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.horizontal, AstralTheme.Spacings.m)
    }

    // MARK: Page 2 — Language

    private var languagePage: some View {
        VStack(spacing: AstralTheme.Spacings.l) {
            Text(L("onboarding.languageTitle", "Onboarding"))
                .font(AstralTheme.title(22))
                .foregroundStyle(AstralTheme.textPrimary)

            Text(L("onboarding.languageBody", "Onboarding"))
                .font(AstralTheme.body(14))
                .foregroundStyle(AstralTheme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: AstralTheme.Spacings.s) {
                ForEach(AppLanguage.allCases) { option in
                    languageCard(option)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func languageCard(_ option: AppLanguage) -> some View {
        let selected = env.language.language == option
        return Button {
            env.language.language = option
        } label: {
            HStack(spacing: AstralTheme.Spacings.s) {
                AIcon(
                    AstralIcons.globe,
                    size: 16,
                    strokeWidth: 2.1,
                    color: AstralTheme.auroraCyan)

                Text(option.displayName)
                    .font(AstralTheme.headline(16))
                    .foregroundStyle(AstralTheme.textPrimary)

                Spacer(minLength: 0)

                if selected {
                    AIcon(
                        AstralIcons.checkCircle,
                        size: 18,
                        strokeWidth: 2.3,
                        color: AstralTheme.auroraCyan)
                }
            }
            .padding(AstralTheme.Spacings.m)
            .glassCard(
                cornerRadius: AstralTheme.Radius.medium,
                depth: .raised,
                tint: selected ? AstralTheme.auroraCyan : .white)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: selected)
    }

    // MARK: Page 3 — Connect a provider

    private var connectPage: some View {
        VStack(spacing: AstralTheme.Spacings.l) {
            ZStack {
                Circle()
                    .frame(width: 76, height: 76)
                    .liquidGlass(in: Circle(), interactive: true)
                AIcon(
                    AstralIcons.key,
                    size: 32,
                    strokeWidth: 1.9,
                    color: AstralTheme.auroraCyan)
            }

            Text(L("onboarding.connectTitle", "Onboarding"))
                .font(AstralTheme.title(22))
                .foregroundStyle(AstralTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(L("onboarding.connectBody", "Onboarding"))
                .font(AstralTheme.body(14))
                .foregroundStyle(AstralTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: AstralTheme.Spacings.s) {
                Button {
                    finish(openSettings: true)
                } label: {
                    HStack(spacing: 8) {
                        AIcon(
                            AstralIcons.plug,
                            size: 15,
                            strokeWidth: 2.3,
                            color: AstralTheme.actionForeground)
                        Text(L("onboarding.setupProvider", "Onboarding"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AuroraButtonStyle())

                Button {
                    finish(openSettings: false)
                } label: {
                    Text(L("onboarding.skip", "Onboarding"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            Spacer()
            if page < 2 {
                Button {
                    withAnimation(.smooth(duration: 0.4)) {
                        page += 1
                    }
                } label: {
                    Text(L("onboarding.continue", "Onboarding"))
                }
                .buttonStyle(AuroraButtonStyle())
            }
            Spacer()
        }
        .frame(height: 72)
        .padding(.horizontal, 24)
    }

    // MARK: Finish

    /// Requests notification permission (best effort) and completes
    /// onboarding.
    private func finish(openSettings: Bool) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            onFinished(openSettings)
        }
    }
}
