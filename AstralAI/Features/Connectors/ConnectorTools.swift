import Foundation

// MARK: - 1. GitHub Connector Tool

@MainActor
final class GitHubConnectorTool: AgentTool {
    let name = "github_api"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Interact with GitHub repositories, files, issues, pull requests, and code search using the user's connected GitHub token.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("One of: list_repos, get_file, create_or_update_file, list_issues, create_issue, list_prs, search_code"),
                    ]),
                    "repo": .object([
                        "type": .string("string"),
                        "description": .string("Repository in 'owner/repo' format (required for repo actions)"),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("File path inside the repo (for get_file / create_or_update_file)"),
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("File content (for create_or_update_file) or issue body (for create_issue)"),
                    ]),
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("Issue title or commit message"),
                    ]),
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search query (for search_code)"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]))
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        let token = ConnectorStore.shared.token(for: .github)
        guard !token.isEmpty else {
            return ToolResult(content: "GitHub connector is not configured. Ask the user to add their GitHub Personal Access Token in Connectors & Plugins.", isError: true)
        }
        let action = arguments["action"]?.stringValue ?? ""
        let repo = arguments["repo"]?.stringValue ?? ""
        let path = arguments["path"]?.stringValue ?? ""
        let content = arguments["content"]?.stringValue ?? ""
        let title = arguments["title"]?.stringValue ?? "Update from Astral AI"
        let query = arguments["query"]?.stringValue ?? ""

        func ghRequest(urlString: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Int, Data) {
            guard let url = URL(string: urlString) else { throw LLMError.invalidURL(urlString) }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 25
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 500
            return (code, data)
        }

        switch action {
        case "list_repos":
            let (code, data) = try await ghRequest(urlString: "https://api.github.com/user/repos?sort=updated&per_page=20")
            guard (200...299).contains(code),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return ToolResult(content: "GitHub list_repos failed (HTTP \(code)).", isError: true)
            }
            let lines = arr.map { r -> String in
                let full = (r["full_name"] as? String) ?? ""
                let priv = (r["private"] as? Bool) == true ? "private" : "public"
                let desc = (r["description"] as? String) ?? ""
                return "- \(full) [\(priv)] \(desc)"
            }
            return ToolResult(content: lines.isEmpty ? "No repositories found." : lines.joined(separator: "\n"))

        case "get_file":
            guard !repo.isEmpty, !path.isEmpty else {
                return ToolResult(content: "Provide 'repo' and 'path'.", isError: true)
            }
            let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            let (code, data) = try await ghRequest(urlString: "https://api.github.com/repos/\(repo)/contents/\(encodedPath)")
            guard (200...299).contains(code),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let b64 = json["content"] as? String,
                  let decoded = Data(base64Encoded: b64.replacingOccurrences(of: "\n", with: "")),
                  let text = String(data: decoded, encoding: .utf8) else {
                return ToolResult(content: "Could not read \(repo)/\(path) (HTTP \(code)).", isError: true)
            }
            return ToolResult(content: String(text.prefix(8000)))

        case "create_or_update_file":
            guard !repo.isEmpty, !path.isEmpty else {
                return ToolResult(content: "Provide 'repo', 'path', and 'content'.", isError: true)
            }
            let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            let urlStr = "https://api.github.com/repos/\(repo)/contents/\(encodedPath)"
            var payload: [String: Any] = [
                "message": title,
                "content": Data(content.utf8).base64EncodedString(),
            ]
            // Fetch existing SHA if file already exists
            let (getCode, getData) = try await ghRequest(urlString: urlStr)
            if (200...299).contains(getCode),
               let existing = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
               let sha = existing["sha"] as? String {
                payload["sha"] = sha
            }
            let (putCode, putData) = try await ghRequest(urlString: urlStr, method: "PUT", body: payload)
            if (200...299).contains(putCode) {
                return ToolResult(content: "Committed '\(path)' to \(repo) successfully.")
            }
            let errText = String(data: putData, encoding: .utf8) ?? ""
            return ToolResult(content: "GitHub commit failed (HTTP \(putCode)): \(String(errText.prefix(300)))", isError: true)

        case "list_issues", "list_prs":
            guard !repo.isEmpty else { return ToolResult(content: "Provide 'repo'.", isError: true) }
            let endpoint = action == "list_prs" ? "pulls" : "issues"
            let (code, data) = try await ghRequest(urlString: "https://api.github.com/repos/\(repo)/\(endpoint)?state=open&per_page=15")
            guard (200...299).contains(code),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return ToolResult(content: "GitHub \(action) failed (HTTP \(code)).", isError: true)
            }
            let lines = arr.map { item -> String in
                let num = (item["number"] as? Int) ?? 0
                let t = (item["title"] as? String) ?? ""
                return "#\(num): \(t)"
            }
            return ToolResult(content: lines.isEmpty ? "No open items in \(repo)." : lines.joined(separator: "\n"))

        case "create_issue":
            guard !repo.isEmpty, !title.isEmpty else {
                return ToolResult(content: "Provide 'repo' and 'title'.", isError: true)
            }
            let (code, data) = try await ghRequest(
                urlString: "https://api.github.com/repos/\(repo)/issues",
                method: "POST",
                body: ["title": title, "body": content])
            if (200...299).contains(code),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let htmlURL = json["html_url"] as? String {
                return ToolResult(content: "Issue created: \(htmlURL)")
            }
            return ToolResult(content: "Failed to create issue (HTTP \(code)).", isError: true)

        case "search_code":
            guard !query.isEmpty else { return ToolResult(content: "Provide 'query'.", isError: true) }
            let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let (code, data) = try await ghRequest(urlString: "https://api.github.com/search/code?q=\(q)&per_page=10")
            guard (200...299).contains(code),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                return ToolResult(content: "GitHub search_code failed (HTTP \(code)).", isError: true)
            }
            let lines = items.map { i -> String in
                let p = (i["path"] as? String) ?? ""
                let r = ((i["repository"] as? [String: Any])?["full_name"] as? String) ?? ""
                return "- \(r): \(p)"
            }
            return ToolResult(content: lines.isEmpty ? "No code matches." : lines.joined(separator: "\n"))

        default:
            return ToolResult(content: "Unknown GitHub action '\(action)'.", isError: true)
        }
    }
}

