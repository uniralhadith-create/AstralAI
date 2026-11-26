import Foundation

// MARK: - Provider presets

/// One-tap provider templates with verified base URLs and popular models.
/// Selecting a preset in the provider editor fills the URL, protocol and
/// model suggestions — the reliable path to a working connection.
public struct ProviderPreset: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let nameAr: String
    public let baseURL: String
    public let models: [String]
    public let kind: APIProtocolKind
    public let keyHint: String
    public let keyHintAr: String

    public init(
        id: String,
        name: String,
        nameAr: String,
        baseURL: String,
        models: [String],
        kind: APIProtocolKind = .openAICompatible,
        keyHint: String = "",
        keyHintAr: String = ""
    ) {
        self.id = id
        self.name = name
        self.nameAr = nameAr
        self.baseURL = baseURL
        self.models = models
        self.kind = kind
        self.keyHint = keyHint
        self.keyHintAr = keyHintAr
    }

    public var localizedName: String {
        LocalizationManager.shared.effectiveCode == "ar" ? nameAr : name
    }

    public var localizedKeyHint: String {
        LocalizationManager.shared.effectiveCode == "ar" ? keyHintAr : keyHint
    }
}

public enum ProviderPresets {

    public static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "openai",
            name: "OpenAI",
            nameAr: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            models: ["gpt-4o", "gpt-4o-mini", "o3-mini"]),

        ProviderPreset(
            id: "nvidia",
            name: "NVIDIA NIM",
            nameAr: "NVIDIA NIM",
            baseURL: "https://integrate.api.nvidia.com/v1",
            models: [
                "meta/llama-3.3-70b-instruct",
                "deepseek-ai/deepseek-r1",
                "nvidia/llama-3.1-nemotron-70b-instruct",
                "qwen/qwen2.5-coder-32b-instruct",
            ],
            keyHint: "Get a free key at build.nvidia.com (starts with nvapi-)",
            keyHintAr: "احصل على مفتاح مجاني من build.nvidia.com (يبدأ بـ nvapi-)"),

        ProviderPreset(
            id: "grok",
            name: "xAI Grok",
            nameAr: "xAI Grok",
            baseURL: "https://api.x.ai/v1",
            models: ["grok-4", "grok-3", "grok-3-mini"],
            keyHint: "Create a key at console.x.ai",
            keyHintAr: "أنشئ مفتاحاً من console.x.ai"),

        ProviderPreset(
            id: "groq",
            name: "Groq",
            nameAr: "Groq",
            baseURL: "https://api.groq.com/openai/v1",
            models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]),

        ProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            nameAr: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            models: [
                "openai/gpt-4o-mini",
                "anthropic/claude-3.5-sonnet",
                "google/gemini-2.0-flash-001",
            ]),

        ProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            nameAr: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            models: ["deepseek-chat", "deepseek-reasoner"]),

        ProviderPreset(
            id: "mistral",
            name: "Mistral AI",
            nameAr: "Mistral AI",
            baseURL: "https://api.mistral.ai/v1",
            models: ["mistral-large-latest", "mistral-small-latest"]),

        ProviderPreset(
            id: "together",
            name: "Together AI",
            nameAr: "Together AI",
            baseURL: "https://api.together.xyz/v1",
            models: ["meta-llama/Llama-3.3-70B-Instruct-Turbo"]),

        ProviderPreset(
            id: "gemini",
            name: "Google Gemini",
            nameAr: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            models: ["gemini-2.0-flash", "gemini-2.0-flash-lite"],
            keyHint: "Key from aistudio.google.com",
            keyHintAr: "المفتاح من aistudio.google.com"),

        ProviderPreset(
            id: "bedrock",
            name: "AWS Bedrock",
            nameAr: "AWS Bedrock",
            baseURL: "https://bedrock-runtime.us-east-1.amazonaws.com",
            models: [
                "anthropic.claude-3-5-sonnet-20240620-v1:0",
                "us.anthropic.claude-sonnet-4-20250514-v1:0",
                "meta.llama3-3-70b-instruct-v1:0",
            ],
            kind: .bedrock,
            keyHint: "Paste: ACCESS_KEY_ID:SECRET_ACCESS_KEY (IAM user with Bedrock access). Change the region in the URL to yours. OpenAI-compatible URLs (…/openai/v1) also work.",
            keyHintAr: "الصق: ACCESS_KEY_ID:SECRET_ACCESS_KEY (مستخدم IAM بصلاحية Bedrock). غيّر المنطقة في الرابط حسب حسابك. الروابط المتوافقة مع OpenAI (…/openai/v1) مدعومة أيضاً."),

        ProviderPreset(
            id: "ollama",
            name: "Ollama (local)",
            nameAr: "Ollama (محلي)",
            baseURL: "http://localhost:11434/v1",
            models: ["llama3.2", "qwen2.5"],
            keyHint: "No key needed — run: ollama serve",
            keyHintAr: "لا يحتاج مفتاحاً — شغّل: ollama serve"),

        ProviderPreset(
            id: "lmstudio",
            name: "LM Studio (local)",
            nameAr: "LM Studio (محلي)",
            baseURL: "http://localhost:1234/v1",
            models: [],
            keyHint: "Start the local server in LM Studio",
            keyHintAr: "شغّل الخادم المحلي من LM Studio"),
    ]

    public static func preset(id: String) -> ProviderPreset? {
        all.first { $0.id == id }
    }
}
