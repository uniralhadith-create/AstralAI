import SwiftUI

// MARK: - About (V5 Liquid Glass)

struct AboutView: View {
    @EnvironmentObject private var language: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "5.0.0"
    }

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: AstralTheme.Spacings.m) {
                appCard
                developerCard
                technologyCard

                Text(L("about.copyright", "Onboarding"))
                    .font(.footnote)
                    .foregroundStyle(AstralTheme.moonDust)
                    .multilineTextAlignment(.center)
                    .padding(.top, AstralTheme.Spacings.xs)
            }
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.vertical, AstralTheme.Spacings.l)
        }
        .background(AstralTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                GlassBackButton {
                    dismiss()
                }
            }
        }
    }

    // MARK: App card

    private var appCard: some View {
        VStack(spacing: AstralTheme.Spacings.s) {
            ZStack {
                Circle()
                    .fill(AstralTheme.actionFill.opacity(0.06))
                    .frame(width: 88, height: 88)
                    .liquidGlass(in: Circle(), interactive: true)
                Image("AstralMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 62, height: 62)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 14, y: 6)

            Text(AppIdentity.appName)
                .font(AstralTheme.display(26, weight: .semibold))
                .foregroundStyle(AstralTheme.textPrimary)

            Text(String(format: L("about.version", "Onboarding"), version))
                .font(AstralTheme.mono(12).weight(.semibold))
                .foregroundStyle(AstralTheme.orbGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 3.5)
                .liquidCapsule(tint: AstralTheme.orbGreen.opacity(0.14))

            Text(L("about.tagline", "Onboarding"))
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AstralTheme.Spacings.l)
        .glassCard(depth: .panel)
    }

    // MARK: Developer card

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            SectionHeader(icon: "person.crop.circle", "about.developer", table: "Onboarding")

            VStack(alignment: .leading, spacing: 4) {
                Text(AppIdentity.developer)
                    .font(AstralTheme.headline(17))
                    .foregroundStyle(AstralTheme.textPrimary)

                Text(L("about.role", "Onboarding"))
                    .font(AstralTheme.body(13))
                    .foregroundStyle(AstralTheme.moonDust)
            }

            if let instagram = URL(string: AppIdentity.instagramURL) {
                Link(destination: instagram) {
                    HStack(spacing: 8) {
                        AIcon(AstralIcons.externalLink, size: 13, strokeWidth: 2.2, color: AstralTheme.textPrimary)
                        Text("@astral.tariq")
                            .font(AstralTheme.headline(13))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassPill(tint: AstralTheme.auroraMagenta)
                }
            }
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(depth: .panel)
    }

    // MARK: Technology card

    private var technologyCard: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            SectionHeader(icon: "sparkles", "about.technology", table: "Onboarding")

            VStack(alignment: .leading, spacing: 10) {
                techRow(icon: AstralIcons.sparkles, textKey: "about.tech.design")
                techRow(icon: AstralIcons.zap, textKey: "about.tech.agents")
                techRow(icon: AstralIcons.shield, textKey: "about.tech.keychain")
            }
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(depth: .panel)
    }

    private func techRow(icon: String, textKey: String) -> some View {
        HStack(spacing: 10) {
            AIcon(icon, size: 14, strokeWidth: 2.2, color: AstralTheme.auroraCyan)

            Text(L(textKey, "Onboarding"))
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textPrimary)

            Spacer(minLength: 0)
        }
    }
}