// MARK: - 2. Telegram Bot Agent Tool

@MainActor
final class TelegramConnectorTool: AgentTool {
    let name = "telegram_bot"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Control the user's connected Telegram Bot: check bot status, read incoming messages, send messages to a chat_id, or start/stop AI auto-reply polling.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("One of: get_me, get_updates, send_message, start_auto_reply, stop_auto_reply"),
                    ]),
                    "chat_id": .object([
                        "type": .string("string"),
                        "description": .string("Numeric Telegram chat_id (required for send_message)"),
                    ]),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string("Message text to send"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]))
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        let action = arguments["action"]?.stringValue ?? "get_me"
        let service = TelegramAgentService.shared

        switch action {
        case "get_me":
            let info = try await service.verifyBot()
            return ToolResult(content: "Telegram Bot active: \(info.firstName) (@\(info.username)), auto-reply polling: \(service.isPolling ? "RUNNING" : "STOPPED").")
        case "get_updates":
            let summary = try await service.fetchRecentUpdatesSummary(limit: 12)
            return ToolResult(content: summary)
        case "send_message":
            let rawID = arguments["chat_id"]?.stringValue ?? ""
            guard let chatID = Int64(rawID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return ToolResult(content: "Provide a valid numeric 'chat_id'. Use action='get_updates' first to see recent chat IDs.", isError: true)
            }
            let text = arguments["text"]?.stringValue ?? ""
            guard !text.isEmpty else { return ToolResult(content: "Provide 'text' to send.", isError: true) }
            try await service.sendMessage(chatID: chatID, text: text)
            return ToolResult(content: "Sent Telegram message to chat_id \(chatID).")
        case "start_auto_reply":
            service.autoReplyEnabled = true
            service.startAgentPolling()
            return ToolResult(content: "Started Telegram Bot live auto-reply agent.")
        case "stop_auto_reply":
            service.stopAgentPolling()
            return ToolResult(content: "Stopped Telegram Bot live auto-reply agent.")
        default:
            return ToolResult(content: "Unknown Telegram action '\(action)'.", isError: true)
        }
    }
}

