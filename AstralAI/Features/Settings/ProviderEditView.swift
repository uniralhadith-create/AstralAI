import SwiftUI

// MARK: - Provider editor

/// Sheet for creating or editing an AI provider: basics, API key, model
/// discovery, connection test and an advanced section exposing the full
/// custom protocol mapping (paths, auth, headers, extra body).
struct ProviderEditView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    @State private var config: ProviderConfig
    let isNew: Bool
    let onSave: (ProviderConfig) -> Void

    @State private var apiKey: String = ""
    @State private var hasStoredKey = false

    @State private var testing = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    @State private var discoveredModels: [ModelInfo] = []
    @State private var discovering = false
    @State private var discoveryError: String?
    @State private var showingModelPicker = false
    @State private var rolePicker: ModelRole = .main

    @State private var advancedExpanded = false
    @State private var extraBodyText: String
    @State private var extraBodyError = false
    @State private var maxTokensText: String
    @State private var timeoutText: String

    @State private var nameError = false
    @State private var urlError = false

    init(
        config: ProviderConfig,
        isNew: Bool,
        onSave: @escaping (ProviderConfig) -> Void
    ) {
        _config = State(initialValue: config)
        self.isNew = isNew
        self.onSave = onSave

        if config.custom.extraBody.isEmpty {
            _extraBodyText = State(initialValue: "")
        } else if let data = JSONValue.object(config.custom.extraBody).jsonData(pretty: true),
                  let text = String(data: data, encoding: .utf8) {
            _extraBodyText = State(initialValue: text)
        } else {
            _extraBodyText = State(initialValue: "")
        }

        _maxTokensText = State(initialValue: config.maxTokens.map { String($0) } ?? "")
        _timeoutText = State(
            initialValue: config.timeout > 0 ? String(format: "%.0f", config.timeout) : "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AstralTheme.Spacings.m) {
                    basicsCard
                    apiKeyCard
                    modelsCard
                    testCard
                    advancedCard
                }
                .padding(.horizontal, AstralTheme.Spacings.m)
                .padding(.vertical, AstralTheme.Spacings.l)
            }
            .navigationTitle(isNew ? L("settings.addProvider", "Settings") : L("settings.editProvider", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("settings.cancel", "Settings")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("settings.save", "Settings")) { save() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Basics

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
            SectionHeader(icon: "server.rack", "settings.basics", table: "Settings")

            presetsMenu

            VStack(alignment: .leading, spacing: AstralTheme.Spacings.xxs) {
                LabeledField(
                    title: L("settings.name", "Settings"),
                    text: $config.name,
                    placeholder: L("settings.name", "Settings"),
                    invalid: nameError)
                if nameError {
                    errorText(L("settings.nameRequired", "Settings"))
                }

                LabeledField(
                    title: L("settings.baseURL", "Settings"),
                    text: $config.baseURL,
                    placeholder: "https://api.openai.com/v1",
                    invalid: urlError)
                if urlError {
                    errorText(L("settings.urlRequired", "Settings"))
                }
            }

            VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                fieldLabel(L("settings.protocol", "Settings"))
                Picker(L("settings.protocol", "Settings"), selection: $config.protocolKind) {
                    Text(L("settings.protocolOpenAI", "Settings"))
                        .tag(APIProtocolKind.openAICompatible)
                    Text("AWS Bedrock")
                        .tag(APIProtocolKind.bedrock)
                    Text(L("settings.protocolCustom", "Settings"))
                        .tag(APIProtocolKind.custom)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(depth: .panel)
    }

    /// One-tap provider templates with verified URLs & models.
    private var presetsMenu: some View {
        Menu {
            ForEach(ProviderPresets.all) { preset in
                Button {
                    applyPreset(preset)
                } label: {
                    Label(preset.localizedName, systemImage: preset.id == "bedrock" ? "cube.fill" : "bolt.fill")
                }
            }
        } label: {
            HStack(spacing: AstralTheme.Spacings.xs) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                Text(L("settings.presets", "Settings"))
                    .font(AstralTheme.headline(13))
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(AstralTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .liquidCapsule(tint: AstralTheme.accent.opacity(0.10), interactive: true)
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text(L("settings.presets", "Settings")))
    }

    private func applyPreset(_ preset: ProviderPreset) {
        config.name = preset.localizedName
        config.baseURL = preset.baseURL
        config.protocolKind = preset.kind
        discoveredModels = []
        discoveryError = nil
        if config.mainModel.isEmpty {
            config.mainModel = preset.models.first ?? ""
        }
        if let first = preset.models.first, !first.isEmpty {
            discoveredModels = preset.models.map {
                ModelInfo(id: $0, name: nil, ownedBy: preset.name, contextLength: nil)
            }
        }
    }

    // MARK: - API key

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
            SectionHeader(icon: "key.fill", "settings.apiKey", table: "Settings")

            if config.protocolKind == .bedrock {
                TextField(
                    hasStoredKey ? "AKIA...:wJalr..." : "ACCESS_KEY_ID:SECRET_ACCESS_KEY",
                    text: $apiKey)
                    .font(AstralTheme.mono(13))
                    .textFieldStyle(GlassTextFieldStyle())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                SecureField(
                    hasStoredKey ? L("settings.keySaved", "Settings") : L("settings.apiKey", "Settings"),
                    text: $apiKey)
                    .font(AstralTheme.mono(13))
                    .textFieldStyle(GlassTextFieldStyle())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Text(currentKeyHint)
                .font(AstralTheme.body(12))
                .foregroundStyle(AstralTheme.moonDust)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(depth: .panel)
        .onAppear {
            hasStoredKey = env.providerStore.key(for: config.id) != nil
        }
    }

    /// Contextual key hint: preset-specific when the URL matches a preset,
    /// the Bedrock format hint for Bedrock, the generic hint otherwise.
    private var currentKeyHint: String {
        if config.protocolKind == .bedrock {
            return L("settings.bedrockKeyHint", "Settings")
        }
        let normalized = EndpointResolver.normalizeBaseURL(config.baseURL) ?? ""
        for preset in ProviderPresets.all where EndpointResolver.normalizeBaseURL(preset.baseURL) == normalized {
            if !preset.localizedKeyHint.isEmpty {
                return preset.localizedKeyHint
            }
        }
        return L("settings.keyHint", "Settings")
    }

    // MARK: - Models

    private var modelsCard: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
            SectionHeader(icon: "cube.transparent", "settings.models", table: "Settings")

            VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                LabeledField(
                    title: L("settings.modelMain", "Settings"),
                    text: $config.mainModel,
                    placeholder: "gpt-4o",
                    mono: true)
                LabeledField(
                    title: L("settings.modelPlanner", "Settings"),
                    text: $config.plannerModel,
                    placeholder: "gpt-4o-mini",
                    mono: true)
                LabeledField(
                    title: L("settings.modelSubAgent", "Settings"),
                    text: $config.subAgentModel,
                    placeholder: "gpt-4o-mini",
                    mono: true)
            }

            VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                fieldLabel(L("settings.applyTo", "Settings"))
                Picker(L("settings.applyTo", "Settings"), selection: $rolePicker) {
                    Text(L("settings.modelMain", "Settings")).tag(ModelRole.main)
                    Text(L("settings.modelPlanner", "Settings")).tag(ModelRole.planner)
                    Text(L("settings.modelSubAgent", "Settings")).tag(ModelRole.subAgent)
                }
                .pickerStyle(.segmented)

                HStack(spacing: AstralTheme.Spacings.s) {
                    Button {
                        discoverModels()
                    } label: {
                        HStack(spacing: AstralTheme.Spacings.xs) {
                            if discovering {
                                ProgressView()
                                    .tint(AstralTheme.textPrimary)
                            }
                            Text(discovering
                                ? L("settings.discovering", "Settings")
                                : L("settings.discoverModels", "Settings"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(discovering)

                    if !discoveredModels.isEmpty {
                        Button {
                            showingModelPicker = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AstralTheme.accent)
                                .padding(.horizontal, AstralTheme.Spacings.m)
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
            }

            if let discoveryError {
                errorText(discoveryError)
            }

            if !discoveredModels.isEmpty {
                VStack(spacing: AstralTheme.Spacings.xxs) {
                    ForEach(discoveredModels) { model in
                        Button {
                            applyModel(model.id)
                        } label: {
                            HStack(spacing: AstralTheme.Spacings.s) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AstralTheme.nebulaViolet)
                                Text(model.id)
                                    .font(AstralTheme.mono(12))
                                    .foregroundStyle(AstralTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                                if let ownedBy = model.ownedBy, !ownedBy.isEmpty {
                                    Text(ownedBy)
                                        .font(AstralTheme.body(10))
                                        .foregroundStyle(AstralTheme.moonDust)
                                }
                            }
                            .padding(.horizontal, AstralTheme.Spacings.s)
                            .padding(.vertical, AstralTheme.Spacings.xs)
                            .glassCard(
                                cornerRadius: AstralTheme.Radius.small,
                                depth: .raised)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(depth: .panel)
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView(
                models: discoveredModels,
                currentSelection: currentRoleModel,
                onSelect: { id in applyModel(id) })
                .settingsSheetEnvironment(env: env, language: language)
        }
    }

    // MARK: - Connection test

    private var testCard: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
            SectionHeader(icon: "antenna.radiowaves.left.and.right", "settings.testConnection", table: "Settings")

            Button {
                runTest()
            } label: {
                HStack(spacing: AstralTheme.Spacings.xs) {
                    if testing {
                        ProgressView()
                            .tint(AstralTheme.textPrimary)
                    }
                    Text(testing
                        ? L("settings.testing", "Settings")
                        : L("settings.testConnection", "Settings"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(testing)

            if let testResult {
                HStack(alignment: .top, spacing: AstralTheme.Spacings.xs) {
                    Image(systemName: testSucceeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(testSucceeded ? AstralTheme.success : AstralTheme.danger)
                    Text(testResult)
                        .font(AstralTheme.body(13))
                        .foregroundStyle(testSucceeded ? AstralTheme.success : AstralTheme.danger)
                }
            }
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(depth: .panel)
    }

    // MARK: - Advanced

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
            DisclosureGroup(isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
                    temperatureRow

                    LabeledField(
                        title: L("settings.maxTokens", "Settings"),
                        text: $maxTokensText,
                        placeholder: "4096",
                        mono: true)

                    LabeledField(
                        title: L("settings.timeout", "Settings"),
                        text: $timeoutText,
                        placeholder: "180",
                        mono: true)

                    Toggle(isOn: $config.sendKeyForModels) {
                        Text(L("settings.sendKeyForModels", "Settings"))
                            .font(AstralTheme.body(15))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                    .tint(AstralTheme.nebulaViolet)

                    customProtocolSection

                    HeadersEditorView(headers: $config.custom.extraHeaders)

                    extraBodySection
                }
                .padding(.top, AstralTheme.Spacings.s)
            } label: {
                SectionHeader(icon: "slider.horizontal.3", "settings.advanced", table: "Settings")
            }
            .tint(AstralTheme.auroraCyan)
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(depth: .panel)
    }

    private var temperatureRow: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.xxs) {
            HStack {
                Text(L("settings.temperature", "Settings"))
                    .font(AstralTheme.body(13))
                    .foregroundStyle(AstralTheme.textSecondary)
                Spacer()
                Text(String(format: "%.1f", config.temperature))
                    .font(AstralTheme.mono(13))
                    .foregroundStyle(AstralTheme.auroraCyan)
            }
            Slider(value: $config.temperature, in: 0...2, step: 0.1)
                .tint(AstralTheme.nebulaViolet)
        }
    }

    private var customProtocolSection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
            Text(L("settings.customNote", "Settings"))
                .font(AstralTheme.body(12))
                .foregroundStyle(AstralTheme.moonDust)

            LabeledField(
                title: L("settings.chatPath", "Settings"),
                text: $config.custom.chatPath,
                placeholder: "/v1/chat/completions",
                mono: true)

            LabeledField(
                title: L("settings.modelsPath", "Settings"),
                text: modelsPathBinding,
                placeholder: "/v1/models",
                mono: true)

            VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                fieldLabel(L("settings.method", "Settings"))
                Picker(L("settings.method", "Settings"), selection: methodBinding) {
                    Text("POST").tag("POST")
                    Text("GET").tag("GET")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                fieldLabel(L("settings.authStyle", "Settings"))
                Picker(L("settings.authStyle", "Settings"), selection: $config.custom.authStyle) {
                    Text(L("settings.authBearer", "Settings")).tag(AuthStyle.bearer)
                    Text(L("settings.authCustomHeader", "Settings")).tag(AuthStyle.customHeader)
                    Text(L("settings.authNone", "Settings")).tag(AuthStyle.none)
                }
                .pickerStyle(.menu)
            }

            if config.custom.authStyle == .customHeader {
                LabeledField(
                    title: L("settings.authHeaderName", "Settings"),
                    text: $config.custom.authHeaderName,
                    placeholder: "Authorization",
                    mono: true)
                LabeledField(
                    title: L("settings.authValueFormat", "Settings"),
                    text: $config.custom.authValueFormat,
                    placeholder: "Bearer %@",
                    mono: true)
            }

            VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                fieldLabel(L("settings.streamFormat", "Settings"))
                Picker(L("settings.streamFormat", "Settings"), selection: $config.custom.streamFormat) {
                    Text(L("settings.streamSSE", "Settings")).tag(StreamFormat.sse)
                    Text(L("settings.streamNDJSON", "Settings")).tag(StreamFormat.ndjson)
                    Text(L("settings.streamNone", "Settings")).tag(StreamFormat.none)
                }
                .pickerStyle(.segmented)
            }

            LabeledField(
                title: L("settings.streamTextPath", "Settings"),
                text: $config.custom.streamTextPath,
                placeholder: "choices.0.delta.content",
                mono: true)

            LabeledField(
                title: L("settings.fullTextPath", "Settings"),
                text: $config.custom.fullTextPath,
                placeholder: "choices.0.message.content",
                mono: true)

            LabeledField(
                title: L("settings.toolCallsPath", "Settings"),
                text: $config.custom.toolCallsPath,
                placeholder: "choices.0.message.tool_calls",
                mono: true)

            LabeledField(
                title: L("settings.finishPath", "Settings"),
                text: $config.custom.finishPath,
                placeholder: "choices.0.finish_reason",
                mono: true)

            LabeledField(
                title: L("settings.modelsIDPath", "Settings"),
                text: $config.custom.modelsIDPath,
                placeholder: "data.[].id",
                mono: true)
        }
    }

    private var extraBodySection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
            fieldLabel(L("settings.extraBody", "Settings"))
            TextField("{ \"key\": \"value\" }", text: $extraBodyText, axis: .vertical)
                .font(AstralTheme.mono(12))
                .textFieldStyle(GlassTextFieldStyle())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .lineLimit(2...8)
            if extraBodyError {
                errorText(L("settings.invalidJSON", "Settings"))
            }
        }
    }

    // MARK: - Bindings

    private var modelsPathBinding: Binding<String> {
        Binding(
            get: { config.custom.modelsPath ?? "" },
            set: { config.custom.modelsPath = $0.isEmpty ? nil : $0 })
    }

    private var methodBinding: Binding<String> {
        Binding(
            get: { config.custom.method.uppercased() == "GET" ? "GET" : "POST" },
            set: { config.custom.method = $0 })
    }

    // MARK: - Actions

    private var currentRoleModel: String {
        switch rolePicker {
        case .main: return config.mainModel
        case .planner: return config.plannerModel
        case .subAgent: return config.subAgentModel
        }
    }

    private func applyModel(_ id: String) {
        switch rolePicker {
        case .main: config.mainModel = id
        case .planner: config.plannerModel = id
        case .subAgent: config.subAgentModel = id
        }
    }

    /// Uses the form's current values (not the persisted ones) so discovery
    /// works for brand-new providers and reflects unsaved edits instantly.
    private func discoverModels() {
        discovering = true
        discoveryError = nil
        let candidate = config
        let key = apiKey.isEmpty ? env.providerStore.key(for: config.id) : apiKey
        Task { @MainActor in
            do {
                let models = try await LLMService.fetchModels(config: candidate, apiKey: key)
                self.discoveredModels = models
                if models.isEmpty {
                    self.discoveryError = L("settings.noModels", "Settings")
                }
            } catch {
                self.discoveredModels = []
                self.discoveryError = error.localizedDescription
            }
            self.discovering = false
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        let candidate = config
        let key = apiKey.isEmpty ? env.providerStore.key(for: config.id) : apiKey
        Task { @MainActor in
            do {
                let (_, elapsed) = try await LLMService.testConnection(config: candidate, apiKey: key)
                self.testSucceeded = true
                self.testResult = String(
                    format: L("settings.testOk", "Settings"),
                    Int(elapsed * 1000))
            } catch {
                self.testSucceeded = false
                self.testResult = error.localizedDescription
            }
            self.testing = false
        }
    }

    private func save() {
        let trimmedName = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        nameError = trimmedName.isEmpty
        urlError = trimmedURL.isEmpty

        // Extra body must be empty or a valid JSON object.
        let trimmedExtraBody = extraBodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        var extraBody: [String: JSONValue] = [:]
        if !trimmedExtraBody.isEmpty {
            if let data = trimmedExtraBody.data(using: .utf8),
               let value = JSONValue.from(data: data),
               let object = value.objectValue {
                extraBody = object
            } else {
                extraBodyError = true
                return
            }
        }
        extraBodyError = false

        guard !nameError, !urlError else { return }

        config.name = trimmedName
        config.baseURL = trimmedURL
        config.custom.extraBody = extraBody

        if let maxTokens = Int(maxTokensText.filter { $0.isNumber }), maxTokens > 0 {
            config.maxTokens = maxTokens
        } else {
            config.maxTokens = nil
        }
        if let timeout = Double(timeoutText.replacingOccurrences(of: ",", with: ".")), timeout > 0 {
            config.timeout = timeout
        }

        if !apiKey.isEmpty {
            env.providerStore.saveKey(apiKey, for: config.id)
        }

        onSave(config)
        dismiss()
    }

    // MARK: - Small helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AstralTheme.body(13))
            .foregroundStyle(AstralTheme.textSecondary)
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .font(AstralTheme.body(12))
            .foregroundStyle(AstralTheme.danger)
    }
}

// MARK: - Labeled field

/// A glass-styled labeled text field with an optional monospaced font and
/// an invalid state that draws a danger border.
private struct LabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var mono: Bool = false
    var invalid: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textSecondary)
            TextField(placeholder, text: $text)
                .font(mono ? AstralTheme.mono(13) : AstralTheme.body(15))
                .textFieldStyle(GlassTextFieldStyle())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .overlay(
                    RoundedRectangle(cornerRadius: AstralTheme.Radius.medium, style: .continuous)
                        .stroke(invalid ? AstralTheme.danger : Color.clear, lineWidth: 1))
        }
    }
}
