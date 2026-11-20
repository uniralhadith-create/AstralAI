import SwiftUI
import SafariServices

// MARK: - Standalone Google Antigravity IDE Section (V8.5.0 — Zero PC Required)

/// A complete, standalone Google Antigravity IDE workspace living directly inside
/// Astral AI on iOS. Users sign in with their Google account (OAuth 2.0 PKCE or
/// Google AI Studio API Key), automatically unlock and connect to Google's
/// Gemini 4 & 3.x models according to their Google AI plan (Free / AI Pro /
/// AI Ultra / Enterprise), and build, edit, run, and verify real projects in
/// `/home/astral` without owning a PC.
struct AntigravityIDEView: View {
    private enum IDETab: String, CaseIterable, Identifiable {
        case agent
        case editor
        case terminal
        case account

        var id: String { rawValue }
    }

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var service = AntigravityService.shared
    @ObservedObject private var workspace = WorkspaceStore.shared
    @ObservedObject private var shell = SandboxShell.shared

    @State private var selectedTab: IDETab = .agent
    @Namespace private var tabThumb

    // Sign-in form state
    @State private var apiKeyInput: String = ""
    @State private var emailHintInput: String = ""
    @State private var selectedPlanHint: AntigravityPlanTier? = nil
    @State private var showAdvancedOAuth: Bool = false
    @State private var customClientIDInput: String = ""
    @State private var customClientSecretInput: String = ""

    // Agent Mission Control state
    @State private var missionPrompt: String = ""

    // Code Editor state
    @State private var activeFilePath: String = "Projects/antigravity_app.py"
    @State private var editorContent: String = """
    # Google Antigravity IDE — Astral AI V8.5 (Zero-PC Mobile Workspace)
    import platform, datetime

    print("Antigravity IDE running natively on iOS Ubuntu Base 24.04!")
    print("Timestamp:", datetime.datetime.now().isoformat())
    """
    @State private var editorStatusBanner: String?
    @State private var showNewFileSheet: Bool = false
    @State private var newFileNameDraft: String = ""

    // Terminal state
    @State private var terminalCommandDraft: String = ""

    private var isArabic: Bool {
        language.effectiveCode == "ar"
    }

    var body: some View {
        ZStack {
            AstralTheme.background.ignoresSafeArea()

            if service.isSignedIn {
                ideWorkspaceView
            } else {
                signInOnboardingView
            }
        }
        .onAppear {
            workspace.refresh()
            customClientIDInput = service.customOAuthClientID
            customClientSecretInput = service.customOAuthClientSecret
        }
        .sheet(item: $service.safariAuthItem, onDismiss: {
            service.cancelOAuthIfPending()
        }) { item in
            SafariAuthSheetView(url: item.url)
                .ignoresSafeArea()
        }
        .alert(isArabic ? "ملف جديد في مساحة العمل" : "New Workspace File", isPresented: $showNewFileSheet) {
            TextField("Projects/app.py", text: $newFileNameDraft)
            Button(L("common.cancel", "Shared"), role: .cancel) { newFileNameDraft = "" }
            Button(L("common.create", "Shared")) {
                createNewFile()
            }
        } message: {
            Text(isArabic ? "أدخل مسار الملف النسبي داخل /home/astral" : "Enter the relative file path inside /home/astral")
        }
    }

    // MARK: - 1. Sign-In & Plan Connection View (Zero-PC Onboarding)

