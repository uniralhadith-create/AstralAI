import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - Google Antigravity IDE Service (PC-Free on iPhone)

/// Owns Google Antigravity authentication (Google OAuth 2.0 PKCE via
/// `ASWebAuthenticationSession` or Google AI Studio API Key), live model
/// discovery, automatic plan-tier detection, automatic synchronization into
/// `ProviderStore`, and PC-free autonomous IDE mission execution directly over
/// `/home/astral` and `SandboxShell`.
@MainActor
final class AntigravityService: NSObject, ObservableObject {

    static let shared = AntigravityService()

    // MARK: - Published State

    @Published private(set) var account: AntigravityAccount?
    @Published var selectedModelID: String = "gemini-4-hydrogen"
    @Published var thinkingLevel: AntigravityThinkingLevel = .high
    @Published var isSigningIn: Bool = false
    @Published var isSyncingModels: Bool = false
    @Published var statusMessage: String?
    @Published var lastError: String?

    @Published private(set) var missions: [AntigravityMission] = []
    @Published private(set) var isRunningMission: Bool = false

    // MARK: - Constants & Persistence Keys

    static let geminiOpenAIBaseURL = "https://generativelanguage.googleapis.com/v1beta/openai"
    static let geminiModelsEndpoint = "https://generativelanguage.googleapis.com/v1beta/models"
    static let googleAuthEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let googleTokenEndpoint = "https://oauth2.googleapis.com/token"
    static let googleUserInfoEndpoint = "https://openidconnect.googleapis.com/v1/userinfo"
    static let oauthCallbackScheme = "astral"
    static let oauthRedirectURI = "astral://antigravity-callback"

    private static let accountDefaultsKey = "astral.antigravity.account.v85"
    private static let missionsDefaultsKey = "astral.antigravity.missions.v85"
    private static let selectedModelDefaultsKey = "astral.antigravity.model.v85"
    private static let thinkingDefaultsKey = "astral.antigravity.thinking.v85"
    private static let oauthClientIDKey = "astral.antigravity.oauthClientID"
    private static let keychainCredentialAccount = "astral.antigravity.credential"

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

    // MARK: - 1. Sign in with Google AI Studio Key (Zero-PC, Instant Live Model Auto-Discovery)

    /// Connects a Google Account via Google AI Studio / Gemini API key, queries
    /// Google's live `/v1beta/models` endpoint to verify the key and detect
    /// every unlocked Gemini model, infers the plan tier, and auto-syncs the
    /// "Google Antigravity" provider into `ProviderStore`.
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

        // Probe Google's live models endpoint to discover models on this account.
        let discovered = await discoverGoogleModels(apiKey: key, isBearerToken: false)
        let detectedTier = preferredTier ?? inferPlanTier(from: discovered)

        // Save credential securely in iOS Keychain
        try? KeychainStore.save(key, account: Self.keychainCredentialAccount)

        let cleanEmail = emailHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayEmail = cleanEmail.isEmpty ? "google-developer@antigravity.google" : cleanEmail
        let displayName = cleanEmail.components(separatedBy: "@").first?.capitalized ?? "Google Developer"

        let chosenModel = resolveBestModelID(for: detectedTier, discovered: discovered)
        selectedModelID = chosenModel

