import Foundation
import SwiftUI

// MARK: - Connector & MCP Store

/// Central registry for all external Plugins, Connectors, and MCP (Model Context
/// Protocol) servers. Non-secret metadata lives in `UserDefaults`; every API key
/// or bearer token is stored securely in iOS `KeychainStore`.
@MainActor
final class ConnectorStore: ObservableObject {

    static let shared = ConnectorStore()

    @Published private(set) var enabledKinds: Set<ConnectorKind> = []
    @Published private(set) var secondaryValues: [ConnectorKind: String] = [:]
    @Published private(set) var mcpServers: [MCPServerConfig] = []
    @Published var statusNote: String?

    private static let enabledDefaultsKey = "astral.connectors.enabled.v90"
    private static let secondaryDefaultsKey = "astral.connectors.secondary.v90"
    private static let mcpServersDefaultsKey = "astral.connectors.mcpServers.v90"
    private static let telegramSeededKey = "astral.connectors.telegramSeeded.v90"
    private static let defaultSeedTelegramToken = "9110669238:AAE5p0Ok4eUxJeQOHxu_Ib3_ZawJhXE9Pt4"

    private init() {
        load()
        seedDefaultTelegramIfNeeded()
    }

    // MARK: - Keychain Helpers

    private func tokenAccount(for kind: ConnectorKind) -> String {
        "astral.connector.token.\(kind.rawValue)"
    }

    private func mcpTokenAccount(for id: UUID) -> String {
        "astral.connector.mcp.token.\(id.uuidString)"
    }

    func token(for kind: ConnectorKind) -> String {
        (try? KeychainStore.get(account: tokenAccount(for: kind))) ?? ""
    }

