import Foundation

// MARK: - Skill model

/// An installable agent skill: a named bundle of expert instructions,
/// tool hints and triggers that extends what the AI models can do.
/// Skills can come from the built-in library, be downloaded from a URL,
/// imported from a JSON file, or written by hand in-app.
public struct Skill: Codable, Equatable, Identifiable {
    public var id: UUID
    /// Unique machine key, e.g. `"deep-research"`.
    public var slug: String
    public var name: String
    public var nameAr: String?
    public var summary: String
    public var summaryAr: String?
    public var category: String
    /// SF Symbol name shown in lists and chips.
    public var icon: String
    public var version: String
    public var author: String
    /// The system-prompt fragment injected while this skill is enabled.
    public var instructions: String
    /// Tool names this skill relies on (informational hints for the model).
    public var tools: [String]
    /// Keywords that suggest activating the skill.
    public var triggers: [String]
    public var source: SkillSource
    public var isEnabled: Bool
    public var installedAt: Date?

    public init(
        id: UUID = UUID(),
        slug: String,
        name: String,
        nameAr: String? = nil,
        summary: String,
        summaryAr: String? = nil,
        category: String = "general",
        icon: String = "sparkles",
        version: String = "1.0.0",
        author: String = "UNIRAL",
        tools: [String] = [],
        triggers: [String] = [],
        instructions: String,
        source: SkillSource = .builtin,
        isEnabled: Bool = false,
        installedAt: Date? = nil
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.nameAr = nameAr
        self.summary = summary
        self.summaryAr = summaryAr
        self.category = category
        self.icon = icon
        self.version = version
        self.author = author
        self.tools = tools
        self.triggers = triggers
        self.instructions = instructions
        self.source = source
        self.isEnabled = isEnabled
        self.installedAt = installedAt
    }

    // MARK: Wire format

    /// The JSON wire format used for downloads, imports and exports.
    /// Uses snake_case keys and tolerates missing optional fields.
    public struct Wire: Codable {
        public var slug: String?
        public var name: String?
        public var nameAr: String?
        public var name_ar: String?
        public var summary: String?
        public var summaryAr: String?
        public var summary_ar: String?
        public var category: String?
        public var icon: String?
        public var version: String?
        public var author: String?
        public var instructions: String?
        public var tools: [String]?
        public var triggers: [String]?

        public func toSkill(source: SkillSource) -> Skill? {
            guard let slug, !slug.isEmpty,
                  let name, !name.isEmpty,
                  let instructions, !instructions.isEmpty else { return nil }
            return Skill(
                slug: slug,
                name: name,
                nameAr: nameAr ?? name_ar,
                summary: summary ?? "",
                summaryAr: summaryAr ?? summary_ar,
                category: category ?? "general",
                icon: (icon?.isEmpty ?? true) ? "sparkles" : icon!,
                version: version ?? "1.0.0",
                author: author ?? "unknown",
                tools: tools ?? [],
                triggers: triggers ?? [],
                instructions: instructions,
                source: source)
        }

        public static func from(_ skill: Skill) -> Wire {
            Wire(
                slug: skill.slug,
                name: skill.name,
                nameAr: skill.nameAr,
                summary: skill.summary,
                summaryAr: skill.summaryAr,
                category: skill.category,
                icon: skill.icon,
                version: skill.version,
                author: skill.author,
                instructions: skill.instructions,
                tools: skill.tools,
                triggers: skill.triggers)
        }
    }

    public func wire() -> Wire { Wire.from(self) }

    // MARK: Localization helpers

    /// Display name in the app's current language (Arabic name when
    /// available and the app runs in Arabic).
    public var displayName: String {
        if LocalizationManager.shared.effectiveCode == "ar",
           let nameAr, !nameAr.isEmpty {
            return nameAr
        }
        return name
    }

    public var displaySummary: String {
        if LocalizationManager.shared.effectiveCode == "ar",
           let summaryAr, !summaryAr.isEmpty {
            return summaryAr
        }
        return summary
    }
}

// MARK: - Skill source

public enum SkillSource: String, Codable {
    case builtin
    case registry
    case url
    case file
    case manual
}

// MARK: - Skill payload decoding

/// Decodes one skill or an array of skills from JSON data, accepting both
/// `{"skills": [...]}`, a bare array `[...]`, and a single object `{...}`.
public enum SkillPayload {
    public static func decode(_ data: Data, source: SkillSource) throws -> [Skill] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([Skill.Wire].self, from: data) {
            return list.compactMap { $0.toSkill(source: source) }
        }
        if let root = try? decoder.decode([String: Skill.Wire].self, from: data),
           let skill = root["skill"]?.toSkill(source: source) {
            return [skill]
        }
        if let root = try? decoder.decode([String: [Skill.Wire]].self, from: data),
           let list = root["skills"] {
            return list.compactMap { $0.toSkill(source: source) }
        }
        if let single = try? decoder.decode(Skill.Wire.self, from: data),
           let skill = single.toSkill(source: source) {
            return [skill]
        }
        throw SkillError.invalidFormat
    }

    public static func encode(_ skills: [Skill]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(["skills": skills.map { $0.wire() }])
    }
}

// MARK: - Errors

public enum SkillError: LocalizedError {
    case invalidFormat
    case network(String)
    case duplicate(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The skill file is not valid Astral skill JSON."
        case .network(let detail):
            return "Could not download the skill: \(detail)"
        case .duplicate(let slug):
            return "A skill named \"\(slug)\" is already installed."
        }
    }
}