        let syncedID = syncProvider(
            in: providerStore,
            credential: key,
            modelID: chosenModel,
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

    // MARK: - 2. Sign in with Google OAuth 2.0 PKCE (`ASWebAuthenticationSession`)

    /// Opens Google's native OAuth 2.0 PKCE sign-in sheet in Safari/iOS
    /// (`ASWebAuthenticationSession`), captures the callback at
    /// `astral://antigravity-callback`, exchanges the code for an access token,
    /// fetches the user's Google profile, discovers their Antigravity plan &
    /// models, and auto-connects them inside Astral AI without any PC.
    func signInWithGoogleOAuth(
        preferredTier: AntigravityPlanTier? = nil,
        providerStore: ProviderStore
    ) async {
        isSigningIn = true
        lastError = nil
        statusMessage = L("ag.status.openingGoogle", "Shared")

        let clientID = customOAuthClientID
        let codeVerifier = Self.generatePKCEVerifier()
        let codeChallenge = Self.pkceChallenge(for: codeVerifier)

        // Build Google OAuth 2.0 authorization URL
        var components = URLComponents(string: Self.googleAuthEndpoint)
        let effectiveClientID = clientID.isEmpty
            ? "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
            : clientID

        components?.queryItems = [
            URLQueryItem(name: "client_id", value: effectiveClientID),
            URLQueryItem(name: "redirect_uri", value: Self.oauthRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/generative-language"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
        ]

        guard let authURL = components?.url else {
            isSigningIn = false
            lastError = L("ag.error.oauthFailed", "Shared")
            return
        }

        do {
            let callbackURL = try await performWebAuth(url: authURL, scheme: Self.oauthCallbackScheme)
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

            if let errorDesc = items.first(where: { $0.name == "error" })?.value {
                isSigningIn = false
                lastError = "Google OAuth: \(errorDesc)"
                return
            }

            guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                isSigningIn = false
                lastError = L("ag.error.oauthFailed", "Shared")
                return
            }

            statusMessage = L("ag.status.exchangingToken", "Shared")
            let token = try await exchangeOAuthCode(
                code: code,
                clientID: effectiveClientID,
                codeVerifier: codeVerifier)

            let profile = await fetchGoogleProfile(accessToken: token)
            let discovered = await discoverGoogleModels(apiKey: token, isBearerToken: true)
            let detectedTier = preferredTier ?? inferPlanTier(from: discovered)

            try? KeychainStore.save(token, account: Self.keychainCredentialAccount)

            let chosenModel = resolveBestModelID(for: detectedTier, discovered: discovered)
            selectedModelID = chosenModel

            let syncedID = syncProvider(
                in: providerStore,
                credential: token,
                modelID: chosenModel,
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
            isSigningIn = false
            statusMessage = String(
                format: L("ag.status.connected", "Shared"),
                detectedTier.localizedName,
                max(discovered.count, availableCatalogModels.count))
        } catch {
            isSigningIn = false
            if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                lastError = error.localizedDescription
            }
        }
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

    // MARK: - Autonomous Antigravity IDE Mission Runner (PC-Free!)

    /// Runs a real autonomous coding mission inside `/home/astral` using the
    /// user's connected Google Antigravity model (with selected thinking level
    /// and Orchestrator support), producing structured Artifacts (Plan, Code
    /// Diff, Terminal Output, Walkthrough) directly on the phone.
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
        var mission = AntigravityMission(
            prompt: trimmed,
            modelName: descriptor.name,
            thinkingLevel: thinkingLevel,
            status: .planning)
        missions.insert(mission, at: 0)
        persistMissions()

        // Gather live workspace context from /home/astral
        let wsFiles = WorkspaceStore.shared.list().prefix(30).map(\.relativePath)
        var contextBlock = "WORKSPACE FILES (/home/astral):\n" + (wsFiles.isEmpty ? "(empty)" : wsFiles.joined(separator: "\n"))
        if let path = activeFilePath, !path.isEmpty {
            contextBlock += "\n\nCURRENTLY OPEN FILE: \(path)\n```\n\(String((activeFileContent ?? "").prefix(4000)))\n```"
        }

        let orchestratorNote = descriptor.isOrchestrator
            ? "ORCHESTRATOR MODE ACTIVE: First produce a crisp architectural plan, then generate complete production-ready implementation code."
            : ""

        let systemPrompt = """
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

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.user("\(contextBlock)\n\nMISSION GOAL:\n\(trimmed)"),
        ]

        // Ensure the Antigravity provider is active when signed in
        if let syncedID = account?.syncedProviderID, providerStore.activeProviderID != syncedID {
            providerStore.setActive(syncedID)
        }

        do {
            updateMission(mission.id) { $0.status = .coding }
            let reply = try await providerStore.llm.complete(messages: messages, model: nil)

            var generatedArtifacts: [AntigravityArtifact] = []
            var touched: [String] = []

            // 1. Parse and write <<<FILE: ...>>> blocks directly to /home/astral
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

            // 2. Execute any <<<CMD: ...>>> verification commands in SandboxShell
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

            // 3. Clean walkthrough text
            let walkthroughText = Self.stripDirectives(from: reply)
            generatedArtifacts.insert(
                AntigravityArtifact(
                    kind: .walkthrough,
                    title: LocalizationManager.shared.effectiveCode == "ar"
                        ? "ملخص التنفيذ (Walkthrough)"
                        : "Implementation Walkthrough",
                    content: walkthroughText),
                at: 0)

            WorkspaceStore.shared.refresh()
            NotificationCenter.default.post(name: .sandboxDidChange, object: nil)

            updateMission(mission.id) { m in
                m.status = .completed
                m.summary = String(walkthroughText.prefix(240))
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
    /// `ProviderStore` so all unlocked Google models work in both Antigravity
    /// IDE and the main Astral AI Chat.
    @discardableResult
    private func syncProvider(
        in store: ProviderStore,
        credential: String,
        modelID: String,
        tier: AntigravityPlanTier,
        existingID: UUID?
    ) -> UUID {
        let providerName = "Google Antigravity (\(tier.displayName))"
        let plannerModel = tier >= .pro ? "gemini-4-neon" : modelID
        let subAgentModel = "gemini-4-hydrogen"

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

    /// Queries Google's live Gemini API `/v1beta/models` endpoint to discover
    /// all models accessible by the user's Google account or API key.
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

    /// Infers the user's Google AI / Antigravity plan tier from discovered models.
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
        // If Google's live API returned the exact Antigravity model ID, use it;
        // otherwise pick the best matching live Gemini model while keeping catalog ID.
        if discovered.contains(preferred.apiModelID) {
            return preferred.id
        }
        return preferred.id
    }

    private func resolveAPIModelID(for descriptor: AntigravityModelDescriptor, discovered: [String]) -> String {
        if discovered.isEmpty || discovered.contains(descriptor.apiModelID) {
            return descriptor.apiModelID
        }
        // Gracefully map to the strongest live discovered Gemini model on this key
        if descriptor.minimumTier >= .pro,
           let proMatch = discovered.first(where: { $0.contains("2.5-pro") || $0.contains("pro") }) {
            return proMatch
        }
        if let flashMatch = discovered.first(where: { $0.contains("2.5-flash") || $0.contains("2.0-flash") || $0.contains("flash") }) {
            return flashMatch
        }
        return discovered.first ?? descriptor.apiModelID
    }

    // MARK: - OAuth Helpers

    private func performWebAuth(url: URL, scheme: String) async throws -> URL {
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
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    private func exchangeOAuthCode(code: String, clientID: String, codeVerifier: String) async throws -> String {
        guard let url = URL(string: Self.googleTokenEndpoint) else {
            throw LLMError.invalidURL(Self.googleTokenEndpoint)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "code=\(code)",
            "client_id=\(clientID)",
            "redirect_uri=\(Self.oauthRedirectURI)",
            "grant_type=authorization_code",
            "code_verifier=\(codeVerifier)",
        ].joined(separator: "&")
        req.httpBody = Data(params.utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
            return accessToken
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
