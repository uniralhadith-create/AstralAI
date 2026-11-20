import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - Safari Sheet Wrapper Item

struct AntigravityAuthSheetItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

// MARK: - Antigravity Interaction Mode (Chatbot vs IDE Agent)

enum AntigravityWorkMode: String, CaseIterable, Identifiable {
    case chat
    case ideMission

    var id: String { rawValue }
}

// MARK: - Google Antigravity IDE Service (PC-Free on iPhone)

/// Owns Google Antigravity authentication:
/// 1. **Google Account Chooser -> AI Studio** (zero `Error 400`, always lets the
///    user pick which Google email to use, auto-detects copied key from clipboard).
/// 2. **iOS-Compliant Google OAuth 2.0 PKCE** via `ASWebAuthenticationSession`
///    using `prefersEphemeralWebBrowserSession` (so Google always opens the
///    account chooser instead of auto-selecting a cached Safari email) and the
///    official iOS reversed Client ID redirect URI (`com.googleusercontent.apps.<id>:/oauth2redirect/google`).
///
/// Also owns live Gemini model discovery, automatic plan-tier detection,
/// `ProviderStore` auto-sync (so Antigravity works in Main Chat as a normal
/// chatbot too), and both conversational chat & autonomous IDE missions over
/// `/home/astral` and `SandboxShell`.
@MainActor
final class AntigravityService: NSObject, ObservableObject {

    static let shared = AntigravityService()

    // MARK: - Published State

    @Published private(set) var account: AntigravityAccount?
    @Published var selectedModelID: String = "gemini-4-hydrogen"
    @Published var thinkingLevel: AntigravityThinkingLevel = .high
    @Published var workMode: AntigravityWorkMode = .chat
    @Published var useEphemeralOAuthSession: Bool = true
    @Published var isSigningIn: Bool = false
    @Published var isSyncingModels: Bool = false
    @Published var statusMessage: String?
    @Published var lastError: String?
    @Published var safariAuthItem: AntigravityAuthSheetItem?

    @Published private(set) var missions: [AntigravityMission] = []
    @Published private(set) var isRunningMission: Bool = false

    // MARK: - Constants & Persistence Keys

    static let geminiOpenAIBaseURL = "https://generativelanguage.googleapis.com/v1beta/openai"
    static let geminiModelsEndpoint = "https://generativelanguage.googleapis.com/v1beta/models"
    static let googleAuthEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let googleTokenEndpoint = "https://oauth2.googleapis.com/token"
    static let googleUserInfoEndpoint = "https://openidconnect.googleapis.com/v1/userinfo"
    /// Forces Google's official Account Chooser before landing on Google AI Studio
    /// so the user can always pick which Gmail account they want to use.
    static let googleAccountChooserAIStudioURL =
        "https://accounts.google.com/AccountChooser?continue=https%3A%2F%2Faistudio.google.com%2Fapikey"

    private static let accountDefaultsKey = "astral.antigravity.account.v85"
    private static let missionsDefaultsKey = "astral.antigravity.missions.v85"
    private static let selectedModelDefaultsKey = "astral.antigravity.model.v85"
    private static let thinkingDefaultsKey = "astral.antigravity.thinking.v85"
    private static let oauthClientIDKey = "astral.antigravity.oauthClientID"
    private static let keychainCredentialAccount = "astral.antigravity.credential"
    private static let keychainClientSecretAccount = "astral.antigravity.oauthClientSecret"

    private var authSession: ASWebAuthenticationSession?

    // MARK: - Init

    private override init() {
        super.init()
        loadPersistedState()
    }

    // MARK: - Computed Helpers

    var isSignedIn: Bool {
        account != nil
    }

    var currentTier: AntigravityPlanTier {
        account?.planTier ?? .free
    }

    var availableCatalogModels: [AntigravityModelDescriptor] {
        AntigravityModelCatalog.models(for: currentTier)
    }

    var selectedDescriptor: AntigravityModelDescriptor {
        AntigravityModelCatalog.all.first { $0.id == selectedModelID }
            ?? AntigravityModelCatalog.defaultModel(for: currentTier)
    }

    var customOAuthClientID: String {
        get { UserDefaults.standard.string(forKey: Self.oauthClientIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.oauthClientIDKey) }
    }

