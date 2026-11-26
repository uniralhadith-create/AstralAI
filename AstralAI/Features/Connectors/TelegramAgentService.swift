import Foundation
import SwiftUI

// MARK: - Telegram Bot Models

public struct TelegramBotInfo: Equatable {
    public let id: Int64
    public let firstName: String
    public let username: String
}

public struct TelegramLogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let chatID: Int64
    public let senderName: String
    public let incomingText: String
    public let replyText: String?
    public let isError: Bool
}

// MARK: - Telegram Bot Agent Service (Live Polling & AI Auto-Reply)

/// Connects Astral AI directly to the official Telegram Bot API (`api.telegram.org`)
/// so the Agent can monitor incoming Telegram messages, reply automatically using
/// the active LLM provider, and send messages on demand via the `telegram_bot` tool.
@MainActor
final class TelegramAgentService: ObservableObject {

    static let shared = TelegramAgentService()

    @Published private(set) var botInfo: TelegramBotInfo?
    @Published private(set) var isPolling: Bool = false
    @Published var autoReplyEnabled: Bool = true
    @Published var allowedChatIDsText: String = ""
    @Published private(set) var logs: [TelegramLogEntry] = []
    @Published var lastError: String?

    private var pollingTask: Task<Void, Never>?
    private var lastUpdateID: Int64 = 0
    private var chatHistories: [Int64: [ChatMessage]] = [:]

    private init() {}

    // MARK: - Bot Verification (`getMe`)