// MARK: - 3. MCP (Model Context Protocol) Tool

@MainActor
final class MCPConnectorTool: AgentTool {
    let name = "mcp_call"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "List or invoke tools on any user-configured MCP (Model Context Protocol) server over JSON-RPC 2.0.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("'list_servers', 'list_tools', or 'call_tool'"),
                    ]),
                    "server_name": .object([
                        "type": .string("string"),
                        "description": .string("Optional MCP server name (defaults to first enabled MCP server)"),
                    ]),
                    "tool_name": .object([
                        "type": .string("string"),
                        "description": .string("Remote MCP tool name (for call_tool)"),
                    ]),
                    "arguments_json": .object([
                        "type": .string("string"),
                        "description": .string("JSON object string of arguments to pass to the MCP tool"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]))
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        let store = ConnectorStore.shared
        let servers = store.mcpServers.filter(\.isEnabled)
        let action = arguments["action"]?.stringValue ?? "list_servers"

        if action == "list_servers" {
            if servers.isEmpty {
                return ToolResult(content: "No MCP servers are enabled. Add an MCP server in Connectors & Plugins.")
            }
            let lines = servers.map { s in
                let toolNames = s.discoveredTools.map(\.name).joined(separator: ", ")
                return "- \(s.name) (\(s.endpointURL)) tools: [\(toolNames)]"
            }
            return ToolResult(content: lines.joined(separator: "\n"))
        }

        let targetName = arguments["server_name"]?.stringValue ?? ""
        guard let server = (targetName.isEmpty
            ? servers.first
            : servers.first { $0.name.localizedCaseInsensitiveContains(targetName) }) ?? servers.first else {
            return ToolResult(content: "No matching enabled MCP server found.", isError: true)
        }
        let tok = store.mcpToken(for: server.id)

        if action == "list_tools" {
            let tools = try await MCPClient.listTools(endpointURL: server.endpointURL, bearerToken: tok.isEmpty ? nil : tok)
            let lines = tools.map { "- \($0.name): \($0.description)" }
            return ToolResult(content: lines.isEmpty ? "No tools returned by \(server.name)." : lines.joined(separator: "\n"))
        }

        guard let toolName = arguments["tool_name"]?.stringValue, !toolName.isEmpty else {
            return ToolResult(content: "Provide 'tool_name' for mcp_call.", isError: true)
        }
        var argsDict: [String: Any] = [:]
        if let rawJSON = arguments["arguments_json"]?.stringValue,
           let data = rawJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argsDict = parsed
        }

        let output = try await MCPClient.callTool(
            endpointURL: server.endpointURL,
            bearerToken: tok.isEmpty ? nil : tok,
            toolName: toolName,
            arguments: argsDict)
        return ToolResult(content: String(output.prefix(8000)))
    }
}

// MARK: - 4. Universal Plugin Connector Tool (Notion, Slack, Discord, Linear, Trello, Brave, Tavily, Vercel, Supabase, Webhook)

