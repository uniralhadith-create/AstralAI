import SwiftUI
import SafariServices
import UIKit

// MARK: - Standalone & Embedded Google Antigravity IDE View (V8.5.0)

/// Refined, balanced Liquid Glass Google Antigravity IDE & Chatbot workspace.
/// Works both as a standalone section AND embedded directly inside the main
/// `ChatView` when the user selects the `IDE` mode in the 3-mode switcher.
struct AntigravityIDEView: View {
    var embeddedInChat: Bool = false

    private enum IDETab: String, CaseIterable, Identifiable {
        case assistant
        case editor
        case terminal
        case account

        var id: String { rawValue }
    }

    private enum SignInTab: String, CaseIterable, Identifiable {
        case googleAccount
        case iosOAuth

        var id: String { rawValue }
    }

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var service = AntigravityService.shared
    @ObservedObject private var workspace = WorkspaceStore.shared
    @ObservedObject private var shell = SandboxShell.shared

    @State private var selectedTab: IDETab = .assistant
    @State private var signInTab: SignInTab = .googleAccount
    @Namespace private var tabThumb
    @Namespace private var signInThumb
    @Namespace private var modeThumb

    // Sign-in form state
    @State private var apiKeyInput: String = ""
    @State private var emailHintInput: String = ""
    @State private var selectedPlanHint: AntigravityPlanTier? = nil
    @State private var customClientIDInput: String = ""
    @State private var clipboardDetectedBanner: Bool = false
    @State private var showPlansInfo: Bool = false

    // Assistant / Mission Control state
    @State private var promptInput: String = ""