    @discardableResult
    func verifyBot(token overrideToken: String? = nil) async throws -> TelegramBotInfo {
        let tok = (overrideToken ?? ConnectorStore.shared.token(for: .telegram))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tok.isEmpty else {
            throw LLMError.badResponse("Missing Telegram Bot Token")
        }
        guard let url = URL(string: "https://api.telegram.org/bot\(tok)/getMe") else {
            throw LLMError.invalidURL("api.telegram.org")
        }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["ok"] as? Bool) == true,
              let result = json["result"] as? [String: Any],
              let id = result["id"] as? Int64 else {
            throw LLMError.badResponse("Invalid Telegram Bot Token")
        }
        let info = TelegramBotInfo(
            id: id,
            firstName: (result["first_name"] as? String) ?? "Astral Bot",
            username: (result["username"] as? String) ?? "astral_bot")
        botInfo = info
        lastError = nil
        return info
    }

    // MARK: - Live Polling Loop (Auto-Reply Agent)

    func startAgentPolling() {
        guard !isPolling else { return }
        let tok = ConnectorStore.shared.token(for: .telegram).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tok.isEmpty else {
            lastError = LocalizationManager.shared.effectiveCode == "ar"
                ? "يرجى إدخال Telegram Bot Token أولاً"
                : "Please enter a Telegram Bot Token first"
            return
        }

        isPolling = true
        lastError = nil

        pollingTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.verifyBot(token: tok)
            } catch {
                self.lastError = error.localizedDescription
                self.isPolling = false
                return
            }

            while !Task.isCancelled && self.isPolling {
                await self.pollOnce(token: tok)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func stopAgentPolling() {
        isPolling = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollOnce(token: String) async {
        var urlStr = "https://api.telegram.org/bot\(token)/getUpdates?timeout=15&allowed_updates=%5B%22message%22%5D"
        if lastUpdateID > 0 {
            urlStr += "&offset=\(lastUpdateID + 1)"
        }
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 25

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["ok"] as? Bool) == true,
                  let updates = json["result"] as? [[String: Any]] else {
                return
            }

            for update in updates {
                if let uid = update["update_id"] as? Int64 {
                    lastUpdateID = max(lastUpdateID, uid)
                }
                guard let message = update["message"] as? [String: Any],
                      let chat = message["chat"] as? [String: Any],
                      let chatID = chat["id"] as? Int64,
                      let text = message["text"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                // Respect optional Allowed Chat IDs filter
                let allowedSet = parsedAllowedChatIDs()
                if !allowedSet.isEmpty && !allowedSet.contains(chatID) {
                    continue
                }

                let from = message["from"] as? [String: Any]
                let firstName = (from?["first_name"] as? String) ?? "User"
                let username = (from?["username"] as? String).map { "@\($0)" } ?? ""
                let senderLabel = username.isEmpty ? firstName : "\(firstName) (\(username))"

                if autoReplyEnabled {
                    await handleIncomingAndReply(
                        token: token,
                        chatID: chatID,
                        senderName: senderLabel,
                        text: text)
                } else {
                    appendLog(TelegramLogEntry(
                        timestamp: Date(),
                        chatID: chatID,
                        senderName: senderLabel,
                        incomingText: text,
                        replyText: nil,
                        isError: false))
                }
            }
        } catch {
            if !(error is CancellationError) {
                lastError = error.localizedDescription
            }
        }
    }

    private func handleIncomingAndReply(
        token: String,
        chatID: Int64,
        senderName: String,
        text: String
    ) async {
        await sendTypingAction(token: token, chatID: chatID)

        var history = chatHistories[chatID] ?? []
        history.append(ChatMessage.user(text))
        if history.count > 16 {
            history = Array(history.suffix(16))
        }

        let sysPrompt = """
        You are Astral AI operating as the user's personal Telegram AI assistant.
        Reply clearly, politely, and concisely in the same language as the incoming message (Arabic -> Arabic, English -> English).
        Do not output raw JSON or tool markers.
        """
        var promptMessages = [ChatMessage.system(sysPrompt)]
        promptMessages.append(contentsOf: history)

        do {
            let rawReply = try await AppEnvironment.shared.providerStore.llm.complete(messages: promptMessages, model: nil)
            let cleanReply = TextToolProtocol.cleanVisibleText(rawReply)
            let finalReply = cleanReply.isEmpty ? rawReply : cleanReply

            history.append(ChatMessage.assistant(finalReply))
            chatHistories[chatID] = history

            try await sendMessage(token: token, chatID: chatID, text: finalReply)
            appendLog(TelegramLogEntry(
                timestamp: Date(),
                chatID: chatID,
                senderName: senderName,
                incomingText: text,
                replyText: finalReply,
                isError: false))
        } catch {
            appendLog(TelegramLogEntry(
                timestamp: Date(),
                chatID: chatID,
                senderName: senderName,
                incomingText: text,
                replyText: error.localizedDescription,
                isError: true))
        }
    }

    // MARK: - Direct Bot API Calls

    func sendMessage(token overrideToken: String? = nil, chatID: Int64, text: String) async throws {
        let tok = (overrideToken ?? ConnectorStore.shared.token(for: .telegram))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tok.isEmpty else { throw LLMError.badResponse("Missing Telegram Bot Token") }
        guard let url = URL(string: "https://api.telegram.org/bot\(tok)/sendMessage") else {
            throw LLMError.invalidURL("api.telegram.org")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        let body: [String: Any] = [
            "chat_id": chatID,
            "text": String(text.prefix(4000)),
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LLMError.badResponse("Telegram sendMessage failed: \(msg)")
        }
    }

    func fetchRecentUpdatesSummary(limit: Int = 10) async throws -> String {
        let tok = ConnectorStore.shared.token(for: .telegram).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tok.isEmpty else { throw LLMError.badResponse("Missing Telegram Bot Token") }
        guard let url = URL(string: "https://api.telegram.org/bot\(tok)/getUpdates?limit=\(limit)") else {
            throw LLMError.invalidURL("api.telegram.org")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updates = json["result"] as? [[String: Any]] else {
            return "No recent Telegram updates."
        }
        if updates.isEmpty {
            return "No new Telegram messages right now."
        }
        var lines: [String] = []
        for u in updates.suffix(limit) {
            if let msg = u["message"] as? [String: Any],
               let chat = msg["chat"] as? [String: Any],
               let chatID = chat["id"] as? Int64 {
                let from = (msg["from"] as? [String: Any])?["first_name"] as? String ?? "User"
                let text = (msg["text"] as? String) ?? "(media)"
                lines.append("chat_id=\(chatID) | \(from): \(text)")
            }
        }
        return lines.isEmpty ? "No text messages in recent updates." : lines.joined(separator: "\n")
    }

    private func sendTypingAction(token: String, chatID: Int64) async {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendChatAction") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["chat_id": chatID, "action": "typing"])
        _ = try? await URLSession.shared.data(for: req)
    }

    private func parsedAllowedChatIDs() -> Set<Int64> {
        let parts = allowedChatIDsText
            .components(separatedBy: CharacterSet(charactersIn: ", \n"))
            .compactMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return Set(parts)
    }

    private func appendLog(_ entry: TelegramLogEntry) {
        logs.insert(entry, at: 0)
        if logs.count > 50 {
            logs = Array(logs.prefix(50))
        }
    }

    func clearLogs() {
        logs = []
    }
}
