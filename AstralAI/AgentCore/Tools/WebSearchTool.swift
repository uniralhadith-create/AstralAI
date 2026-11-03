import Foundation

// MARK: - WebSearchTool

/// Searches the web through DuckDuckGo and returns formatted results.
@MainActor
final class WebSearchTool: AgentTool {

    let name = "web_search"

    var spec: ToolSpec {
        ToolSpec(
            name: name,
            description: "Search the web and return the top results (title, URL, snippet).",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The search query"),
                    ]),
                    "max_results": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum results, default 6"),
                    ]),
                ]),
                "required": .array([.string("query")]),
            ]))
    }

    func execute(
        arguments: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let query = arguments["query"]?.stringValue,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                content: "Error: missing required parameter 'query'.",
                isError: true)
        }
        let maxResults = arguments["max_results"]?.intValue ?? 6

        let results: [WebSearchService.SearchResult]
        do {
            results = try await WebSearchService.search(query: query, maxResults: maxResults)
        } catch {
            return ToolResult(
                content: "Search failed: \(error.localizedDescription)",
                isError: true)
        }

        guard !results.isEmpty else {
            return ToolResult(content: "No results found for: \(query)")
        }

        var lines: [String] = []
        for (index, result) in results.enumerated() {
            lines.append("\(index + 1). \(result.title)")
            lines.append("   URL: \(result.url)")
            lines.append("   \(result.snippet)")
        }
        return ToolResult(content: lines.joined(separator: "\n"))
    }
}