    // Code Editor state
    @State private var activeFilePath: String = "Projects/antigravity_app.py"
    @State private var editorContent: String = """
    # Google Antigravity IDE — Astral AI V8.5
    import datetime

    print("Antigravity IDE running natively on iPhone!")
    print("Time:", datetime.datetime.now().isoformat())
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
            if !embeddedInChat {
                AstralTheme.background.ignoresSafeArea()
            }

            if service.isSignedIn {
                ideWorkspaceView
            } else {
                signInOnboardingView
            }
        }
        .onAppear {
            workspace.refresh()
            customClientIDInput = service.customOAuthClientID
            checkClipboardForKey()
        }
        .sheet(item: $service.safariAuthItem, onDismiss: {
            service.dismissSafariSheet()
            checkClipboardForKey()
        }) { item in
            SafariAuthSheetView(url: item.url)
                .ignoresSafeArea()
        }
        .alert(isArabic ? "ملف جديد" : "New File", isPresented: $showNewFileSheet) {
            TextField("Projects/app.py", text: $newFileNameDraft)
            Button(L("common.cancel", "Shared"), role: .cancel) { newFileNameDraft = "" }
            Button(L("common.create", "Shared")) { createNewFile() }
        } message: {
            Text(isArabic ? "أدخل المسار داخل /home/astral" : "Enter the relative path inside /home/astral")
        }
    }

    private func checkClipboardForKey() {
        if apiKeyInput.isEmpty, let key = service.detectClipboardAPIKey() {
            apiKeyInput = key
            clipboardDetectedBanner = true
        }
    }

    // MARK: - 1. Clean, Structured Sign-In View (Pick Any Google Account, Zero Error 400)

    private var signInOnboardingView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Compact Refined Hero Header
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.25, green: 0.54, blue: 0.98).opacity(0.22),
                                        Color(red: 0.56, green: 0.42, blue: 0.98).opacity(0.18),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                            .liquidGlass(in: Circle(), interactive: true)

                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.36, green: 0.68, blue: 1.0),
                                        AstralTheme.orbGreen,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                    }

                    Text("Google Antigravity")
                        .font(AstralTheme.display(22, weight: .bold))
                        .foregroundStyle(AstralTheme.textPrimary)

                    Text(isArabic
                         ? "بيئة تطوير كاملة وشات ذكي بنماذج جوجل مباشرة على الآيفون بدون كمبيوتر"
                         : "Full Google IDE & Gemini chatbot natively on iPhone — no PC required")
                        .font(AstralTheme.body(13))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(.top, embeddedInChat ? 8 : 16)
                .padding(.bottom, 4)

                // Unified Sign-In Card with Clean 2-Segment Picker
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 4) {
                        signInMethodPill(
                            .googleAccount,
                            title: isArabic ? "حساب جوجل (فوري)" : "Google Account")
                        signInMethodPill(
                            .iosOAuth,
                            title: isArabic ? "OAuth 2.0 (iOS)" : "OAuth 2.0 (iOS)")
                    }
                    .padding(4)
                    .liquidGlass(in: Capsule(), tint: AstralTheme.actionFill.opacity(0.05))

                    if signInTab == .googleAccount {
                        googleAccountInstantForm
                    } else {
                        iosOAuthForm
                    }

                    if let error = service.lastError {
                        HStack(alignment: .top, spacing: 8) {
                            AIcon(AstralIcons.close, size: 12, strokeWidth: 2.3, color: AstralTheme.danger)
                                .padding(.top, 3)
                            Text(error)
                                .font(AstralTheme.body(12))
                                .foregroundStyle(AstralTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AstralTheme.danger.opacity(0.10)))
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 22, depth: .panel)

                // Collapsible Plans Reference Card
                DisclosureGroup(isExpanded: $showPlansInfo) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(AntigravityPlanTier.allCases) { tier in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(tier.accentColor)
                                    .frame(width: 8, height: 8)
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
                    .padding(.top, 10)
                } label: {
                    HStack(spacing: 8) {
                        AIcon(AstralIcons.sparkles, size: 14, strokeWidth: 2.1, color: AstralTheme.orbGreen)
                        Text(isArabic ? "النماذج المتاحة حسب خطة حسابك في جوجل" : "Models Unlocked by Your Google AI Plan")
                            .font(AstralTheme.headline(13))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 20, depth: .panel)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
    }

    private func signInMethodPill(_ tab: SignInTab, title: String) -> some View {
        let active = signInTab == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                signInTab = tab
                service.lastError = nil
            }
        } label: {
            Text(title)
                .font(AstralTheme.headline(12.5))
                .foregroundStyle(active ? AstralTheme.actionForeground : AstralTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if active {
                        Capsule()
                            .fill(AstralTheme.actionFill)
                            .matchedGeometryEffect(id: "ag-signin-thumb", in: signInThumb)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var googleAccountInstantForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Step 1: Open Google Account Chooser (always lets user choose which email!)
            Button {
                service.openGoogleAccountChooser()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 16, weight: .semibold))
                    Text(isArabic ? "اختيار حساب جوجل والحصول على المفتاح" : "Choose Google Account & Get Key")
                        .font(AstralTheme.headline(13.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(GlassProminentButtonStyle())

            Text(isArabic
                 ? "سيفتح لك جوجل قائمة لاختيار الإيميل الذي تريده (بدون تسجيل تلقائي). انسخ المفتاح وعد للتطبيق وسيتم لصقه تلقائياً."
                 : "Opens Google's Account Chooser so you can pick any Gmail account. Copy your key and return — Astral detects it automatically.")
                .font(AstralTheme.body(11.5))
                .foregroundStyle(AstralTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if clipboardDetectedBanner {
                HStack(spacing: 6) {
                    AIcon(AstralIcons.checkCircle, size: 13, strokeWidth: 2.2, color: AstralTheme.orbGreen)
                    Text(isArabic ? "تم اكتشاف مفتاح Google AI Studio تلقائياً من الحافظة" : "Google AI Studio key detected from clipboard")
                        .font(AstralTheme.mono(10.5).weight(.semibold))
                        .foregroundStyle(AstralTheme.orbGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AstralTheme.orbGreen.opacity(0.12)))
            }

            // Key Input with integrated Paste button
            HStack(spacing: 8) {
                SecureField("AIzaSy...", text: $apiKeyInput)
                    .font(AstralTheme.mono(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    if let pasted = UIPasteboard.general.string {
                        apiKeyInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Text(isArabic ? "لصق" : "Paste")
                        .font(AstralTheme.mono(11).weight(.bold))
                        .foregroundStyle(AstralTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .liquidCapsule(tint: AstralTheme.accent.opacity(0.14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AstralTheme.surfaceSecondary.opacity(0.75)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AstralTheme.separator, lineWidth: 1))

            TextField(isArabic ? "البريد الإلكتروني (اختياري)" : "Google email (optional)", text: $emailHintInput)
                .font(AstralTheme.body(13))
                .textFieldStyle(GlassTextFieldStyle())
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            // Clean 2-column grid for Plan Selection (zero cramped horizontal scroll)
            VStack(alignment: .leading, spacing: 6) {
                Text(isArabic ? "خطة الحساب" : "Google AI Plan")
                    .font(AstralTheme.mono(10.5).weight(.semibold))
                    .foregroundStyle(AstralTheme.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    planGridButton(title: isArabic ? "اكتشاف تلقائي" : "Auto Detect", tier: nil)
                    planGridButton(title: "Free / AI Plus", tier: .free)
                    planGridButton(title: "Google AI Pro", tier: .pro)
                    planGridButton(title: "Google AI Ultra", tier: .ultra)
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
                    Text(isArabic ? "اتصال وتشغيل Antigravity" : "Connect & Launch Antigravity")
                        .font(AstralTheme.headline(14))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isSigningIn)
        }
    }

    private var iosOAuthForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isArabic
                 ? "لتسجيل الدخول المباشر بـ OAuth 2.0 على iOS بدون خطأ 400، أدخل iOS Client ID الخاص بك من Google Cloud Console. الجلسة الخاصة مفعّلة لاختيار أي إيميل."
                 : "For direct Google OAuth 2.0 on iOS without Error 400, enter your Google Cloud iOS Client ID. Ephemeral session is enabled so you always choose your email.")
                .font(AstralTheme.body(12))
                .foregroundStyle(AstralTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("xxxx.apps.googleusercontent.com", text: $customClientIDInput)
                .font(AstralTheme.mono(12))
                .textFieldStyle(GlassTextFieldStyle())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: customClientIDInput) { _, newValue in
                    service.customOAuthClientID = newValue
                }

            Toggle(isOn: $service.useEphemeralOAuthSession) {
                Text(isArabic ? "فتح اختيار الإيميل دائماً (جلسة خاصة)" : "Always ask which email (Private Session)")
                    .font(AstralTheme.body(12.5))
                    .foregroundStyle(AstralTheme.textPrimary)
            }
            .tint(AstralTheme.orbGreen)

            Button {
                Task {
                    await service.signInWithGoogleOAuth(
                        preferredTier: selectedPlanHint,
                        providerStore: env.providerStore)
                }
            } label: {
                HStack(spacing: 8) {
                    if service.isSigningIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(isArabic ? "تسجيل الدخول عبر Google OAuth" : "Sign in with Google OAuth")
                        .font(AstralTheme.headline(13.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .disabled(service.isSigningIn)
        }
    }

    private func planGridButton(title: String, tier: AntigravityPlanTier?) -> some View {
        let isSelected = selectedPlanHint == tier
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.84)) {
                selectedPlanHint = tier
            }
        } label: {
            Text(title)
                .font(AstralTheme.mono(11).weight(.semibold))
                .foregroundStyle(isSelected ? .black : AstralTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AstralTheme.orbGreen : AstralTheme.actionFill.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Connected IDE & Chatbot Workspace (Refined Layout)

    private var ideWorkspaceView: some View {
        VStack(spacing: 8) {
            // Compact Top Status & Model Picker Bar
            ideTopControlBar
                .padding(.horizontal, 12)
                .padding(.top, embeddedInChat ? 4 : 8)

            // Balanced 4-Segment IDE Tab Bar
            ideTabPicker
                .padding(.horizontal, 12)

            // Active Tab Content
            Group {
                switch selectedTab {
                case .assistant:
                    assistantAndMissionTab
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
            if let acc = service.account {
                HStack(spacing: 5) {
                    Circle()
                        .fill(acc.planTier.accentColor)
                        .frame(width: 7, height: 7)
                    Text(acc.planTier.displayName)
                        .font(AstralTheme.mono(10.5).weight(.bold))
                        .foregroundStyle(acc.planTier.accentColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .liquidCapsule(tint: acc.planTier.accentColor.opacity(0.14))
            }

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
                Section(isArabic ? "مستوى التفكير" : "Thinking Level") {
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
                    Spacer(minLength: 4)
                    Text(service.thinkingLevel.label)
                        .font(AstralTheme.mono(10))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .lineLimit(1)
                    AIcon(AstralIcons.chevronsUpDown, size: 10.5, strokeWidth: 2.2, color: AstralTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .liquidGlass(in: Capsule(), interactive: true)
            }
        }
    }

    private var ideTabPicker: some View {
        HStack(spacing: 4) {
            ideTabButton(.assistant, icon: AstralIcons.sparkles, label: isArabic ? "المساعد" : "Assistant")
            ideTabButton(.editor, icon: AstralIcons.fileCode, label: isArabic ? "المحرر" : "Editor")
            ideTabButton(.terminal, icon: AstralIcons.terminal, label: isArabic ? "الطرفية" : "Shell")
            ideTabButton(.account, icon: AstralIcons.cpu, label: isArabic ? "الحساب" : "Account")
        }
        .padding(4)
        .liquidGlass(in: Capsule(), tint: AstralTheme.actionFill.opacity(0.05))
    }

    private func ideTabButton(_ tab: IDETab, icon: String, label: String) -> some View {
        let active = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                AIcon(
                    icon,
                    size: 12,
                    strokeWidth: 2.2,
                    color: active ? AstralTheme.actionForeground : AstralTheme.textSecondary)
                Text(label)
                    .font(AstralTheme.headline(11.5))
                    .foregroundStyle(active ? AstralTheme.actionForeground : AstralTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
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

    // MARK: - Tab 1: Unified Chatbot + Autonomous IDE Missions

    private var assistantAndMissionTab: some View {
        VStack(spacing: 8) {
            // Clean 2-Mode Toggle: Normal Chatbot vs Autonomous IDE Mission
            HStack(spacing: 6) {
                workModePill(
                    .chat,
                    icon: AstralIcons.chat,
                    label: isArabic ? "شات عادي" : "Normal Chat")
                workModePill(
                    .ideMission,
                    icon: AstralIcons.fileCode,
                    label: isArabic ? "مهمة IDE برمجية" : "IDE Coding Agent")
                if !service.missions.isEmpty {
                    Button {
                        service.clearMissions()
                    } label: {
                        AIcon(AstralIcons.trash, size: 13, strokeWidth: 2, color: AstralTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if service.missions.isEmpty {
                        VStack(spacing: 12) {
                            Spacer(minLength: 16)
                            Image(systemName: service.workMode == .chat ? "bubble.left.and.text.bubble.right.fill" : "sparkles.rectangle.stack")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(AstralTheme.orbGreen.opacity(0.88))

                            Text(service.workMode == .chat
                                 ? (isArabic ? "محادثة Google Antigravity" : "Google Antigravity Chat")
                                 : (isArabic ? "وكيل البرمجة الذاتي (IDE)" : "Antigravity Autonomous IDE"))
                                .font(AstralTheme.headline(16))
                                .foregroundStyle(AstralTheme.textPrimary)

                            Text(service.workMode == .chat
                                 ? (isArabic
                                    ? "اسأل أي سؤال أو ناقش أفكارك بحرية مع نموذج Gemini المتصل بحسابك."
                                    : "Ask anything or chat naturally with your connected Gemini model.")
                                 : (isArabic
                                    ? "اطلب إنشاء تطبيق أو تعديل ملفات — سيكتب الكود مباشرة في /home/astral ويشغّله على Ubuntu."
                                    : "Ask to build an app or edit files — it writes code directly to /home/astral and verifies it on Ubuntu."))
                                .font(AstralTheme.body(12.5))
                                .foregroundStyle(AstralTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            VStack(spacing: 8) {
                                if service.workMode == .chat {
                                    quickPromptButton(isArabic ? "اشرح لي فكرة البرمجة غير المتزامنة ببساطة" : "Explain async/await simply with an example")
                                    quickPromptButton(isArabic ? "اقترح لي فكرة تطبيق iOS مميزة وخطة تنفيذها" : "Suggest an original iOS app idea and roadmap")
                                } else {
                                    quickPromptButton(isArabic ? "أنشئ صفحة هبوط HTML احترافية في Projects/landing.html" : "Create a modern HTML landing page in Projects/landing.html")
                                    quickPromptButton(isArabic ? "اكتب سكربت بايثون لتحليل البيانات في Projects/analyzer.py" : "Write a Python data analyzer in Projects/analyzer.py")
                                }
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(service.missions) { mission in
                            missionCard(mission)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // Clean Bottom Composer Bar
            VStack(spacing: 6) {
                if let error = service.lastError {
                    Text(error)
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(AstralTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                HStack(spacing: 10) {
                    TextField(
                        service.workMode == .chat
                            ? (isArabic ? "اكتب رسالتك هنا..." : "Message Antigravity...")
                            : (isArabic ? "اطلب مهمة برمجية في مساحة العمل..." : "Give Antigravity a coding mission..."),
                        text: $promptInput,
                        axis: .vertical)
                        .font(AstralTheme.body(14.5))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1...4)

                    Button {
                        let text = promptInput
                        promptInput = ""
                        Task {
                            await service.runMission(
                                prompt: text,
                                activeFilePath: activeFilePath,
                                activeFileContent: editorContent,
                                providerStore: env.providerStore)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isRunningMission
                                      ? AstralTheme.actionFill.opacity(0.15)
                                      : AstralTheme.orbGreen)
                                .frame(width: 36, height: 36)
                            if service.isRunningMission {
                                ProgressView().controlSize(.mini).tint(.black)
                            } else {
                                AIcon(AstralIcons.arrowUp, size: 16, strokeWidth: 2.5, color: .black)
                            }
                        }
                    }
                    .disabled(promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isRunningMission)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func workModePill(_ mode: AntigravityWorkMode, icon: String, label: String) -> some View {
        let active = service.workMode == mode
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                service.workMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                AIcon(icon, size: 12, strokeWidth: 2.1, color: active ? .black : AstralTheme.textSecondary)
                Text(label)
                    .font(AstralTheme.headline(11.5))
                    .foregroundStyle(active ? .black : AstralTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if active {
                    Capsule()
                        .fill(AstralTheme.orbGreen)
                        .matchedGeometryEffect(id: "ag-workmode-thumb", in: modeThumb)
                } else {
                    Capsule()
                        .fill(AstralTheme.actionFill.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func quickPromptButton(_ text: String) -> some View {
        Button {
            promptInput = text
        } label: {
            HStack(spacing: 8) {
                AIcon(AstralIcons.sparkles, size: 13, strokeWidth: 2, color: AstralTheme.orbGreen)
                Text(text)
                    .font(AstralTheme.body(12.5))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.horizontal, 13)
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
                    .frame(width: 7.5, height: 7.5)
                Text(mission.modelName)
                    .font(AstralTheme.mono(10.5).weight(.bold))
                    .foregroundStyle(AstralTheme.orbGreen)
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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .liquidCapsule(tint: AstralTheme.accent.opacity(0.14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            ForEach(mission.artifacts) { artifact in
                if artifact.kind == .walkthrough {
                    MarkdownView(artifact.content)
                        .padding(.top, 2)
                } else {
                    DisclosureGroup {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(artifact.content)
                                .font(AstralTheme.mono(11))
                                .foregroundStyle(AstralTheme.textPrimary)
                                .textSelection(.enabled)
                                .padding(10)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.35)))
                        .padding(.top, 4)
                    } label: {
                        HStack(spacing: 7) {
                            AIcon(
                                artifact.kind == .terminal ? AstralIcons.terminal : AstralIcons.fileCode,
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

    // MARK: - Tab 2: Code Editor (Cleanly Aligned Toolbar + Full Editor)

    private var codeEditorTab: some View {
        VStack(spacing: 10) {
            // File Strip
            HStack(spacing: 8) {
                Button {
                    showNewFileSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(isArabic ? "جديد" : "New")
                            .font(AstralTheme.mono(11).weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AstralTheme.orbGreen))
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(workspace.list(), id: \.relativePath) { file in
                            let isSelected = activeFilePath == file.relativePath
                            Button {
                                openFileInEditor(path: file.relativePath)
                            } label: {
                                Text(file.relativePath)
                                    .font(AstralTheme.mono(11).weight(isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? AstralTheme.textPrimary : AstralTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .liquidCapsule(tint: isSelected ? AstralTheme.accent.opacity(0.22) : .clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            // Active File Name + Evenly Spaced 3-Button Action Row
            VStack(spacing: 8) {
                HStack {
                    AIcon(AstralIcons.fileCode, size: 12, strokeWidth: 2, color: AstralTheme.accent)
                    Text(activeFilePath)
                        .font(AstralTheme.mono(11.5).weight(.semibold))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        saveActiveFile()
                    } label: {
                        Label(L("common.save", "Shared"), systemImage: "square.and.arrow.down")
                            .font(AstralTheme.headline(11.5))
                            .foregroundStyle(AstralTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                    }
                    .buttonStyle(.plain)

                    Button {
                        runActiveFileOnUbuntu()
                    } label: {
                        Label(isArabic ? "تشغيل" : "Run", systemImage: "play.fill")
                            .font(AstralTheme.headline(11.5))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AstralTheme.orbGreen))
                    }
                    .buttonStyle(.plain)

                    Button {
                        service.workMode = .ideMission
                        promptInput = isArabic
                            ? "راجع الملف \(activeFilePath) وحسّن الكود وأصلح أي أخطاء"
                            : "Review \(activeFilePath), improve code quality, and fix any issues"
                        selectedTab = .assistant
                    } label: {
                        Label(isArabic ? "تحسين" : "AI Fix", systemImage: "sparkles")
                            .font(AstralTheme.headline(11.5))
                            .foregroundStyle(AstralTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), tint: AstralTheme.accent.opacity(0.12), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            // Monospace Code Editor Surface
            TextEditor(text: $editorContent)
                .font(AstralTheme.mono(12.5))
                .foregroundStyle(AstralTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.35)))
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
                    .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 8)
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
        Task { _ = await shell.run(cmd) }
    }

    // MARK: - Tab 3: Integrated Ubuntu Base 24.04 Terminal

    private var embeddedTerminalTab: some View {
        VStack(spacing: 8) {
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
                                .padding(.vertical, 6)
                                .liquidCapsule(tint: AstralTheme.actionFill.opacity(0.08))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("Ubuntu Base 24.04.2 LTS (arm64) · /home/astral")
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
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AstralTheme.orbGreen))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
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
                    VStack(alignment: .leading, spacing: 14) {
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
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(acc.planTier.displayName)
                                .font(AstralTheme.mono(10).weight(.bold))
                                .foregroundStyle(acc.planTier.accentColor)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .liquidCapsule(tint: acc.planTier.accentColor.opacity(0.16))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(isArabic ? "الحصة المتبقية" : "Remaining Quota")
                                    .font(AstralTheme.body(12))
                                    .foregroundStyle(AstralTheme.textSecondary)
                                Spacer()
                                Text("\(acc.quotaRemainingPercent)%")
                                    .font(AstralTheme.mono(11.5).weight(.bold))
                                    .foregroundStyle(AstralTheme.orbGreen)
                            }
                            GlassProgressView(progress: Double(acc.quotaRemainingPercent) / 100.0, height: 6)
                        }

                        // Clean 2×2 Plan Tier Grid
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isArabic ? "خطة Google AI" : "Active Google AI Plan")
                                .font(AstralTheme.mono(10.5).weight(.semibold))
                                .foregroundStyle(AstralTheme.textSecondary)

                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(AntigravityPlanTier.allCases) { tier in
                                    let active = acc.planTier == tier
                                    Button {
                                        service.updatePlanTier(tier, providerStore: env.providerStore)
                                    } label: {
                                        Text(tier.displayName)
                                            .font(AstralTheme.mono(10.5).weight(.bold))
                                            .foregroundStyle(active ? .black : AstralTheme.textPrimary)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 9)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(active ? tier.accentColor : AstralTheme.actionFill.opacity(0.08)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Equal-width Sync & Sign Out buttons
                        HStack(spacing: 10) {
                            Button {
                                Task { await service.refreshDiscoveredModels(providerStore: env.providerStore) }
                            } label: {
                                HStack(spacing: 6) {
                                    if service.isSyncingModels {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        AIcon(AstralIcons.refresh, size: 12, strokeWidth: 2.2, color: AstralTheme.textPrimary)
                                    }
                                    Text(isArabic ? "مزامنة النماذج" : "Sync Models")
                                        .font(AstralTheme.headline(12))
                                        .foregroundStyle(AstralTheme.textPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                service.signOut(providerStore: env.providerStore)
                            } label: {
                                Text(isArabic ? "تسجيل الخروج" : "Sign Out")
                                    .font(AstralTheme.headline(12))
                                    .foregroundStyle(AstralTheme.danger)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), tint: AstralTheme.danger.opacity(0.08), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }

                        if let status = service.statusMessage {
                            Text(status)
                                .font(AstralTheme.mono(10.5))
                                .foregroundStyle(AstralTheme.orbGreen)
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 22, depth: .panel)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isArabic ? "نماذج Google Antigravity المتصلة" : "Connected Google Models")
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
                                    VStack(alignment: .leading, spacing: 3) {
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
                                .padding(11)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selected ? AstralTheme.orbGreen.opacity(0.10) : AstralTheme.actionFill.opacity(0.03)))
                                .opacity(unlocked ? 1.0 : 0.55)
                            }
                            .buttonStyle(.plain)
                            .disabled(!unlocked)
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 22, depth: .panel)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Native SFSafariViewController Sheet for Google Account Chooser

private struct SafariAuthSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
