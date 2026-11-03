import Foundation

// MARK: - Endpoint resolver

/// Smart URL handling for user-entered provider base URLs.
///
/// Users paste endpoints in every imaginable shape — bare hosts, hosts with
/// `/v1`, full `.../chat/completions` URLs, URLs without a scheme. This
/// resolver normalizes the input and generates ordered endpoint candidates
/// so the LLM service can probe until one answers, which is what makes
/// providers like NVIDIA NIM, xAI (Grok), OpenRouter and local servers
/// connect on the first try.
public enum EndpointResolver {

    /// Cleans a user-entered base URL:
    /// - trims whitespace
    /// - prepends `https://` when the scheme is missing
    /// - drops trailing slashes
    /// - strips pasted endpoint suffixes (`/chat/completions`, `/models`, …)
    ///
    /// Returns nil when nothing usable remains.
    public static func normalizeBaseURL(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if !value.contains("://") {
            value = "https://" + value
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        // A full endpoint was pasted: reduce it to its base.
        let lowered = value.lowercased()
        for suffix in ["/chat/completions", "/completions", "/models", "/messages", "/converse", "/converse-stream"] {
            if lowered.hasSuffix(suffix) {
                value = String(value.dropLast(suffix.count))
                break
            }
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        guard URL(string: value) != nil, value.contains("://") else {
            return nil
        }
        return value
    }

    /// True when the base URL already ends with an API version segment
    /// (`/v1`, `/v2`, `/v3`, `/v1beta`) — meaning endpoint paths must NOT
    /// prepend another `/v1` (the classic `…/v1/v1/chat/completions` bug).
    public static func hasVersionSuffix(_ base: String) -> Bool {
        guard let url = URL(string: base) else { return false }
        let path = url.path.lowercased()
        guard !path.isEmpty else { return false }
        let versions = ["/v1", "/v2", "/v3", "/v4", "/v1beta"]
        return versions.contains { path == $0 || path.hasSuffix($0) }
    }

    /// Ordered chat-completion endpoint candidates for the base URL.
    public static func chatEndpointCandidates(_ rawBase: String) -> [String] {
        guard let base = normalizeBaseURL(rawBase) else { return [] }
        if hasVersionSuffix(base) {
            return [base + "/chat/completions"]
        }
        return [
            base + "/v1/chat/completions",
            base + "/chat/completions",
        ]
    }

    /// Ordered model-listing endpoint candidates for the base URL.
    public static func modelsEndpointCandidates(_ rawBase: String) -> [String] {
        guard let base = normalizeBaseURL(rawBase) else { return [] }
        if hasVersionSuffix(base) {
            return [base + "/models"]
        }
        return [
            base + "/v1/models",
            base + "/models",
        ]
    }

    /// The display form of a base URL (normalized, for settings UI).
    public static func displayBase(_ raw: String) -> String {
        normalizeBaseURL(raw) ?? raw
    }

    // MARK: AWS Bedrock detection

    /// True when the base URL points at an AWS Bedrock runtime host
    /// (`bedrock-runtime.{region}.amazonaws.com` or `bedrock.{region}…`).
    /// These hosts expose the OpenAI-compatible layer under `/openai/v1` —
    /// blindly appending `/v1/chat/completions` is what produced the
    /// user-facing 404s.
    public static func isBedrockHost(_ rawBase: String) -> Bool {
        bedrockRegion(from: rawBase) != nil
    }

    /// Extracts the region from a Bedrock base URL, if the host is one.
    public static func bedrockRegion(from rawBase: String) -> String? {
        guard let base = normalizeBaseURL(rawBase),
              let url = URL(string: base),
              let host = url.host(percentEncoded: false) ?? url.host,
              host.hasSuffix(".amazonaws.com") else { return nil }
        let parts = host.dropLast(".amazonaws.com".count).split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let prefix = parts[0]
        guard prefix == "bedrock-runtime" || prefix == "bedrock" else { return nil }
        return String(parts[1])
    }

    /// The Bedrock OpenAI-compatible chat endpoint for a region.
    public static func bedrockOpenAIChatEndpoint(region: String) -> String {
        "https://bedrock-runtime.\(region).amazonaws.com/openai/v1/chat/completions"
    }

    /// The Bedrock OpenAI-compatible model-listing endpoint for a region.
    public static func bedrockOpenAIModelsEndpoint(region: String) -> String {
        "https://bedrock-runtime.\(region).amazonaws.com/openai/v1/models"
    }
}