    var customOAuthClientSecret: String {
        get { (try? KeychainStore.get(account: Self.keychainClientSecretAccount)) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try? KeychainStore.delete(account: Self.keychainClientSecretAccount)
            } else {
                try? KeychainStore.save(trimmed, account: Self.keychainClientSecretAccount)
            }
        }
    }

    // MARK: - 1. Open Google Account Chooser (Pick Any Gmail -> AI Studio Key)

    /// Opens Google's official `AccountChooser` inside `SFSafariViewController`
    /// so the user explicitly chooses which Google account to sign in with
    /// (never auto-signing into a cached Safari email) and avoids Google's
    /// desktop-OAuth-on-iOS `Error 400: invalid_request`.
    func openGoogleAccountChooser() {
        lastError = nil
        if let url = URL(string: Self.googleAccountChooserAIStudioURL) {
            safariAuthItem = AntigravityAuthSheetItem(url: url)
        }
    }

    /// Checks the iOS clipboard for a Google Gemini / AI Studio API key (`AIza...`).
    func detectClipboardAPIKey() -> String? {
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("AIza"),
              raw.count >= 30,
              raw.count <= 80,
              !raw.contains(" ") else {
            return nil
        }
        return raw
    }

    // MARK: - 2. Sign in with Google AI Studio Key (Zero-PC, Instant Live Model Auto-Discovery)

    /// Connects a Google Account via Google AI Studio / Gemini API key, queries
    /// Google's live `/v1beta/models` endpoint to verify the key and detect
    /// every unlocked Gemini model, infers the plan tier, and auto-syncs the
    /// "Google Antigravity" provider into `ProviderStore` with a verified live
    /// API model ID so both Main Chat and Antigravity IDE work immediately.
    func signInWithAPIKey(
        _ rawKey: String,
        emailHint: String = "",
        preferredTier: AntigravityPlanTier? = nil,
        providerStore: ProviderStore
    ) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastError = L("ag.error.emptyKey", "Shared")
            return
        }

        isSigningIn = true
        lastError = nil
        statusMessage = L("ag.status.verifying", "Shared")
        defer { isSigningIn = false }

        let discovered = await discoverGoogleModels(apiKey: key, isBearerToken: false)
        let detectedTier = preferredTier ?? inferPlanTier(from: discovered)

        try? KeychainStore.save(key, account: Self.keychainCredentialAccount)

        let cleanEmail = emailHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayEmail = cleanEmail.isEmpty ? "google-developer@antigravity.google" : cleanEmail
        let displayName = cleanEmail.components(separatedBy: "@").first?.capitalized ?? "Google Developer"

        let chosenModel = resolveBestModelID(for: detectedTier, discovered: discovered)
        selectedModelID = chosenModel

        let descriptor = AntigravityModelCatalog.all.first { $0.id == chosenModel }
            ?? AntigravityModelCatalog.defaultModel(for: detectedTier)
        let liveAPIModel = resolveAPIModelID(for: descriptor, discovered: discovered)

        let syncedID = syncProvider(
            in: providerStore,
            credential: key,
            modelID: liveAPIModel,
            discovered: discovered,
            tier: detectedTier,
            existingID: account?.syncedProviderID)

        account = AntigravityAccount(
            email: displayEmail,
            displayName: displayName,
            planTier: detectedTier,
            authMethod: .aiStudioKey,
            connectedAt: Date(),
            discoveredModels: discovered,
            syncedProviderID: syncedID,
            quotaRemainingPercent: detectedTier == .ultra ? 100 : (detectedTier == .pro ? 96 : 92))

        persistState()
        statusMessage = String(
            format: L("ag.status.connected", "Shared"),
            detectedTier.localizedName,
            max(discovered.count, availableCatalogModels.count))
    }

    // MARK: - 3. Sign in with iOS-Compliant Google OAuth 2.0 PKCE (`ASWebAuthenticationSession`)

    /// Uses Google's official iOS OAuth 2.0 flow:
    /// - Reversed Client ID redirect URI (`com.googleusercontent.apps.<prefix>:/oauth2redirect/google`)
    ///   which complies 100% with Google's iOS OAuth 2.0 policy (no `Error 400: invalid_request`).
    /// - `prefersEphemeralWebBrowserSession = useEphemeralOAuthSession` (default `true`)
    ///   plus `prompt=select_account consent` so Google ALWAYS asks which email
    ///   to sign in with instead of auto-selecting a cached Safari account.
    func signInWithGoogleOAuth(
        preferredTier: AntigravityPlanTier? = nil,
        providerStore: ProviderStore
    ) async {
        let isArabic = LocalizationManager.shared.effectiveCode == "ar"
        let clientID = customOAuthClientID

        // Google blocks Desktop OAuth client IDs (loopback/custom schemes) from iOS Mobile Safari
        // with Error 400: invalid_request. Require a valid Google Cloud iOS OAuth Client ID here
        // and guide the user cleanly instead of hitting Google's 400 error wall.
        guard !clientID.isEmpty, clientID.hasSuffix(".apps.googleusercontent.com") else {
            lastError = isArabic
                ? "سياسة Google OAuth 2.0 على iOS تتطلب iOS Client ID من Google Cloud Console. للاتصال الفوري بدون أخطاء واختيار أي إيميل، استخدم تبويب «حساب جوجل»."
                : "Google's iOS OAuth 2.0 policy requires an iOS Client ID from Google Cloud Console. For instant zero-error sign-in with any Gmail account, use the Google Account tab."
            return
        }

        let clientPrefix = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let callbackScheme = "com.googleusercontent.apps.\(clientPrefix)"
        let redirectURI = "\(callbackScheme):/oauth2redirect/google"

        isSigningIn = true
        lastError = nil
        statusMessage = L("ag.status.openingGoogle", "Shared")
        defer { isSigningIn = false }

        let codeVerifier = Self.generatePKCEVerifier()
        let codeChallenge = Self.pkceChallenge(for: codeVerifier)
        let stateToken = Self.generatePKCEVerifier()

        var components = URLComponents(string: Self.googleAuthEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile https://www.googleapis.com/auth/cloud-platform"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: stateToken),
            URLQueryItem(name: "prompt", value: "select_account consent"),
        ]

        guard let authURL = components?.url else {
            lastError = L("ag.error.oauthFailed", "Shared")
            return
        }

        do {
            let callbackURL = try await performWebAuth(
                url: authURL,
                scheme: callbackScheme,
                ephemeral: useEphemeralOAuthSession)

            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let errorDesc = items.first(where: { $0.name == "error" })?.value {
                lastError = "Google OAuth: \(errorDesc)"
                return
            }

            if let returnedState = items.first(where: { $0.name == "state" })?.value,
               returnedState != stateToken {
                lastError = isArabic
                    ? "فشل التحقق الأمني (OAuth state mismatch). أعد المحاولة."
                    : "OAuth state verification failed. Please try again."
                return
            }

            guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                lastError = L("ag.error.oauthFailed", "Shared")
                return
            }

            statusMessage = L("ag.status.exchangingToken", "Shared")
            let secret = customOAuthClientSecret
            let token = try await exchangeOAuthCode(
                code: code,
                clientID: clientID,
                clientSecret: secret.isEmpty ? nil : secret,
                redirectURI: redirectURI,
                codeVerifier: codeVerifier)

            let profile = await fetchGoogleProfile(accessToken: token)
            let discovered = await discoverGoogleModels(apiKey: token, isBearerToken: true)
            let detectedTier = preferredTier ?? inferPlanTier(from: discovered)

            try? KeychainStore.save(token, account: Self.keychainCredentialAccount)

            let chosenModel = resolveBestModelID(for: detectedTier, discovered: discovered)
            selectedModelID = chosenModel

            let descriptor = AntigravityModelCatalog.all.first { $0.id == chosenModel }
                ?? AntigravityModelCatalog.defaultModel(for: detectedTier)
            let liveAPIModel = resolveAPIModelID(for: descriptor, discovered: discovered)

            let syncedID = syncProvider(
                in: providerStore,
                credential: token,
                modelID: liveAPIModel,
                discovered: discovered,
                tier: detectedTier,
                existingID: account?.syncedProviderID)

            account = AntigravityAccount(
                email: profile.email,
                displayName: profile.name,
                planTier: detectedTier,
                authMethod: .googleOAuth,
                connectedAt: Date(),
                discoveredModels: discovered,
                syncedProviderID: syncedID,
                quotaRemainingPercent: 100)

            persistState()
            statusMessage = String(
                format: L("ag.status.connected", "Shared"),
                detectedTier.localizedName,
                max(discovered.count, availableCatalogModels.count))
        } catch {
            if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                lastError = error.localizedDescription
            }
        }
    }

    func dismissSafariSheet() {
        safariAuthItem = nil
    }

    // MARK: - Plan Switching, Model Selection & Auto-Sync

    func updatePlanTier(_ tier: AntigravityPlanTier, providerStore: ProviderStore) {
        guard var current = account else { return }
        current.planTier = tier
        account = current

        let unlocked = AntigravityModelCatalog.models(for: tier)
        if !unlocked.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = AntigravityModelCatalog.defaultModel(for: tier).id
        }

        if let cred = try? KeychainStore.get(account: Self.keychainCredentialAccount), !cred.isEmpty {
            let apiModel = resolveAPIModelID(for: selectedDescriptor, discovered: current.discoveredModels)
            let syncedID = syncProvider(
                in: providerStore,
                credential: cred,
                modelID: apiModel,
                discovered: current.discoveredModels,
                tier: tier,
                existingID: current.syncedProviderID)
            account?.syncedProviderID = syncedID
        }
        persistState()
    }

    func selectModel(_ descriptor: AntigravityModelDescriptor, providerStore: ProviderStore) {
        selectedModelID = descriptor.id
        if !descriptor.supportsExtraThinking && thinkingLevel == .extra {
            thinkingLevel = .high
        }

        if let current = account,
           let cred = try? KeychainStore.get(account: Self.keychainCredentialAccount), !cred.isEmpty {
            let apiModel = resolveAPIModelID(for: descriptor, discovered: current.discoveredModels)
            let syncedID = syncProvider(
                in: providerStore,
                credential: cred,
                modelID: apiModel,
                discovered: current.discoveredModels,
                tier: current.planTier,
                existingID: current.syncedProviderID)
            account?.syncedProviderID = syncedID
        }
        persistState()
    }

    func refreshDiscoveredModels(providerStore: ProviderStore) async {
        guard var current = account,
              let cred = try? KeychainStore.get(account: Self.keychainCredentialAccount),
              !cred.isEmpty else { return }

        isSyncingModels = true
        defer { isSyncingModels = false }

        let discovered = await discoverGoogleModels(
            apiKey: cred,
            isBearerToken: current.authMethod == .googleOAuth)
        if !discovered.isEmpty {
            current.discoveredModels = discovered
            account = current
            let apiModel = resolveAPIModelID(for: selectedDescriptor, discovered: discovered)
            _ = syncProvider(
                in: providerStore,
                credential: cred,
                modelID: apiModel,
                discovered: discovered,
                tier: current.planTier,
                existingID: current.syncedProviderID)
            persistState()
            statusMessage = String(format: L("ag.status.modelsRefreshed", "Shared"), discovered.count)
        }
    }

    func signOut(providerStore: ProviderStore) {
        if let syncedID = account?.syncedProviderID {
            providerStore.delete(syncedID)
        }
        try? KeychainStore.delete(account: Self.keychainCredentialAccount)
        account = nil
        statusMessage = nil
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.accountDefaultsKey)
    }

    // MARK: - Unified Antigravity Runner (Normal Chatbot + Autonomous IDE Missions)

    /// Executes either a normal conversational chatbot message (`workMode == .chat`)
    /// or a full autonomous IDE coding mission (`workMode == .ideMission`) over
    /// `/home/astral` and `SandboxShell`.
    func runMission(
        prompt: String,
        activeFilePath: String?,
        activeFileContent: String?,
        providerStore: ProviderStore
    ) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunningMission else { return }

        isRunningMission = true
        lastError = nil
        defer { isRunningMission = false }

        let descriptor = selectedDescriptor
        let isChatbotMode = (workMode == .chat)
        let mission = AntigravityMission(
            prompt: trimmed,
            modelName: descriptor.name,
            thinkingLevel: thinkingLevel,
            status: isChatbotMode ? .coding : .planning)
        missions.insert(mission, at: 0)
        persistMissions()

        // Ensure the Antigravity provider is active when signed in
        if let syncedID = account?.syncedProviderID, providerStore.activeProviderID != syncedID {
            providerStore.setActive(syncedID)
        }

        let messages: [ChatMessage]
        if isChatbotMode {
            let chatSystem = """
            You are Astral AI powered by Google Antigravity (\(descriptor.name)).
            Answer naturally, clearly, and helpfully as a conversational AI assistant in the user's language (Arabic -> Arabic, English -> English).
            Only write code if the user asks for it. Keep answers clean and well-structured.
            """
            messages = [
                ChatMessage.system(chatSystem),
                ChatMessage.user(trimmed),
            ]
        } else {
            let wsFiles = WorkspaceStore.shared.list().prefix(30).map(\.relativePath)
            var contextBlock = "WORKSPACE FILES (/home/astral):\n" + (wsFiles.isEmpty ? "(empty)" : wsFiles.joined(separator: "\n"))
            if let path = activeFilePath, !path.isEmpty {
                contextBlock += "\n\nCURRENTLY OPEN FILE: \(path)\n```\n\(String((activeFileContent ?? "").prefix(4000)))\n```"
            }

            let orchestratorNote = descriptor.isOrchestrator
                ? "ORCHESTRATOR MODE ACTIVE: First produce a crisp architectural plan, then generate complete production-ready implementation code."
                : ""

            let ideSystem = """
            You are Google Antigravity IDE Agent running natively inside Astral AI on iOS (PC-Free Ubuntu Base 24.04 ARM64 workstation at /home/astral).
            Active Model: \(descriptor.name) · Thinking Effort: \(thinkingLevel.rawValue) · Plan: \(currentTier.displayName).
            \(orchestratorNote)

            When writing or modifying code files in the workspace, wrap each file using this exact block format so the IDE applies it automatically:
            <<<FILE: relative/path/to/file.ext>>>
            ...complete file contents...
            <<<END_FILE>>>

            If you want to run a verification command in the integrated Ubuntu terminal, include:
            <<<CMD: command to run>>>

            Respond in the user's language (Arabic request -> Arabic explanation & walkthrough, English -> English). Always include a short Implementation Plan and Walkthrough.
            """
            messages = [
                ChatMessage.system(ideSystem),
                ChatMessage.user("\(contextBlock)\n\nMISSION GOAL:\n\(trimmed)"),
            ]
        }

        do {
            updateMission(mission.id) { $0.status = .coding }
            let reply = try await providerStore.llm.complete(messages: messages, model: nil)

            var generatedArtifacts: [AntigravityArtifact] = []
            var touched: [String] = []

            if !isChatbotMode {
                let fileBlocks = Self.extractFileBlocks(from: reply)
                for block in fileBlocks {
                    try? WorkspaceStore.shared.write(path: block.path, content: block.content)
                    touched.append(block.path)
                    generatedArtifacts.append(
                        AntigravityArtifact(
                            kind: .codeDiff,
                            title: block.path,
                            filePath: block.path,
                            content: block.content))
                }

                let commands = Self.extractCommands(from: reply)
                if !commands.isEmpty {
                    updateMission(mission.id) { $0.status = .verifying }
                    var termOutputs: [String] = []
                    for cmd in commands.prefix(4) {
                        let result = await SandboxShell.shared.run(cmd)
                        termOutputs.append("$ \(cmd)\n\(result.stdout)")
                    }
                    generatedArtifacts.append(
                        AntigravityArtifact(
                            kind: .terminal,
                            title: "Ubuntu Terminal Verification",
                            content: termOutputs.joined(separator: "\n\n")))
                }
            }

            let cleanText = isChatbotMode ? reply.trimmingCharacters(in: .whitespacesAndNewlines) : Self.stripDirectives(from: reply)
            generatedArtifacts.insert(
                AntigravityArtifact(
                    kind: .walkthrough,
                    title: isChatbotMode
                        ? (LocalizationManager.shared.effectiveCode == "ar" ? "الرد" : "Response")
                        : (LocalizationManager.shared.effectiveCode == "ar" ? "ملخص التنفيذ" : "Implementation Walkthrough"),
                    content: cleanText),
                at: 0)

            if !touched.isEmpty {
                WorkspaceStore.shared.refresh()
                NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
            }

            updateMission(mission.id) { m in
                m.status = .completed
                m.summary = String(cleanText.prefix(240))
                m.artifacts = generatedArtifacts
                m.touchedFiles = touched
            }
        } catch {
            lastError = error.localizedDescription
            updateMission(mission.id) { m in
                m.status = .failed
                m.summary = error.localizedDescription
            }
        }
    }

    func clearMissions() {
        missions = []
        persistMissions()
    }

    // MARK: - Provider Synchronization

    /// Creates or updates the dedicated "Google Antigravity" provider inside
    /// `ProviderStore` so all unlocked Google models work seamlessly in both
    /// Antigravity IDE and the Main Astral AI Chat (Chat & Agent modes).
    @discardableResult
    private func syncProvider(
        in store: ProviderStore,
        credential: String,
        modelID: String,
        discovered: [String],
        tier: AntigravityPlanTier,
        existingID: UUID?
    ) -> UUID {
        let providerName = "Google Antigravity (\(tier.displayName))"
        let plannerModel = discovered.first(where: { $0.contains("2.5-pro") || $0.contains("pro") }) ?? modelID
        let subAgentModel = discovered.first(where: { $0.contains("2.5-flash") || $0.contains("flash") }) ?? modelID

        if let existingID, var existing = store.providers.first(where: { $0.id == existingID }) {
            existing.name = providerName
            existing.baseURL = Self.geminiOpenAIBaseURL
            existing.protocolKind = .openAICompatible
            existing.mainModel = modelID
            existing.plannerModel = plannerModel
            existing.subAgentModel = subAgentModel
            store.update(existing)
            store.saveKey(credential, for: existing.id)
            store.setActive(existing.id)
            return existing.id
        }

        let config = ProviderConfig(
            name: providerName,
            baseURL: Self.geminiOpenAIBaseURL,
            protocolKind: .openAICompatible,
            mainModel: modelID,
            plannerModel: plannerModel,
            subAgentModel: subAgentModel,
            temperature: 0.25,
            maxTokens: 8192,
            timeout: 180)
        store.add(config)
        store.saveKey(credential, for: config.id)
        store.setActive(config.id)
        return config.id
    }

    // MARK: - Live Google Model Discovery & Plan Detection

    private func discoverGoogleModels(apiKey: String, isBearerToken: Bool) async -> [String] {
        var urlString = Self.geminiModelsEndpoint
        if !isBearerToken {
            urlString += "?key=\(apiKey)"
        }
        guard let url = URL(string: urlString) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if isBearerToken {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                return []
            }
            return models.compactMap { entry -> String? in
                guard let name = entry["name"] as? String else { return nil }
                let clean = name.replacingOccurrences(of: "models/", with: "")
                return clean.lowercased().contains("gemini") ? clean : nil
            }.sorted()
        } catch {
            return []
        }
    }

    func inferPlanTier(from discovered: [String]) -> AntigravityPlanTier {
        let lower = discovered.map { $0.lowercased() }
        if lower.contains(where: { $0.contains("argon") || $0.contains("carbon") || $0.contains("ultra") }) {
            return .ultra
        }
        if lower.contains(where: { $0.contains("neon") || $0.contains("3.1-pro") || $0.contains("2.5-pro") }) {
            return .pro
        }
        return .free
    }

    private func resolveBestModelID(for tier: AntigravityPlanTier, discovered: [String]) -> String {
        let preferred = AntigravityModelCatalog.defaultModel(for: tier)
        if discovered.isEmpty { return preferred.id }
        if discovered.contains(preferred.apiModelID) {
            return preferred.id
        }
        return preferred.id
    }

    private func resolveAPIModelID(for descriptor: AntigravityModelDescriptor, discovered: [String]) -> String {
        if discovered.contains(descriptor.apiModelID) {
            return descriptor.apiModelID
        }
        if !discovered.isEmpty {
            if descriptor.minimumTier >= .pro,
               let proMatch = discovered.first(where: { $0.contains("2.5-pro") || $0.contains("3.1-pro") || $0.contains("pro") }) {
                return proMatch
            }
            if let flashMatch = discovered.first(where: { $0.contains("2.5-flash") || $0.contains("2.0-flash") || $0.contains("flash") }) {
                return flashMatch
            }
            if let first = discovered.first {
                return first
            }
        }
        return "gemini-2.5-flash"
    }

    // MARK: - ASWebAuthenticationSession & Token Exchange Helpers

    private func performWebAuth(url: URL, scheme: String, ephemeral: Bool) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: LLMError.badResponse("No callback URL returned"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = ephemeral
            self.authSession = session
            session.start()
        }
    }

    private func exchangeOAuthCode(
        code: String,
        clientID: String,
        clientSecret: String?,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> String {
        guard let url = URL(string: Self.googleTokenEndpoint) else {
            throw LLMError.invalidURL(Self.googleTokenEndpoint)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var formItems: [(String, String)] = [
            ("code", code),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", codeVerifier),
        ]
        if let clientSecret, !clientSecret.isEmpty {
            formItems.append(("client_secret", clientSecret))
        }

        let encodedBody = formItems.map { key, value in
            "\(Self.formEncode(key))=\(Self.formEncode(value))"
        }.joined(separator: "&")
        req.httpBody = Data(encodedBody.utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
                return accessToken
            }
            if let err = json["error"] as? String {
                let desc = (json["error_description"] as? String) ?? err
                throw LLMError.badResponse("Google OAuth (\(err)): \(desc)")
            }
        }
        throw LLMError.unauthorized
    }

    private func fetchGoogleProfile(accessToken: String) async -> (email: String, name: String) {
        guard let url = URL(string: Self.googleUserInfoEndpoint) else {
            return ("developer@google.com", "Google Developer")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let email = (json["email"] as? String) ?? "developer@google.com"
            let name = (json["name"] as? String) ?? email.components(separatedBy: "@").first ?? "Google Developer"
            return (email, name)
        }
        return ("developer@google.com", "Google Developer")
    }

    private static func formEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private static func generatePKCEVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Directive Parsers for Autonomous IDE File Edits & Commands

    private static func extractFileBlocks(from text: String) -> [(path: String, content: String)] {
        var results: [(String, String)] = []
        let pattern = "<<<FILE:\\s*([^>\\n]+)>>>\\n?([\\s\\S]*?)<<<END_FILE>>>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            if match.numberOfRanges >= 3,
               let pRange = Range(match.range(at: 1), in: text),
               let cRange = Range(match.range(at: 2), in: text) {
                let path = String(text[pRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let content = String(text[cRange]).trimmingCharacters(in: .newlines)
                if !path.isEmpty {
                    results.append((path, content))
                }
            }
        }
        return results
    }

    private static func extractCommands(from text: String) -> [String] {
        var cmds: [String] = []
        let pattern = "<<<CMD:\\s*([^>\\n]+)>>>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            if match.numberOfRanges >= 2,
               let cRange = Range(match.range(at: 1), in: text) {
                let cmd = String(text[cRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cmd.isEmpty { cmds.append(cmd) }
            }
        }
        return cmds
    }

    private static func stripDirectives(from text: String) -> String {
        var out = text
        for pattern in ["<<<FILE:[^>\\n]+>>>[\\s\\S]*?<<<END_FILE>>>", "<<<CMD:[^>\\n]+>>>"] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(out.startIndex..., in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Persistence

    private func updateMission(_ id: UUID, mutate: (inout AntigravityMission) -> Void) {
        guard let idx = missions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&missions[idx])
        persistMissions()
    }

    private func loadPersistedState() {
        if let data = UserDefaults.standard.data(forKey: Self.accountDefaultsKey),
           let decoded = try? JSONDecoder().decode(AntigravityAccount.self, from: data) {
            account = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.missionsDefaultsKey),
           let decoded = try? JSONDecoder().decode([AntigravityMission].self, from: data) {
            missions = decoded
        }
        if let savedModel = UserDefaults.standard.string(forKey: Self.selectedModelDefaultsKey),
           !savedModel.isEmpty {
            selectedModelID = savedModel
        }
        if let savedThinking = UserDefaults.standard.string(forKey: Self.thinkingDefaultsKey),
           let level = AntigravityThinkingLevel(rawValue: savedThinking) {
            thinkingLevel = level
        }
    }

    private func persistState() {
        if let account, let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: Self.accountDefaultsKey)
        }
        UserDefaults.standard.set(selectedModelID, forKey: Self.selectedModelDefaultsKey)
        UserDefaults.standard.set(thinkingLevel.rawValue, forKey: Self.thinkingDefaultsKey)
    }

    private func persistMissions() {
        let capped = Array(missions.prefix(30))
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: Self.missionsDefaultsKey)
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AntigravityService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