    func setToken(_ value: String, for kind: ConnectorKind) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? KeychainStore.delete(account: tokenAccount(for: kind))
        } else {
            try? KeychainStore.save(trimmed, account: tokenAccount(for: kind))
        }
        objectWillChange.send()
    }

    func secondaryValue(for kind: ConnectorKind) -> String {
        secondaryValues[kind] ?? ""
    }

    func setSecondaryValue(_ value: String, for kind: ConnectorKind) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secondaryValues.removeValue(forKey: kind)
        } else {
            secondaryValues[kind] = trimmed
        }
        persist()
    }

    func isEnabled(_ kind: ConnectorKind) -> Bool {
        enabledKinds.contains(kind)
    }

    func isConfigured(_ kind: ConnectorKind) -> Bool {
        if kind == .mcp {
            return !mcpServers.filter(\.isEnabled).isEmpty || !secondaryValue(for: .mcp).isEmpty
        }
        if !kind.requiresToken {
            return !secondaryValue(for: kind).isEmpty
        }
        return !token(for: kind).isEmpty
    }

    func isActive(_ kind: ConnectorKind) -> Bool {
        isEnabled(kind) && isConfigured(kind)
    }

    var activeCount: Int {
        ConnectorKind.allCases.filter { isActive($0) }.count
    }

    func setEnabled(_ enabled: Bool, for kind: ConnectorKind) {
        if enabled {
            enabledKinds.insert(kind)
        } else {
            enabledKinds.remove(kind)
        }
        persist()
    }

    // MARK: - MCP Server Management

    func mcpToken(for serverID: UUID) -> String {
        (try? KeychainStore.get(account: mcpTokenAccount(for: serverID))) ?? ""
    }

    func addMCPServer(name: String, endpointURL: String, bearerToken: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }
        let server = MCPServerConfig(
            name: cleanName.isEmpty ? (URL(string: cleanURL)?.host ?? "MCP Server") : cleanName,
            endpointURL: cleanURL,
            isEnabled: true)
        mcpServers.append(server)
        let trimmedTok = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTok.isEmpty {
            try? KeychainStore.save(trimmedTok, account: mcpTokenAccount(for: server.id))
        }
        enabledKinds.insert(.mcp)
        persist()
    }

    func toggleMCPServer(_ id: UUID) {
        guard let idx = mcpServers.firstIndex(where: { $0.id == id }) else { return }
        mcpServers[idx].isEnabled.toggle()
        persist()
    }

    func deleteMCPServer(_ id: UUID) {
        mcpServers.removeAll { $0.id == id }
        try? KeychainStore.delete(account: mcpTokenAccount(for: id))
        persist()
    }

    func refreshMCPTools(for serverID: UUID) async -> Result<[MCPDiscoveredTool], Error> {
        guard let idx = mcpServers.firstIndex(where: { $0.id == serverID }) else {
            return .failure(LLMError.badResponse("MCP server not found"))
        }
        let server = mcpServers[idx]
        let tok = mcpToken(for: serverID)
        do {
            let tools = try await MCPClient.listTools(endpointURL: server.endpointURL, bearerToken: tok.isEmpty ? nil : tok)
            mcpServers[idx].discoveredTools = tools
            persist()
            return .success(tools)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Live Connection Tester

    func testConnection(for kind: ConnectorKind) async -> (ok: Bool, message: String) {
        let ar = LocalizationManager.shared.effectiveCode == "ar"
        let tok = token(for: kind)
        let sec = secondaryValue(for: kind)

        do {
            switch kind {
            case .github:
                guard !tok.isEmpty else { return (false, ar ? "أدخل GitHub Token أولاً" : "Enter a GitHub Token first") }
                var req = URLRequest(url: URL(string: "https://api.github.com/user")!)
                req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 15
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let login = json["login"] as? String else {
                    return (false, ar ? "فشل التحقق من GitHub Token" : "GitHub token verification failed")
                }
                return (true, ar ? "متصل بنجاح بحساب @\(login)" : "Connected as @\(login)")

            case .telegram:
                guard !tok.isEmpty else { return (false, ar ? "أدخل Telegram Bot Token أولاً" : "Enter a Telegram Bot Token first") }
                let bot = try await TelegramAgentService.shared.verifyBot(token: tok)
                return (true, ar ? "البوت متصل بنجاح: @\(bot.username)" : "Connected to @\(bot.username)")

            case .notion:
                guard !tok.isEmpty else { return (false, ar ? "أدخل Notion Secret أولاً" : "Enter Notion secret first") }
                var req = URLRequest(url: URL(string: "https://api.notion.com/v1/users/me")!)
                req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
                req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
                req.timeoutInterval = 15
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return (true, ar ? "تم الاتصال بـ Notion بنجاح" : "Connected to Notion")
                }
                return (false, ar ? "توكن Notion غير صالح" : "Invalid Notion token")

            case .slack:
                guard !tok.isEmpty else { return (false, ar ? "أدخل Slack Bot Token أولاً" : "Enter Slack Bot Token first") }
                var req = URLRequest(url: URL(string: "https://slack.com/api/auth.test")!)
                req.httpMethod = "POST"
                req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: req)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (json["ok"] as? Bool) == true {
                    let team = (json["team"] as? String) ?? "Slack"
                    return (true, ar ? "متصل بمساحة \(team)" : "Connected to \(team)")
                }
                return (false, ar ? "فشل الاتصال بـ Slack" : "Slack authentication failed")

            case .mcp:
                let url = sec.isEmpty ? (mcpServers.first?.endpointURL ?? "") : sec
                guard !url.isEmpty else { return (false, ar ? "أضف رابط خادم MCP أولاً" : "Add an MCP server URL first") }
                let tools = try await MCPClient.listTools(endpointURL: url, bearerToken: tok.isEmpty ? nil : tok)
                return (true, ar ? "متصل بـ MCP — تم اكتشاف \(tools.count) أداة" : "Connected to MCP — discovered \(tools.count) tools")

            default:
                if isConfigured(kind) {
                    return (true, ar ? "الإعدادات محفوظة وجاهزة لاستخدام الوكيل" : "Configuration saved & ready for Agent")
                }
                return (false, ar ? "يرجى إدخال البيانات المطلوبة أولاً" : "Please enter required credentials first")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Persistence

    private func seedDefaultTelegramIfNeeded() {
        if !UserDefaults.standard.bool(forKey: Self.telegramSeededKey) {
            if token(for: .telegram).isEmpty {
                setToken(Self.defaultSeedTelegramToken, for: .telegram)
                enabledKinds.insert(.telegram)
                persist()
            }
            UserDefaults.standard.set(true, forKey: Self.telegramSeededKey)
        }
    }

    private func load() {
        if let raw = UserDefaults.standard.array(forKey: Self.enabledDefaultsKey) as? [String] {
            enabledKinds = Set(raw.compactMap(ConnectorKind.init(rawValue:)))
        }
        if let dict = UserDefaults.standard.dictionary(forKey: Self.secondaryDefaultsKey) as? [String: String] {
            var map: [ConnectorKind: String] = [:]
            for (k, v) in dict {
                if let kind = ConnectorKind(rawValue: k) {
                    map[kind] = v
                }
            }
            secondaryValues = map
        }
        if let data = UserDefaults.standard.data(forKey: Self.mcpServersDefaultsKey),
           let decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) {
            mcpServers = decoded
        }
    }

    private func persist() {
        UserDefaults.standard.set(enabledKinds.map(\.rawValue), forKey: Self.enabledDefaultsKey)
        var dict: [String: String] = [:]
        for (k, v) in secondaryValues { dict[k.rawValue] = v }
        UserDefaults.standard.set(dict, forKey: Self.secondaryDefaultsKey)
        if let data = try? JSONEncoder().encode(mcpServers) {
            UserDefaults.standard.set(data, forKey: Self.mcpServersDefaultsKey)
        }
    }
}

// MARK: - MCP JSON-RPC 2.0 Streamable HTTP Client

enum MCPClient {

    static func listTools(endpointURL: String, bearerToken: String?) async throws -> [MCPDiscoveredTool] {
        let result = try await sendJSONRPC(
            endpointURL: endpointURL,
            bearerToken: bearerToken,
            method: "tools/list",
            params: [:])
        guard let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }
        return toolsArray.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let desc = (item["description"] as? String) ?? ""
            return MCPDiscoveredTool(name: name, description: desc)
        }
    }

    static func callTool(
        endpointURL: String,
        bearerToken: String?,
        toolName: String,
        arguments: [String: Any]
    ) async throws -> String {
        let result = try await sendJSONRPC(
            endpointURL: endpointURL,
            bearerToken: bearerToken,
            method: "tools/call",
            params: [
                "name": toolName,
                "arguments": arguments,
            ])

        if let content = result["content"] as? [[String: Any]] {
            let texts = content.compactMap { block -> String? in
                if let text = block["text"] as? String { return text }
                if let data = try? JSONSerialization.data(withJSONObject: block),
                   let str = String(data: data, encoding: .utf8) {
                    return str
                }
                return nil
            }
            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "OK"
    }

    private static func sendJSONRPC(
        endpointURL: String,
        bearerToken: String?,
        method: String,
        params: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: endpointURL) else {
            throw LLMError.invalidURL(endpointURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let bearerToken, !bearerToken.isEmpty {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int.random(in: 1...999_999),
            "method": method,
            "params": params,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.badResponse("MCP HTTP \(http.statusCode): \(String(body.prefix(240)))")
        }

        // Parse either plain JSON or SSE (`data: {...}`)
        let jsonObj: [String: Any]?
        if let direct = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonObj = direct
        } else if let text = String(data: data, encoding: .utf8) {
            let dataLine = text.components(separatedBy: .newlines)
                .last(where: { $0.hasPrefix("data:") })?
                .dropFirst(5)
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let lineData = dataLine.data(using: .utf8) {
                jsonObj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            } else {
                jsonObj = nil
            }
        } else {
            jsonObj = nil
        }

        guard let jsonObj else {
            throw LLMError.badResponse("Invalid MCP JSON-RPC response")
        }
        if let err = jsonObj["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "MCP error"
            throw LLMError.badResponse(msg)
        }
        return (jsonObj["result"] as? [String: Any]) ?? jsonObj
    }
}
