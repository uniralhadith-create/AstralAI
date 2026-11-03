import Foundation

// MARK: - WebSearchService

/// Multi-engine HTML search (no API keys). The engine chain, in order:
/// 1. **Bing** — reliably reachable, rich markup. V3.6 fix: Bing's mobile
///    layout nests the title INSIDE the anchor (`<a href><h2>…</h2></a>`)
///    while the desktop layout keeps the legacy order (`<h2><a href>…</a>`);
///    both are now parsed, and `bing.com/ck/a` redirect wrappers are
///    unwrapped (base64url `u=a1` payload).
/// 2. **DuckDuckGo HTML / Lite** — frequently serves 202 anti-bot challenge
///    pages on datacenter and some mobile carriers; used only as fallback.
/// 3. **Mojeek** — independent index, scraping-friendly markup.
/// 4. **Wikipedia API** — never blocks, no key; a knowledge fallback that
///    guarantees the agent always receives usable material (Arabic queries
///    hit ar.wikipedia.org automatically).
enum WebSearchService {

    struct SearchResult: Codable, Equatable {
        let title: String
        let url: String
        let snippet: String
    }

    private static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    private static let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    /// Searches the web and returns up to `maxResults` results.
    static func search(query: String, maxResults: Int = 6) async throws -> [SearchResult] {
        let limited = max(1, min(maxResults, 10))
        var failures: [String] = []

        // 1. Bing (mobile UA first — serves the modern layout — then desktop).
        for ua in [mobileUA, desktopUA] {
            if let html = try? await fetchHTML(
                url: bingURL(query: query), userAgent: ua) {
                let results = parseBingResults(html)
                if !results.isEmpty {
                    return Array(results.prefix(limited))
                }
            }
        }

        // 2. DuckDuckGo HTML endpoint, then Lite.
        for base in ["https://html.duckduckgo.com/html/", "https://lite.duckduckgo.com/lite/"] {
            if let url = try? searchURL(base: base, query: query),
               let html = try? await fetchHTML(url: url, userAgent: mobileUA) {
                let results = parseHTMLResults(html) + parseLiteResults(html)
                if !results.isEmpty {
                    return Array(results.prefix(limited))
                }
            }
        }

        // 3. Mojeek — independent index.
        if let url = try? searchURL(base: "https://www.mojeek.com/search", query: query),
           let html = try? await fetchHTML(url: url, userAgent: desktopUA) {
            let results = parseMojeekResults(html)
            if !results.isEmpty {
                return Array(results.prefix(limited))
            }
        }

        // 4. Wikipedia — the guaranteed knowledge fallback. Arabic-script
        // queries search the Arabic Wikipedia; everything else English.
        let wiki = await wikipediaSearch(query: query, limit: limited)
        if !wiki.isEmpty {
            return Array(wiki.prefix(limited))
        }

        throw LLMError.network(
            "No search results returned — all engines unreachable or blocked "
            + "(Bing, DuckDuckGo, Mojeek, Wikipedia). Check the internet connection.")
    }

    // MARK: Networking