@MainActor
final class UniversalPluginTool: AgentTool {
    let name = "plugin_call"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Execute actions on connected plugins: notion (search), slack (send_message), discord (send_message), linear (list_issues/create_issue), trello (list_boards), brave_search (search), tavily (search), vercel (list_projects), supabase (query), or webhook (post).",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "plugin": .object([
                        "type": .string("string"),
                        "description": .string("One of: notion, slack, discord, linear, trello, brave_search, tavily, vercel, supabase, webhook"),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("Action name (e.g. search, send_message, list_issues, create_issue, query, post)"),
                    ]),
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search query, table name, or Slack channel ID"),
                    ]),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string("Message text, title, or JSON payload"),
                    ]),
                    "url": .object([
                        "type": .string("string"),
                        "description": .string("Optional override URL for webhook"),
                    ]),
                ]),
                "required": .array([.string("plugin")]),
            ]))
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        let store = ConnectorStore.shared
        let plugin = (arguments["plugin"]?.stringValue ?? "").lowercased()
        let query = arguments["query"]?.stringValue ?? ""
        let text = arguments["text"]?.stringValue ?? ""
        let customURL = arguments["url"]?.stringValue ?? ""

        switch plugin {
        case "notion":
            let tok = store.token(for: .notion)
            guard !tok.isEmpty else { return ToolResult(content: "Notion token not configured.", isError: true) }
            var req = URLRequest(url: URL(string: "https://api.notion.com/v1/search")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "page_size": 10])
            let (data, _) = try await URLSession.shared.data(for: req)
            return ToolResult(content: String((String(data: data, encoding: .utf8) ?? "").prefix(5000)))

        case "slack":
            let tok = store.token(for: .slack)
            guard !tok.isEmpty else { return ToolResult(content: "Slack token not configured.", isError: true) }
            var req = URLRequest(url: URL(string: "https://slack.com/api/chat.postMessage")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["channel": query, "text": text])
            let (data, _) = try await URLSession.shared.data(for: req)
            return ToolResult(content: String((String(data: data, encoding: .utf8) ?? "").prefix(2000)))

        case "discord":
            let webhookURL = store.token(for: .discord)
            guard let url = URL(string: webhookURL), webhookURL.hasPrefix("http") else {
                return ToolResult(content: "Discord Webhook URL not configured.", isError: true)
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["content": text])
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 500
            return ToolResult(content: (200...299).contains(code) ? "Sent message to Discord." : "Discord webhook failed (HTTP \(code)).", isError: !(200...299).contains(code))

        case "linear":
            let tok = store.token(for: .linear)
            guard !tok.isEmpty else { return ToolResult(content: "Linear API key not configured.", isError: true) }
            var req = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
            req.httpMethod = "POST"
            req.setValue(tok, forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let gql = "{ issues(first: 10) { nodes { identifier title state { name } } } }"
            req.httpBody = try JSONSerialization.data(withJSONObject: ["query": gql])
            let (data, _) = try await URLSession.shared.data(for: req)
            return ToolResult(content: String((String(data: data, encoding: .utf8) ?? "").prefix(4000)))

        case "brave_search", "brave":
            let tok = store.token(for: .braveSearch)
            guard !tok.isEmpty else { return ToolResult(content: "Brave Search API key not configured.", isError: true) }
            let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            var req = URLRequest(url: URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(q)&count=8")!)
            req.setValue(tok, forHTTPHeaderField: "X-Subscription-Token")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            return ToolResult(content: String((String(data: data, encoding: .utf8) ?? "").prefix(6000)))

        case "tavily":
            let tok = store.token(for: .tavily)
            guard !tok.isEmpty else { return ToolResult(content: "Tavily API key not configured.", isError: true) }
            var req = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["api_key": tok, "query": query, "max_results": 6])
            let (data, _) = try await URLSession.shared.data(for: req)
            return ToolResult(content: String((String(data: data, encoding: .utf8) ?? "").prefix(6000)))

        case "vercel":
            let tok = store.token(for: .vercel)
            guard !tok.isEmpty else { return ToolResult(content: "Vercel token not configured.", isError: true) }
            var req = URLRequest(url: URL(string: "https://api.vercel.com/v9/projects")!)
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
            return ToolResult(content: String((String(data: data, encoding: .utf8) ?? "").prefix(5000)))

        case "supabase":
            let key = store.token(for: .supabase)
            let base = store.secondaryValue(for: .supabase).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !key.isEmpty, !base.isEmpty, let url = URL(string: "\(base)/rest/v1/\(query)?limit=20") else {
                return ToolResult(content: "Supabase URL/Key not configured.", isError: true)
            }
            var req = URLRequest(url: url)
            req.setValue(key, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
            return ToolResult(content: String((String(data: data, encoding: .utf8) ?? "").prefix(5000)))

        case "webhook":
            let target = customURL.isEmpty ? store.secondaryValue(for: .webhook) : customURL
            guard let url = URL(string: target) else { return ToolResult(content: "Webhook URL not configured.", isError: true) }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let tok = store.token(for: .webhook)
            if !tok.isEmpty { req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization") }
            req.httpBody = Data((text.isEmpty ? "{}" : text).utf8)
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 500
            return ToolResult(content: "Webhook HTTP \(code): \(String((String(data: data, encoding: .utf8) ?? "").prefix(2000)))")

        default:
            return ToolResult(content: "Unsupported plugin '\(plugin)'.", isError: true)
        }
    }
}