    private var signInOnboardingView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero Emblem Card
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.22),
                                        Color(red: 0.56, green: 0.42, blue: 0.98).opacity(0.18),
                                        AstralTheme.orbGreen.opacity(0.16),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                            .frame(width: 78, height: 78)
                            .liquidGlass(in: Circle(), interactive: true)

                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.35, green: 0.68, blue: 1.0),
                                        Color(red: 0.72, green: 0.52, blue: 1.0),
                                        AstralTheme.orbGreen,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                    }

                    Text("Google Antigravity IDE")
                        .font(AstralTheme.display(24, weight: .bold))
                        .foregroundStyle(AstralTheme.textPrimary)

                    Text(L("ag.onboarding.subtitle", "Shared"))
                        .font(AstralTheme.body(13.5))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(AstralTheme.orbGreen)
                            .frame(width: 6.5, height: 6.5)
                        Text(isArabic ? "بدون كمبيوتر · يعمل بالكامل على الآيفون" : "Zero PC Required · 100% On-Device IDE")
                            .font(AstralTheme.mono(10.5).weight(.semibold))
                            .foregroundStyle(AstralTheme.orbGreen)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .liquidCapsule(tint: AstralTheme.orbGreen.opacity(0.12))
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 24, depth: .panel)

                // Method 1: Continue with Google (OAuth 2.0 PKCE)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.35, green: 0.68, blue: 1.0))
                        Text(L("ag.signin.googleTitle", "Shared"))
                            .font(AstralTheme.headline(15))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }

                    Text(L("ag.signin.googleDesc", "Shared"))
                        .font(AstralTheme.body(12))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task {
                            await service.signInWithGoogleOAuth(
                                preferredTier: selectedPlanHint,
                                providerStore: env.providerStore)
                        }
                    } label: {
                        HStack(spacing: 9) {
                            if service.isSigningIn {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            Text(L("ag.signin.googleButton", "Shared"))
                                .font(AstralTheme.headline(14))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                    .disabled(service.isSigningIn)

                    DisclosureGroup(
                        isArabic ? "إعداد OAuth Client ID مخصص (اختياري)" : "Custom OAuth Client ID (Optional)",
                        isExpanded: $showAdvancedOAuth
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("xxxx.apps.googleusercontent.com", text: $customClientIDInput)
                                .font(AstralTheme.mono(12))
                                .textFieldStyle(GlassTextFieldStyle())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: customClientIDInput) { _, newValue in
                                    service.customOAuthClientID = newValue
                                }
                            SecureField("GOCSPX-... (Client Secret)", text: $customClientSecretInput)
                                .font(AstralTheme.mono(12))
                                .textFieldStyle(GlassTextFieldStyle())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: customClientSecretInput) { _, newValue in
                                    service.customOAuthClientSecret = newValue
                                }
                            Text(isArabic
                                 ? "اتركهما فارغين للاستخدام التلقائي عبر Loopback (localhost)، أو أدخل Client ID و Client Secret من Google Cloud."
                                 : "Leave blank for automatic localhost loopback OAuth, or enter your Google Cloud Desktop Client ID & Secret.")
                                .font(AstralTheme.body(11))
                                .foregroundStyle(AstralTheme.moonDust)
                        }
                        .padding(.top, 6)
                    }
                    .font(AstralTheme.body(12))
                    .foregroundStyle(AstralTheme.textSecondary)
                }
                .padding(AstralTheme.Spacings.m)
                .glassCard(cornerRadius: 22, depth: .panel)

                // Method 2: Instant Connect with Google AI Studio Key + Auto Plan Sync
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        AIcon(AstralIcons.key, size: 15, strokeWidth: 2.1, color: AstralTheme.orbGreen)
                        Text(L("ag.signin.apiTitle", "Shared"))
                            .font(AstralTheme.headline(15))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }

                    Text(L("ag.signin.apiDesc", "Shared"))
                        .font(AstralTheme.body(12))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField("AIzaSy...", text: $apiKeyInput)
                        .font(AstralTheme.mono(13))
                        .textFieldStyle(GlassTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField(isArabic ? "بريد جوجل (اختياري للعرض)" : "Google email (optional)", text: $emailHintInput)
                        .font(AstralTheme.body(13))
                        .textFieldStyle(GlassTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    // Optional Plan Selector (Auto-detect by default)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isArabic ? "خطة Google AI (اكتشاف تلقائي أو اختيار يدوي):" : "Google AI Plan (Auto-detect or override):")
                            .font(AstralTheme.mono(10.5).weight(.semibold))
                            .foregroundStyle(AstralTheme.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                planChip(title: isArabic ? "تلقائي" : "Auto", tier: nil)
                                ForEach(AntigravityPlanTier.allCases) { tier in
                                    planChip(title: tier.displayName, tier: tier)
                                }
                            }
                        }
                    }

                    Button {
                        Task {
                            await service.signInWithAPIKey(
                                apiKeyInput,
                                emailHint: emailHintInput,
                                preferredTier: selectedPlanHint,
                                providerStore: env.providerStore)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if service.isSigningIn {
                                ProgressView().controlSize(.small)
                            } else {
                                AIcon(AstralIcons.sparkles, size: 14, strokeWidth: 2.2, color: AstralTheme.actionForeground)
                            }
                            Text(L("ag.signin.connectButton", "Shared"))
                                .font(AstralTheme.headline(14))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isSigningIn)

                    if let url = URL(string: "https://aistudio.google.com/apikey") {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                AIcon(AstralIcons.externalLink, size: 12, strokeWidth: 2.1, color: AstralTheme.accent)
                                Text(isArabic ? "احصل على مفتاح Google AI Studio مجاناً في ثوانٍ" : "Get your free Google AI Studio key in seconds")
                                    .font(AstralTheme.body(12).weight(.medium))
                                    .foregroundStyle(AstralTheme.accent)
                            }
                        }
                    }
                }
                .padding(AstralTheme.Spacings.m)
                .glassCard(cornerRadius: 22, depth: .panel)

                // Error / Status Banner
                if let error = service.lastError {
                    HStack(spacing: 8) {
                        AIcon(AstralIcons.close, size: 13, strokeWidth: 2.3, color: AstralTheme.danger)
                        Text(error)
                            .font(AstralTheme.body(12))
                            .foregroundStyle(AstralTheme.danger)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 16, depth: .panel)
                }

                // Plans & Models Overview Card
                plansComparisonCard
            }
            .padding(AstralTheme.Spacings.m)
        }
    }

    private func planChip(title: String, tier: AntigravityPlanTier?) -> some View {
        let isSelected = selectedPlanHint == tier
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                selectedPlanHint = tier
            }
        } label: {
            Text(title)
                .font(AstralTheme.mono(10.5).weight(.semibold))
                .foregroundStyle(isSelected ? AstralTheme.actionForeground : AstralTheme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? AstralTheme.orbGreen : AstralTheme.actionFill.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var plansComparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isArabic ? "النماذج المتاحة حسب خطة حسابك في جوجل" : "Models Unlocked Automatically by Your Google Plan")
                .font(AstralTheme.headline(14))
                .foregroundStyle(AstralTheme.textPrimary)

            ForEach(AntigravityPlanTier.allCases) { tier in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(tier.accentColor)
                        .frame(width: 9, height: 9)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.localizedName)
                            .font(AstralTheme.headline(12.5))
                            .foregroundStyle(AstralTheme.textPrimary)
                        Text(tier.rateLimitSummary)
                            .font(AstralTheme.body(11.5))
                            .foregroundStyle(AstralTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(AstralTheme.Spacings.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, depth: .panel)
    }

    // MARK: - 2. Full Connected Mobile IDE Workspace

    private var ideWorkspaceView: some View {
        VStack(spacing: 0) {
            // Top Studio Status & Model/Thinking Picker Bar
            ideTopControlBar
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // Segmented Liquid Glass IDE Tabs
            ideTabPicker
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Tab Body
            Group {
                switch selectedTab {
                case .agent:
                    missionControlTab
                case .editor:
                    codeEditorTab
                case .terminal:
                    embeddedTerminalTab
                case .account:
                    accountAndModelsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var ideTopControlBar: some View {
        HStack(spacing: 8) {
            // Plan Tier Pill
            if let acc = service.account {
                HStack(spacing: 5) {
                    Circle()
                        .fill(acc.planTier.accentColor)
                        .frame(width: 7, height: 7)
                    Text(acc.planTier.displayName)
                        .font(AstralTheme.mono(10).weight(.bold))
                        .foregroundStyle(acc.planTier.accentColor)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .liquidCapsule(tint: acc.planTier.accentColor.opacity(0.14))
            }

            // Active Google Model Picker Menu (Filtered by Plan)
            Menu {
                Section(isArabic ? "النماذج المتاحة لخطتك" : "Models Unlocked for Your Plan") {
                    ForEach(service.availableCatalogModels) { model in
                        Button {
                            service.selectModel(model, providerStore: env.providerStore)
                        } label: {
                            if model.id == service.selectedModelID {
                                Label("\(model.name) (\(model.contextWindow))", systemImage: "checkmark")
                            } else {
                                Text("\(model.name) · \(model.contextWindow)")
                            }
                        }
                    }
                }
                Section(isArabic ? "مستوى التفكير (Thinking Level)" : "Thinking Level") {
                    ForEach(AntigravityThinkingLevel.allCases) { level in
                        if level != .extra || service.selectedDescriptor.supportsExtraThinking {
                            Button {
                                service.thinkingLevel = level
                            } label: {
                                if service.thinkingLevel == level {
                                    Label(level.label, systemImage: "checkmark")
                                } else {
                                    Text(level.label)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    AIcon(AstralIcons.sparkles, size: 12, strokeWidth: 2.2, color: AstralTheme.orbGreen)
                    Text(service.selectedDescriptor.name)
                        .font(AstralTheme.headline(12))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)
                    Text("· \(service.thinkingLevel.label)")
                        .font(AstralTheme.mono(10))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .lineLimit(1)
                    AIcon(AstralIcons.chevronsUpDown, size: 10.5, strokeWidth: 2.2, color: AstralTheme.textSecondary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .liquidGlass(in: Capsule(), interactive: true)
            }
        }
    }

    private var ideTabPicker: some View {
        HStack(spacing: 4) {
            ideTabButton(.agent, icon: AstralIcons.sparkles, label: isArabic ? "الوكيل" : "Agent")
            ideTabButton(.editor, icon: AstralIcons.fileCode, label: isArabic ? "المحرر" : "Editor")
            ideTabButton(.terminal, icon: AstralIcons.terminal, label: isArabic ? "الطرفية" : "Shell")
            ideTabButton(.account, icon: AstralIcons.cpu, label: isArabic ? "الخطة" : "Plan")
        }
        .padding(4)
        .liquidGlass(in: Capsule(), tint: AstralTheme.actionFill.opacity(0.05))
    }

    private func ideTabButton(_ tab: IDETab, icon: String, label: String) -> some View {
        let active = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                AIcon(
                    icon,
                    size: 11.5,
                    strokeWidth: 2.2,
                    color: active ? AstralTheme.actionForeground : AstralTheme.textSecondary)
                Text(label)
                    .font(AstralTheme.headline(11.5))
                    .foregroundStyle(active ? AstralTheme.actionForeground : AstralTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                if active {
                    Capsule()
                        .fill(AstralTheme.actionFill)
                        .matchedGeometryEffect(id: "ag-tab-thumb", in: tabThumb)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: Antigravity Mission Control (Agent Manager + Artifacts)

    private var missionControlTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if service.missions.isEmpty {
                        VStack(spacing: 12) {
                            Spacer(minLength: 18)
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(AstralTheme.orbGreen.opacity(0.85))

                            Text(isArabic ? "مركز مهام Google Antigravity" : "Google Antigravity Mission Control")
                                .font(AstralTheme.headline(16))
                                .foregroundStyle(AstralTheme.textPrimary)

                            Text(isArabic
                                 ? "اطلب بناء تطبيق، تعديل ملفات، كتابة سكربت بايثون أو موقع ويب — سيقوم وكيل Antigravity بالتخطيط وكتابة الملفات مباشرة في /home/astral والتحقق منها على Ubuntu."
                                 : "Ask Antigravity to build an app, refactor files, or write scripts — it plans, edits files directly in /home/astral, and verifies them on Ubuntu with zero PC.")
                                .font(AstralTheme.body(12.5))
                                .foregroundStyle(AstralTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            // Quick starter missions
                            VStack(spacing: 8) {
                                quickMissionButton(
                                    isArabic ? "أنشئ صفحة هبوط HTML احترافية في Projects/landing.html" : "Create a modern HTML landing page in Projects/landing.html")
                                quickMissionButton(
                                    isArabic ? "اكتب سكربت بايثون لتحليل البيانات وحفظه في Projects/analyzer.py" : "Write a Python data analyzer script in Projects/analyzer.py")
                            }
                            .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(service.missions) { mission in
                            missionCard(mission)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            // Mission Composer Bar
            VStack(spacing: 8) {
                if let error = service.lastError {
                    Text(error)
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(AstralTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 9) {
                    TextField(
                        isArabic ? "اطلب مهمة برمجية من Antigravity..." : "Give Antigravity a coding mission...",
                        text: $missionPrompt,
                        axis: .vertical)
                        .font(AstralTheme.body(14))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1...4)

                    Button {
                        let prompt = missionPrompt
                        missionPrompt = ""
                        Task {
                            await service.runMission(
                                prompt: prompt,
                                activeFilePath: activeFilePath,
                                activeFileContent: editorContent,
                                providerStore: env.providerStore)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(missionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isRunningMission
                                      ? AstralTheme.actionFill.opacity(0.15)
                                      : AstralTheme.orbGreen)
                                .frame(width: 34, height: 34)
                            if service.isRunningMission {
                                ProgressView().controlSize(.mini).tint(.black)
                            } else {
                                AIcon(AstralIcons.arrowUp, size: 15, strokeWidth: 2.5, color: .black)
                            }
                        }
                    }
                    .disabled(missionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isRunningMission)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func quickMissionButton(_ text: String) -> some View {
        Button {
            missionPrompt = text
        } label: {
            HStack(spacing: 8) {
                AIcon(AstralIcons.sparkles, size: 13, strokeWidth: 2, color: AstralTheme.orbGreen)
                Text(text)
                    .font(AstralTheme.body(12.5))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func missionCard(_ mission: AntigravityMission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(missionStatusColor(mission.status))
                    .frame(width: 8, height: 8)
                Text(mission.modelName)
                    .font(AstralTheme.mono(10.5).weight(.bold))
                    .foregroundStyle(AstralTheme.orbGreen)
                Text("· \(mission.thinkingLevel.label)")
                    .font(AstralTheme.mono(10))
                    .foregroundStyle(AstralTheme.textSecondary)
                Spacer()
                Text(mission.status.rawValue.uppercased())
                    .font(AstralTheme.mono(9.5).weight(.bold))
                    .foregroundStyle(missionStatusColor(mission.status))
            }

            Text(mission.prompt)
                .font(AstralTheme.headline(13.5))
                .foregroundStyle(AstralTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !mission.touchedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mission.touchedFiles, id: \.self) { path in
                            Button {
                                openFileInEditor(path: path)
                            } label: {
                                HStack(spacing: 5) {
                                    AIcon(AstralIcons.fileCode, size: 11, strokeWidth: 2, color: AstralTheme.accent)
                                    Text(path)
                                        .font(AstralTheme.mono(10.5))
                                        .foregroundStyle(AstralTheme.textPrimary)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .liquidCapsule(tint: AstralTheme.accent.opacity(0.14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Artifacts Disclosure
            ForEach(mission.artifacts) { artifact in
                DisclosureGroup {
                    if artifact.kind == .walkthrough {
                        MarkdownView(artifact.content)
                            .padding(.top, 6)
                    } else {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(artifact.content)
                                .font(AstralTheme.mono(11))
                                .foregroundStyle(AstralTheme.textPrimary)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.35)))
                        .padding(.top, 4)
                    }
                } label: {
                    HStack(spacing: 7) {
                        AIcon(
                            artifact.kind == .terminal ? AstralIcons.terminal :
                                (artifact.kind == .codeDiff ? AstralIcons.fileCode : AstralIcons.sparkles),
                            size: 12,
                            strokeWidth: 2.1,
                            color: AstralTheme.orbGreen)
                        Text(artifact.title)
                            .font(AstralTheme.headline(12))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18, depth: .panel)
    }

    private func missionStatusColor(_ status: AntigravityMissionStatus) -> Color {
        switch status {
        case .planning, .coding, .verifying: return AstralTheme.accent
        case .completed: return AstralTheme.orbGreen
        case .failed: return AstralTheme.danger
        }
    }

    // MARK: - Tab 2: Code Editor + Workspace Explorer

    private var codeEditorTab: some View {
        VStack(spacing: 8) {
            // Workspace Files Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        showNewFileSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text(isArabic ? "ملف جديد" : "New File")
                                .font(AstralTheme.mono(10.5).weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AstralTheme.orbGreen))
                    }
                    .buttonStyle(.plain)

                    ForEach(workspace.list(), id: \.relativePath) { file in
                        let isSelected = activeFilePath == file.relativePath
                        Button {
                            openFileInEditor(path: file.relativePath)
                        } label: {
                            Text(file.relativePath)
                                .font(AstralTheme.mono(10.5).weight(isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? AstralTheme.textPrimary : AstralTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .liquidCapsule(tint: isSelected ? AstralTheme.accent.opacity(0.22) : .clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            // Editor Toolbar
            HStack(spacing: 8) {
                Text(activeFilePath)
                    .font(AstralTheme.mono(11.5).weight(.semibold))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Button {
                    saveActiveFile()
                } label: {
                    Text(L("common.save", "Shared"))
                        .font(AstralTheme.mono(11).weight(.semibold))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .liquidCapsule(tint: AstralTheme.actionFill.opacity(0.12))
                }
                .buttonStyle(.plain)

                Button {
                    runActiveFileOnUbuntu()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text(isArabic ? "تشغيل" : "Run")
                            .font(AstralTheme.mono(11).weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AstralTheme.orbGreen))
                }
                .buttonStyle(.plain)

                Button {
                    missionPrompt = isArabic
                        ? "راجع الملف \(activeFilePath) وحسّن الكود وأصلح أي أخطاء فيه"
                        : "Review \(activeFilePath), improve the code quality, and fix any issues"
                    selectedTab = .agent
                } label: {
                    AIcon(AstralIcons.sparkles, size: 13, strokeWidth: 2.2, color: AstralTheme.accent)
                        .frame(width: 28, height: 28)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)

            // Monospace Code Editor
            TextEditor(text: $editorContent)
                .font(AstralTheme.mono(12.5))
                .foregroundStyle(AstralTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.32)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AstralTheme.separator, lineWidth: 1))
                .padding(.horizontal, 12)

            if let banner = editorStatusBanner {
                Text(banner)
                    .font(AstralTheme.mono(10.5))
                    .foregroundStyle(AstralTheme.orbGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        }
        .padding(.bottom, 6)
    }

    private func openFileInEditor(path: String) {
        activeFilePath = path
        if let content = try? workspace.read(path: path) {
            editorContent = content
            editorStatusBanner = nil
        }
        selectedTab = .editor
    }

    private func saveActiveFile() {
        try? workspace.write(path: activeFilePath, content: editorContent)
        workspace.refresh()
        editorStatusBanner = isArabic ? "✓ تم الحفظ في /home/astral/\(activeFilePath)" : "✓ Saved /home/astral/\(activeFilePath)"
    }

    private func createNewFile() {
        let clean = newFileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        activeFilePath = clean
        editorContent = ""
        try? workspace.write(path: clean, content: "")
        workspace.refresh()
        newFileNameDraft = ""
        editorStatusBanner = isArabic ? "✓ تم إنشاء \(clean)" : "✓ Created \(clean)"
    }

    private func runActiveFileOnUbuntu() {
        saveActiveFile()
        let ext = (activeFilePath as NSString).pathExtension.lowercased()
        let cmd: String
        switch ext {
        case "py": cmd = "python3 \(activeFilePath)"
        case "js": cmd = "node \(activeFilePath)"
        case "c": cmd = "gcc \(activeFilePath) -o app.out && bash app.out"
        default: cmd = "bash \(activeFilePath)"
        }
        selectedTab = .terminal
        Task {
            _ = await shell.run(cmd)
        }
    }

    // MARK: - Tab 3: Integrated Ubuntu Base 24.04 Terminal

    private var embeddedTerminalTab: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["ls -la", "git status", "python3 --version", "neofetch", "lsb_release -a"], id: \.self) { cmd in
                        Button {
                            Task { _ = await shell.run(cmd) }
                        } label: {
                            Text(cmd)
                                .font(AstralTheme.mono(10.5))
                                .foregroundStyle(AstralTheme.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .liquidCapsule(tint: AstralTheme.actionFill.opacity(0.08))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("Antigravity Integrated Terminal · Ubuntu Base 24.04.2 LTS (arm64)")
                        .font(AstralTheme.mono(11).weight(.semibold))
                        .foregroundStyle(AstralTheme.orbGreen)

                    ForEach(shell.history) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("root@antigravity:\(shell.cwd)# \(entry.command)")
                                .font(AstralTheme.mono(11.5).weight(.bold))
                                .foregroundStyle(AstralTheme.orbGreen)
                            if !entry.output.isEmpty {
                                Text(entry.output)
                                    .font(AstralTheme.mono(11))
                                    .foregroundStyle(AstralTheme.textPrimary.opacity(0.88))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.45)))
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                Text("$")
                    .font(AstralTheme.mono(14).weight(.bold))
                    .foregroundStyle(AstralTheme.orbGreen)
                TextField("python3 main.py, git status, ls -la...", text: $terminalCommandDraft)
                    .font(AstralTheme.mono(12.5))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(runTerminalDraft)
                Button(isArabic ? "تنفيذ" : "Run", action: runTerminalDraft)
                    .font(AstralTheme.mono(11).weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AstralTheme.orbGreen))
                    .buttonStyle(.plain)
            }
            .padding(10)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
            .padding(12)
        }
    }

    private func runTerminalDraft() {
        let cmd = terminalCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        terminalCommandDraft = ""
        Task { _ = await shell.run(cmd) }
    }

    // MARK: - Tab 4: Google Account, Plan Tier & Auto-Connected Models

    private var accountAndModelsTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let acc = service.account {
                    // Account Summary Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(acc.planTier.accentColor.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                Text(String(acc.displayName.prefix(1)).uppercased())
                                    .font(AstralTheme.headline(18))
                                    .foregroundStyle(acc.planTier.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(acc.displayName)
                                    .font(AstralTheme.headline(15))
                                    .foregroundStyle(AstralTheme.textPrimary)
                                Text(acc.email)
                                    .font(AstralTheme.mono(11))
                                    .foregroundStyle(AstralTheme.textSecondary)
                            }
                            Spacer()
                            Text(acc.planTier.displayName)
                                .font(AstralTheme.mono(10).weight(.bold))
                                .foregroundStyle(acc.planTier.accentColor)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .liquidCapsule(tint: acc.planTier.accentColor.opacity(0.16))
                        }

                        // Quota Progress Bar
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(isArabic ? "الحصة المتبقية (Quota)" : "Remaining Plan Quota")
                                    .font(AstralTheme.body(12))
                                    .foregroundStyle(AstralTheme.textSecondary)
                                Spacer()
                                Text("\(acc.quotaRemainingPercent)%")
                                    .font(AstralTheme.mono(11.5).weight(.bold))
                                    .foregroundStyle(AstralTheme.orbGreen)
                            }
                            GlassProgressView(progress: Double(acc.quotaRemainingPercent) / 100.0, height: 6)
                        }

                        // Plan Tier Switcher
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isArabic ? "تحديث خطة Google AI:" : "Active Google AI Plan Tier:")
                                .font(AstralTheme.mono(10.5).weight(.semibold))
                                .foregroundStyle(AstralTheme.textSecondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    ForEach(AntigravityPlanTier.allCases) { tier in
                                        let active = acc.planTier == tier
                                        Button {
                                            service.updatePlanTier(tier, providerStore: env.providerStore)
                                        } label: {
                                            Text(tier.displayName)
                                                .font(AstralTheme.mono(10.5).weight(.bold))
                                                .foregroundStyle(active ? .black : AstralTheme.textPrimary)
                                                .padding(.horizontal, 11)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule().fill(active ? tier.accentColor : AstralTheme.actionFill.opacity(0.08)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                Task { await service.refreshDiscoveredModels(providerStore: env.providerStore) }
                            } label: {
                                HStack(spacing: 6) {
                                    if service.isSyncingModels {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        AIcon(AstralIcons.refresh, size: 12, strokeWidth: 2.2, color: AstralTheme.textPrimary)
                                    }
                                    Text(isArabic ? "مزامنة نماذج جوجل" : "Sync Google Models")
                                        .font(AstralTheme.headline(12))
                                        .foregroundStyle(AstralTheme.textPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                service.signOut(providerStore: env.providerStore)
                            } label: {
                                Text(isArabic ? "تسجيل الخروج" : "Sign Out")
                                    .font(AstralTheme.headline(12))
                                    .foregroundStyle(AstralTheme.danger)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }

                        if let status = service.statusMessage {
                            Text(status)
                                .font(AstralTheme.mono(10.5))
                                .foregroundStyle(AstralTheme.orbGreen)
                        }
                    }
                    .padding(AstralTheme.Spacings.m)
                    .glassCard(cornerRadius: 22, depth: .panel)

                    // Models List Grouped by Availability
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isArabic ? "نماذج Google Antigravity المتصلة تلقائياً" : "Auto-Connected Google Antigravity Models")
                            .font(AstralTheme.headline(14))
                            .foregroundStyle(AstralTheme.textPrimary)

                        ForEach(AntigravityModelCatalog.all) { model in
                            let unlocked = model.isUnlocked(for: acc.planTier)
                            let selected = service.selectedModelID == model.id
                            Button {
                                if unlocked {
                                    service.selectModel(model, providerStore: env.providerStore)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(model.name)
                                                .font(AstralTheme.headline(13))
                                                .foregroundStyle(unlocked ? AstralTheme.textPrimary : AstralTheme.textSecondary)
                                            if let badge = model.badge {
                                                Text(badge)
                                                    .font(AstralTheme.mono(9).weight(.bold))
                                                    .foregroundStyle(model.minimumTier.accentColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(model.minimumTier.accentColor.opacity(0.14)))
                                            }
                                        }
                                        Text("\(model.localizedSubtitle) · \(model.contextWindow)")
                                            .font(AstralTheme.body(11.5))
                                            .foregroundStyle(AstralTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if selected {
                                        AIcon(AstralIcons.checkCircle, size: 17, strokeWidth: 2.2, color: AstralTheme.orbGreen)
                                    } else if !unlocked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AstralTheme.moonDust)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selected ? AstralTheme.orbGreen.opacity(0.10) : AstralTheme.actionFill.opacity(0.03)))
                                .opacity(unlocked ? 1.0 : 0.55)
                            }
                            .buttonStyle(.plain)
                            .disabled(!unlocked)
                        }
                    }
                    .padding(AstralTheme.Spacings.m)
                    .glassCard(cornerRadius: 22, depth: .panel)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Native SFSafariViewController Sheet for RFC 8252 Loopback OAuth

private struct SafariAuthSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .cancel
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