    private static func bingURL(query: String) -> URL {
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "15"),
        ]
        return components.url!
    }

    private static func searchURL(base: String, query: String) throws -> URL {
        guard var components = URLComponents(string: base) else {
            throw LLMError.network("Invalid search endpoint URL")
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw LLMError.network("Invalid search request URL")
        }
        return url
    }

    private static func fetchHTML(url: URL, userAgent: String) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9,ar;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LLMError.network("Search endpoint returned HTTP \(http.statusCode)")
        }
        // HTTP 202 from DuckDuckGo is an anti-bot challenge page, not
        // results — treat it as unreadable so the fallback engine runs.
        if let http = response as? HTTPURLResponse, http.statusCode == 202 {
            throw LLMError.network("Search endpoint served a challenge page")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw LLMError.network("Search endpoint returned unreadable data")
        }
        return html
    }

    // MARK: Bing parsing

    /// Parses Bing's `<li class="b_algo">` result blocks. Two title shapes
    /// are supported:
    /// - modern/mobile: `<a href="…"><h2>Title</h2></a>`
    /// - legacy/desktop: `<h2><a href="…">Title</a></h2>`
    /// Snippets come from `b_lineclamp` paragraphs or the `b_caption`
    /// wrapper. Bing redirect URLs (`bing.com/ck/a?…&u=a1…`) are unwrapped
    /// by base64url-decoding the payload; anything still pointing at Bing
    /// or Microsoft hosts is dropped.
    private static func parseBingResults(_ html: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let blocks = html.components(separatedBy: "<li class=\"b_algo\"")
        guard blocks.count > 1 else { return [] }

        for block in blocks.dropFirst() {
            guard let titleMatch = firstMatch(
                pattern: "<a[^>]*href=\"([^\"]+)\"[^>]*>\\s*<h2[^>]*>(.*?)</h2>\\s*</a>",
                in: block)
                ?? firstMatch(
                    pattern: "<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
                    in: block)
            else { continue }
            let title = cleanText(titleMatch.1)
            guard !title.isEmpty else { continue }

            let url = resolvedBingURL(decodeEntities(titleMatch.0))
            guard url.hasPrefix("http"), !isBingRedirect(url) else { continue }

            var snippet = ""
            // Single-capture patterns → firstCapture (firstMatch requires
            // two groups; using it here silently dropped every Bing snippet
            // — caught by the test suite once it actually ran, V4.5.6).
            if let snippetMatch = firstCapture(
                pattern: "<p[^>]*class=\"[^\"]*b_lineclamp[^\"]*\"[^>]*>(.*?)</p>",
                in: block) {
                snippet = cleanText(snippetMatch)
            } else if let captionMatch = firstCapture(
                pattern: "class=\"b_caption\"[^>]*>(.*?)</div>",
                in: block) {
                snippet = cleanText(captionMatch)
            }

            results.append(SearchResult(title: title, url: url, snippet: snippet))
            if results.count >= 15 { break }
        }
        return results
    }

    /// True for Bing/Microsoft redirect or tracking URLs that should never
    /// reach the model as a source.
    private static func isBingRedirect(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.contains("bing.com/ck/")
            || lowered.contains("bing.com/a?")
            || lowered.contains("go.microsoft.com")
            || lowered.contains("microsoft.com/en-us/bing")
            || lowered.hasPrefix("https://www.bing.com/search")
    }

    /// Resolves a Bing result URL: direct links pass through; the
    /// `bing.com/ck/a?...&u=a1<base64url>` redirect wrapper is unwrapped by
    /// base64url-decoding the payload.
    private static func resolvedBingURL(_ raw: String) -> String {
        if let base64 = firstCapture(pattern: "[?&]u=a1([A-Za-z0-9_-]+)", in: raw) {
            let normalized = base64
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
            if let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters),
               let decoded = String(data: data, encoding: .utf8),
               decoded.hasPrefix("http") {
                return decoded
            }
        }
        return raw
    }

    // MARK: DuckDuckGo HTML endpoint parsing

    private static func parseHTMLResults(_ html: String) -> [SearchResult] {
        var pairs: [(title: String, url: String)] = []
        let linkPattern = "class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>"
        if let linkRegex = try? NSRegularExpression(
            pattern: linkPattern,
            options: [.dotMatchesLineSeparators]) {
            let range = NSRange(html.startIndex..., in: html)
            for match in linkRegex.matches(in: html, options: [], range: range) {
                guard match.numberOfRanges >= 3,
                      let hrefRange = Range(match.range(at: 1), in: html),
                      let titleRange = Range(match.range(at: 2), in: html) else { continue }
                let url = resolvedURL(fromRaw: String(html[hrefRange]))
                let title = cleanText(String(html[titleRange]))
                guard !url.isEmpty, !title.isEmpty else { continue }
                pairs.append((title, url))
            }
        }

        guard !pairs.isEmpty else { return [] }

        var snippets: [String] = []
        let snippetPattern = "class=\"result__snippet\"[^>]*>(.*?)</a>"
        if let snippetRegex = try? NSRegularExpression(
            pattern: snippetPattern,
            options: [.dotMatchesLineSeparators]) {
            let range = NSRange(html.startIndex..., in: html)
            for match in snippetRegex.matches(in: html, options: [], range: range) {
                guard let snippetRange = Range(match.range(at: 1), in: html) else { continue }
                snippets.append(cleanText(String(html[snippetRange])))
            }
        }

        var results: [SearchResult] = []
        for (index, pair) in pairs.enumerated() {
            let snippet = index < snippets.count ? snippets[index] : ""
            results.append(SearchResult(title: pair.title, url: pair.url, snippet: snippet))
        }
        return results
    }

    // MARK: Lite endpoint parsing

    private static func parseLiteResults(_ html: String) -> [SearchResult] {
        var pairs: [(title: String, url: String)] = []

        // The lite endpoint puts href before or after class="result-link"
        // depending on the served markup; try both attribute orders.
        let patterns = [
            "href=\"([^\"]+)\"[^>]*class=\"result-link\"[^>]*>(.*?)</a>",
            "class=\"result-link\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
        ]
        for pattern in patterns where pairs.isEmpty {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, options: [], range: range) {
                guard match.numberOfRanges >= 3,
                      let hrefRange = Range(match.range(at: 1), in: html),
                      let titleRange = Range(match.range(at: 2), in: html) else { continue }
                let url = resolvedURL(fromRaw: String(html[hrefRange]))
                let title = cleanText(String(html[titleRange]))
                guard !url.isEmpty, !title.isEmpty else { continue }
                pairs.append((title, url))
            }
        }

        guard !pairs.isEmpty else { return [] }

        var snippets: [String] = []
        let snippetPattern = "class=\"result-snippet\"[^>]*>(.*?)</td>"
        if let snippetRegex = try? NSRegularExpression(
            pattern: snippetPattern,
            options: [.dotMatchesLineSeparators]) {
            let range = NSRange(html.startIndex..., in: html)
            for match in snippetRegex.matches(in: html, options: [], range: range) {
                guard let snippetRange = Range(match.range(at: 1), in: html) else { continue }
                snippets.append(cleanText(String(html[snippetRange])))
            }
        }

        var results: [SearchResult] = []
        for (index, pair) in pairs.enumerated() {
            let snippet = index < snippets.count ? snippets[index] : ""
            results.append(SearchResult(title: pair.title, url: pair.url, snippet: snippet))
        }
        return results
    }

    // MARK: Mojeek parsing

    /// Mojeek serves `<li class="result-item">` blocks (older layouts:
    /// `<ul class="results-standard">` with `<h2><a>` titles). Title links
    /// carry class "title" or sit inside an `<h2>`; snippets are `<p class="s">`.
    private static func parseMojeekResults(_ html: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let separators = ["<li class=\"result-item\"", "<li class=\"result", "<article"]
        var blocks: [String] = []
        for separator in separators where blocks.count <= 1 {
            blocks = html.components(separatedBy: separator)
            if blocks.count > 1 { break }
        }
        guard blocks.count > 1 else { return [] }

        outer: for block in blocks.dropFirst() {
            guard let titleMatch = firstMatch(
                pattern: "<a[^>]*href=\"(https?://[^\"]+)\"[^>]*class=\"title\"[^>]*>(.*?)</a>",
                in: block)
                ?? firstMatch(
                    pattern: "class=\"title\"[^>]*href=\"(https?://[^\"]+)\"[^>]*>(.*?)</a>",
                    in: block)
                ?? firstMatch(
                    pattern: "<h2[^>]*>\\s*<a[^>]*href=\"(https?://[^\"]+)\"[^>]*>(.*?)</a>",
                    in: block)
                ?? firstMatch(
                    pattern: "<a[^>]*class=\"ob\"[^>]*href=\"(https?://[^\"]+)\"[^>]*>(.*?)</a>",
                    in: block)
            else { continue }
            let title = cleanText(titleMatch.1)
            let url = decodeEntities(titleMatch.0)
            guard !title.isEmpty, url.hasPrefix("http"),
                  !url.contains("mojeek.com") else { continue }

            var snippet = ""
            // Same single-group fix as the Bing parser (V4.5.6).
            if let snippetMatch = firstCapture(
                pattern: "<p[^>]*class=\"s\"[^>]*>(.*?)</p>",
                in: block) {
                snippet = cleanText(snippetMatch)
            }

            results.append(SearchResult(title: title, url: url, snippet: snippet))
            if results.count >= 15 { break outer }
        }
        return results
    }

    // MARK: Wikipedia fallback

    /// Test hook: runs the private Bing parser over raw HTML.
    static func parseBingResultsForTests(_ html: String) -> [SearchResult] {
        parseBingResults(html)
    }

    /// Wikipedia full-text search API — JSON, stable, never rate-limits
    /// meaningfully. Arabic-script queries use the Arabic edition; Latin
    /// queries use English. Results link to the article pages and use the
    /// search snippet as-is (already plain text).
    private static func wikipediaSearch(query: String, limit: Int) async -> [SearchResult] {
        let isArabicScript = query.unicodeScalars.contains { scalar in
            (0x0600...0x06FF).contains(scalar.value)
        }
        let host = isArabicScript ? "ar.wikipedia.org" : "en.wikipedia.org"

        var components = URLComponents(string: "https://\(host)/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: String(max(3, limit))),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data, options: [])
                  as? [String: Any],
              let queryObject = body["query"] as? [String: Any],
              let hits = queryObject["search"] as? [[String: Any]] else {
            return []
        }

        var results: [SearchResult] = []
        for hit in hits {
            guard let title = hit["title"] as? String else { continue }
            let slug = title
                .replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            let snippetHTML = hit["snippet"] as? String ?? ""
            results.append(SearchResult(
                title: title,
                url: "https://\(host)/wiki/\(slug)",
                snippet: cleanText(snippetHTML)))
        }
        return results
    }

    // MARK: Text helpers

    /// Returns capture groups (1, 2) of the first regex match in `text`,
    /// or nil when the pattern doesn't match or a group is missing.
    /// Shared by all parsers.
    private static func firstMatch(
        pattern: String,
        in text: String
    ) -> (String, String)? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3,
              let first = Range(match.range(at: 1), in: text),
              let second = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[first]), String(text[second]))
    }

    /// Returns capture group 1 of the first regex match — for patterns with
    /// a single group.
    private static func firstCapture(
        pattern: String,
        in text: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let first = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[first])
    }

    /// Resolves DuckDuckGo redirect links (uddg parameter) and protocol
    /// relative URLs into direct https URLs.
    private static func resolvedURL(fromRaw raw: String) -> String {
        let href = decodeEntities(raw)
        if let uddgRange = href.range(of: "uddg=") {
            var value = String(href[uddgRange.upperBound...])
            if let ampersand = value.firstIndex(of: "&") {
                value = String(value[..<ampersand])
            }
            let cleaned = value.replacingOccurrences(of: "+", with: " ")
            if let decoded = cleaned.removingPercentEncoding,
               decoded.hasPrefix("http") {
                return decoded
            }
        }
        if href.hasPrefix("//") {
            return "https:" + href
        }
        if href.hasPrefix("/") {
            return "https://duckduckgo.com" + href
        }
        return href
    }

    /// Strips HTML tags, decodes entities and collapses whitespace.
    private static func cleanText(_ text: String) -> String {
        var out = text
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(out.startIndex..., in: out)
            out = tagRegex.stringByReplacingMatches(
                in: out, options: [], range: range, withTemplate: "")
        }
        out = decodeEntities(out)
        out = out.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return out
    }

    private static func decodeEntities(_ text: String) -> String {
        var out = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#x27;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&#x2F;", "/"),
            ("&#47;", "/"),
        ]
        for (entity, replacement) in entities {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
    }
}
