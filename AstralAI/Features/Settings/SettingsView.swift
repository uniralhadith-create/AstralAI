import SwiftUI

// MARK: - Settings (V5.0.0 — iOS 27 Liquid Glass Control Center)

/// Settings V5: preserves the signature monochrome Astral theme while
/// organizing all sections into sleek iOS 27 Liquid Glass V5 cards with
/// custom Lucide vector icons, live status pills, and smooth animations.
struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @EnvironmentObject private var providerStore: ProviderStore
    @ObservedObject private var modeController = ComputerModeController.shared
    @ObservedObject private var cloud = E2BComputer.shared

    @State private var selectedLanguage: AppLanguage = .system
    @State private var showingAddProvider = false
    @State private var editingProvider: ProviderConfig?
    @State private var pendingDelete: ProviderConfig?
    @State private var showSavedFeedback = false
    @State private var feedbackDismissTask: Task<Void, Never>?

    @AppStorage("astral.allowParallel") private var allowParallel = true
    @AppStorage("astral.autoNotify") private var autoNotify = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AstralTheme.Spacings.m) {
                    heroHeaderCard
                    languageSection
                    providersSection
                    computerSection
                    actionButtonSection
                    behaviorSection
                    aboutSection
                }
                .padding(.horizontal, AstralTheme.Spacings.m)
                .padding(.vertical, AstralTheme.Spacings.m)
            }
            .background(AstralTheme.background.ignoresSafeArea())
            .overlay(alignment: .top) {
                savedFeedbackPill
            }
            .navigationTitle(L("settings.title", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                L("settings.deleteProvider", "Settings"),
                isPresented: deleteDialogBinding,
                titleVisibility: .visible
            ) {
                Button(L("common.delete", "Shared"), role: .destructive) {
                    if let target = pendingDelete {
                        providerStore.delete(target.id)
                    }
                    pendingDelete = nil
                }
                Button(L("settings.cancel", "Settings"), role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                Text(L("settings.deleteProviderHint", "Settings"))
            }
        }
        .onAppear {
            selectedLanguage = language.language
        }
        .onChange(of: selectedLanguage) { _, newValue in
            language.language = newValue
        }
        .sheet(isPresented: $showingAddProvider) {
            addProviderSheet
        }
        .sheet(item: $editingProvider) { provider in
            editProviderSheet(provider)
        }
    }

    // MARK: - Hero summary card

    private var heroHeaderCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(AstralTheme.actionFill.opacity(0.08))
                    .frame(width: 48, height: 48)
                    .liquidGlass(in: Circle(), interactive: true)
                Image("AstralMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(AppIdentity.appName)
                        .font(AstralTheme.headline(16))
                        .foregroundStyle(AstralTheme.textPrimary)
                    Text(L("app.versionBadge", "Shared"))
                        .font(AstralTheme.mono(9.5).weight(.semibold))
                        .foregroundStyle(AstralTheme.orbGreen)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AstralTheme.orbGreen.opacity(0.14)))
                }
                Text("astra-os 5.0 · iOS 27 Liquid Glass · AI Agent")
                    .font(AstralTheme.mono(10.5))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            SectionHeader(icon: "globe", "settings.language", table: "Settings")

            Picker(L("settings.language", "Settings"), selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.displayName)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    // MARK: - Providers

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            SectionHeader(icon: "cpu", "settings.providers", table: "Settings")

            if providerStore.providers.isEmpty {
                Text(L("settings.noProvidersHint", "Settings"))
                    .font(AstralTheme.body(13))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(providerStore.providers) { provider in
                        providerRow(provider)
                    }
                }
            }

            Button {
                showingAddProvider = true
            } label: {
                HStack(spacing: 8) {
                    AIcon(
                        AstralIcons.plus,
                        size: 15,
                        strokeWidth: 2.4,
                        color: AstralTheme.actionForeground)
                    Text(L("settings.addProvider", "Settings"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .padding(.top, 4)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    private func providerRow(_ provider: ProviderConfig) -> some View {
        let isActive = providerStore.activeProviderID == provider.id
        return HStack(spacing: AstralTheme.Spacings.s) {
            Button {
                providerStore.setActive(provider.id)
            } label: {
                HStack(spacing: AstralTheme.Spacings.s) {
                    ZStack {
                        Circle()
                            .fill(isActive ? AstralTheme.orbGreen : Color.clear)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isActive ? AstralTheme.orbGreen : AstralTheme.moonDust.opacity(0.6),
                                        lineWidth: 1.6))
                        if isActive {
                            AIcon(AstralIcons.check, size: 11, strokeWidth: 3.0, color: .black)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name.isEmpty ? L("settings.untitled", "Settings") : provider.name)
                            .font(AstralTheme.headline(14.5))
                            .foregroundStyle(AstralTheme.textPrimary)
                        Text(provider.baseURL)
                            .font(AstralTheme.body(11))
                            .foregroundStyle(AstralTheme.moonDust)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !provider.mainModel.isEmpty {
                            Text(provider.mainModel)
                                .font(AstralTheme.mono(11))
                                .foregroundStyle(AstralTheme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                editingProvider = provider
            } label: {
                AIcon(
                    AstralIcons.settings,
                    size: 15,
                    strokeWidth: 2.1,
                    color: AstralTheme.accent)
                    .frame(width: 32, height: 32)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L("settings.editProvider", "Settings")))

            Button(role: .destructive) {
                pendingDelete = provider
            } label: {
                AIcon(
                    AstralIcons.trash,
                    size: 14,
                    strokeWidth: 2.0,
                    color: AstralTheme.danger.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L("common.delete", "Shared")))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 15, style: .continuous),
            tint: isActive ? AstralTheme.orbGreen.opacity(0.07) : AstralTheme.actionFill.opacity(0.03),
            interactive: true)
    }

    // MARK: - Computer (Local astra-os 5.0 + Cloud Ubuntu)

    private var computerSection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            HStack {
                HStack(spacing: AstralTheme.Spacings.s) {
                    ZStack {
                        Circle()
                            .fill(AstralTheme.actionFill)
                            .frame(width: 25, height: 25)
                        AstralComputerIcon(
                            size: 13.5,
                            color: AstralTheme.actionForeground,
                            accentColor: AstralTheme.orbGreen,
                            isActive: true)
                    }
                    Text(L("settings.cloudComputer", "Settings"))
                        .font(AstralTheme.headline(15))
                        .foregroundStyle(AstralTheme.textPrimary)
                }
                Spacer()
                Text(modeController.prefersCloud ? L("computer.modeCloud", "Chat") : L("computer.modeLocal", "Chat"))
                    .font(AstralTheme.mono(10).weight(.semibold))
                    .foregroundStyle(AstralTheme.orbGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .liquidCapsule(tint: AstralTheme.orbGreen.opacity(0.14))
            }

            NavigationLink {
                CloudComputerSetupView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AstralTheme.orbGreen.opacity(0.14))
                            .frame(width: 38, height: 38)
                        AstralComputerIcon(
                            size: 20,
                            color: AstralTheme.textPrimary,
                            accentColor: AstralTheme.orbGreen,
                            isActive: true)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(cloud.isConfigured
                            ? L("settings.cloudConnected", "Settings")
                            : L("settings.cloudSetup", "Settings"))
                            .font(AstralTheme.headline(14))
                            .foregroundStyle(AstralTheme.textPrimary)
                        Text(cloudStatusText)
                            .font(AstralTheme.mono(11))
                            .foregroundStyle(AstralTheme.textSecondary)
                    }

                    Spacer(minLength: 6)

                    AIcon(
                        AstralIcons.chevronForward,
                        size: 14,
                        strokeWidth: 2.2,
                        color: AstralTheme.textSecondary)
                        .scaleEffect(x: language.layoutDirection == .rightToLeft ? -1 : 1, y: 1)
                }
                .padding(12)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)

            Text(L("settings.cloudComputerHint", "Settings"))
                .font(AstralTheme.body(11.5))
                .foregroundStyle(AstralTheme.moonDust)
                .padding(.top, 2)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    private var cloudStatusText: String {
        switch cloud.status {
        case .off: return L("settings.cloudOff", "Settings")
        case .starting: return L("settings.cloudStarting", "Settings")
        case .running: return L("settings.cloudRunning", "Settings")
        case .failed: return L("settings.cloudFailed", "Settings")
        }
    }

    // MARK: - Action Button

    private var actionButtonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AIcon(
                    AstralIcons.zap,
                    size: 17,
                    strokeWidth: 2.2,
                    color: AstralTheme.orbGreen)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AstralTheme.orbGreen.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("settings.actionButton", "Settings"))
                        .font(AstralTheme.headline(15))
                        .foregroundStyle(AstralTheme.textPrimary)
                    Text(L("settings.actionButtonHint", "Settings"))
                        .font(AstralTheme.body(11))
                        .foregroundStyle(AstralTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                actionButtonStep("1", L("settings.actionButton.step1", "Settings"))
                actionButtonStep("2", L("settings.actionButton.step2", "Settings"))
                actionButtonStep("3", L("settings.actionButton.step3", "Settings"))
            }

            Button {
                openQuickLaunchPreview()
            } label: {
                HStack(spacing: 8) {
                    AIcon(
                        AstralIcons.sparkles,
                        size: 14,
                        strokeWidth: 2.2,
                        color: AstralTheme.actionForeground)
                    Text(L("settings.actionButton.try", "Settings"))
                        .font(AstralTheme.headline(14))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .padding(.top, 2)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    private func actionButtonStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(AstralTheme.mono(11).weight(.bold))
                .foregroundStyle(AstralTheme.actionForeground)
                .frame(width: 20, height: 20)
                .background(Circle().fill(AstralTheme.actionFill))
            Text(text)
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openQuickLaunchPreview() {
        env.presentedSection = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            env.showQuickLaunch = true
        }
    }

    // MARK: - Agent behavior

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            HStack(spacing: AstralTheme.Spacings.s) {
                ZStack {
                    Circle()
                        .fill(AstralTheme.actionFill)
                        .frame(width: 25, height: 25)
                    AIcon(AstralIcons.brain, size: 13, strokeWidth: 2.2, color: AstralTheme.actionForeground)
                }
                Text(L("settings.agentBehavior", "Settings"))
                    .font(AstralTheme.headline(15))
                    .foregroundStyle(AstralTheme.textPrimary)
                Spacer()
            }

            VStack(spacing: 10) {
                Toggle(isOn: $allowParallel) {
                    HStack(spacing: 8) {
                        AIcon(AstralIcons.users, size: 14, strokeWidth: 2.1, color: AstralTheme.textSecondary)
                        Text(L("settings.allowParallel", "Settings"))
                            .font(AstralTheme.body(14))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                }
                .tint(AstralTheme.accent)

                Divider().overlay(AstralTheme.separator)

                Toggle(isOn: $autoNotify) {
                    HStack(spacing: 8) {
                        AIcon(AstralIcons.zap, size: 14, strokeWidth: 2.1, color: AstralTheme.textSecondary)
                        Text(L("settings.autoNotify", "Settings"))
                            .font(AstralTheme.body(14))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                }
                .tint(AstralTheme.accent)
            }
            .padding(12)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    // MARK: - About

    private var aboutSection: some View {
        NavigationLink {
            AboutView()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AstralTheme.actionFill.opacity(0.10))
                        .frame(width: 30, height: 30)
                    AIcon(AstralIcons.sparkles, size: 14, strokeWidth: 2.1, color: AstralTheme.textPrimary)
                }
                Text(L("settings.about", "Settings"))
                    .font(AstralTheme.headline(15))
                    .foregroundStyle(AstralTheme.textPrimary)
                Spacer()
                AIcon(
                    AstralIcons.chevronForward,
                    size: 14,
                    strokeWidth: 2.2,
                    color: AstralTheme.textSecondary)
                    .scaleEffect(x: language.layoutDirection == .rightToLeft ? -1 : 1, y: 1)
            }
            .padding(AstralTheme.Spacings.m)
            .glassCard(cornerRadius: 22, depth: .panel)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sheets

    private var addProviderSheet: some View {
        ProviderEditView(
            config: ProviderConfig(name: "", baseURL: ""),
            isNew: true
        ) { newProvider in
            providerStore.add(newProvider)
            providerStore.setActive(newProvider.id)
            confirmProviderSaved()
        }
        .settingsSheetEnvironment(env: env, language: language)
    }

    private func editProviderSheet(_ provider: ProviderConfig) -> some View {
        ProviderEditView(config: provider, isNew: false) { updated in
            providerStore.update(updated)
            confirmProviderSaved()
        }
        .settingsSheetEnvironment(env: env, language: language)
    }

    // MARK: - Save feedback

    private var savedFeedbackPill: some View {
        Group {
            if showSavedFeedback {
                HStack(spacing: 6) {
                    AIcon(AstralIcons.checkCircle, size: 14, strokeWidth: 2.3, color: AstralTheme.success)
                    Text(L("settings.providerSaved", "Settings"))
                        .font(AstralTheme.headline(13))
                        .foregroundStyle(AstralTheme.success)
                }
                .padding(.horizontal, AstralTheme.Spacings.l)
                .padding(.vertical, AstralTheme.Spacings.s)
                .liquidCapsule()
                .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
                .padding(.top, AstralTheme.Spacings.xxs)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private func confirmProviderSaved() {
        feedbackDismissTask?.cancel()
        withAnimation(.smooth(duration: 0.3)) {
            showSavedFeedback = true
        }
        feedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                showSavedFeedback = false
            }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { shown in
                if !shown { pendingDelete = nil }
            })
    }
}

// MARK: - Sheet environment helper

extension View {
    func settingsSheetEnvironment(
        env: AppEnvironment,
        language: LocalizationManager
    ) -> some View {
        self
            .environmentObject(env)
            .environmentObject(language)
            .environment(\.layoutDirection, language.layoutDirection)
            .environment(\.locale, Locale(identifier: language.effectiveCode))
    }
}
