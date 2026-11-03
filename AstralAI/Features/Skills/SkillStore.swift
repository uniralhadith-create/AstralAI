import Foundation
import Combine

// MARK: - Skill store

/// Owns the installed skill list: persistence, install / uninstall,
/// enable / disable, import from URL or file, and export.
///
/// The store is thread-safe: UI mutations are performed from the main
/// thread (SwiftUI views) while the agent core can read a consistent
/// snapshot from any thread — skills are injected into system prompts
/// while agent tasks run in the back.
public final class SkillStore: ObservableObject {

    public static let shared = SkillStore()

    // MARK: State

    /// Installed skills (built-in ones appear here once the user adds them
    /// from the library, plus anything downloaded/imported/created).
    @Published public private(set) var installed: [Skill] = []

    private let lock = NSLock()
    private var boxed: [Skill] = []

    private let directory: URL
    private let manifestURL: URL

    // MARK: Init

    public init(directory: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = directory ?? docs.appendingPathComponent("Skills", isDirectory: true)
        self.directory = dir
        self.manifestURL = dir.appendingPathComponent("skills.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Derived

    /// Skills currently enabled — what gets injected into prompts.
    public var enabledSkills: [Skill] {
        snapshot().filter(\.isEnabled)
    }

    /// The built-in library skills that are not installed yet.
    public var librarySkills: [Skill] {
        let installedSlugs = Set(snapshot().map(\.slug))
        return SkillCatalog.builtins.filter { !installedSlugs.contains($0.slug) }
    }

    public func skill(id: UUID) -> Skill? {
        snapshot().first { $0.id == id }
    }

    // MARK: Prompt injection

    /// The system-prompt block describing every enabled skill. Safe to call
    /// from any thread — returns a consistent snapshot.
    public func activePromptBlock() -> String {
        let enabled = snapshot().filter(\.isEnabled)
        guard !enabled.isEmpty else { return "" }
        var block = "ACTIVE SKILLS — specialized behaviors the user enabled. Follow the applicable skill instructions when they match the request:\n"
        for skill in enabled {
            block += "\n<skill name=\"\(skill.name)\" version=\"\(skill.version)\">\n"
            block += skill.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            block += "\n</skill>"
        }
        return block
    }

    /// Thread-safe snapshot of the installed list.
    private func snapshot() -> [Skill] {
        lock.lock()
        defer { lock.unlock() }
        return boxed
    }

    // MARK: Mutations

    /// Installs (or replaces, matching by slug) a skill, enabled by default.
    public func install(_ skill: Skill, enabled: Bool = true) {
        var updated = snapshot()
        var newSkill = skill
        newSkill.isEnabled = enabled
        newSkill.installedAt = Date()

        if let index = updated.firstIndex(where: { $0.slug == newSkill.slug }) {
            newSkill.isEnabled = updated[index].isEnabled && enabled
            updated[index] = newSkill
        } else {
            updated.append(newSkill)
        }
        commit(updated)
    }

    public func install(_ skills: [Skill], enabled: Bool = true) {
        for skill in skills {
            install(skill, enabled: enabled)
        }
    }

    public func uninstall(id: UUID) {
        commit(snapshot().filter { $0.id != id })
    }

    public func toggle(_ id: UUID) {
        var updated = snapshot()
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isEnabled.toggle()
        commit(updated)
    }

    public func setEnabled(_ id: UUID, _ value: Bool) {
        var updated = snapshot()
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isEnabled = value
        commit(updated)
    }

    public func update(_ skill: Skill) {
        var updated = snapshot()
        guard let index = updated.firstIndex(where: { $0.id == skill.id }) else { return }
        updated[index] = skill
        commit(updated)
    }

    /// Creates a skill from raw fields typed by the user.
    public func createManual(name: String, summary: String, instructions: String) throws -> Skill {
        let slug = Self.slugify(name)
        guard !slug.isEmpty else { throw SkillError.invalidFormat }
        let skill = Skill(
            slug: slug,
            name: name.trimmingCharacters(in: .whitespaces),
            summary: summary.trimmingCharacters(in: .whitespaces),
            category: "custom",
            icon: "sparkles",
            author: "You",
            instructions: instructions,
            source: .manual)
        install(skill)
        return skill
    }

    // MARK: Import / export

    /// Downloads a skill (or a list of skills) from a JSON URL.
    public func importFromURL(_ urlString: String) async throws -> [Skill] {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
            cleaned = "https://" + cleaned
        }
        guard let url = URL(string: cleaned) else {
            throw SkillError.network("invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SkillError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SkillError.network("HTTP \(http.statusCode)")
        }

        let skills = try SkillPayload.decode(data, source: .url)
        guard !skills.isEmpty else { throw SkillError.invalidFormat }
        install(skills)
        return skills
    }

    /// Imports skills from local JSON data (file picker / share sheet).
    public func importFromData(_ data: Data) throws -> [Skill] {
        let skills = try SkillPayload.decode(data, source: .file)
        guard !skills.isEmpty else { throw SkillError.invalidFormat }
        install(skills)
        return skills
    }

    /// Imports a skill from a `.skill.skill`, `.skill` or JSON file picked
    /// in the document picker. Tries the JSON payload format first; if the
    /// data isn't JSON, decodes it as UTF-8 text and builds a skill from it
    /// — the file name (extensions stripped) becomes the name, the whole
    /// text becomes the instructions and its first 120 characters the
    /// summary.
    public func importSkillFile(at url: URL) throws -> [Skill] {
        let data = try Data(contentsOf: url)

        // 1. Structured path: one skill or a list of skills as JSON.
        if let skills = try? SkillPayload.decode(data, source: .file), !skills.isEmpty {
            install(skills)
            return skills
        }

        // 2. Plain-text path: any readable non-empty text file becomes a
        //    skill whose instructions are the file's contents.
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = Self.stripSkillExtensions(url.lastPathComponent)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let slug = Self.slugify(name)
            if !trimmed.isEmpty, !slug.isEmpty {
                let skill = Skill(
                    slug: slug,
                    name: name,
                    summary: String(trimmed.prefix(120)),
                    category: "imported",
                    icon: "sparkles",
                    instructions: text,
                    source: .file)
                install(skill)
                return [skill]
            }
        }

        throw SkillError.invalidFormat
    }

    /// Strips the known skill file extensions (longest match first) from a
    /// file name, preserving the display case of what remains.
    private static func stripSkillExtensions(_ filename: String) -> String {
        let suffixes = [".skill.skill", ".skill", ".json"]
        for suffix in suffixes where filename.lowercased().hasSuffix(suffix) {
            return String(filename.dropLast(suffix.count))
        }
        return filename
    }

    /// Exports one installed skill as a shareable `\(slug).skill.skill`
    /// file (JSON payload) in Documents and returns its URL.
    public func exportFileURL(for id: UUID) throws -> URL {
        guard let skill = skill(id: id) else { throw SkillError.invalidFormat }
        let data = try SkillPayload.encode([skill])
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("\(skill.slug).skill.skill")
        try data.write(to: url, options: [.atomic])
        return url
    }

    /// Exports one installed skill as pretty JSON.
    public func export(id: UUID) throws -> Data {
        guard let skill = skill(id: id) else { throw SkillError.invalidFormat }
        return try SkillPayload.encode([skill])
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let saved = try? JSONDecoder().decode([Skill].self, from: data) else {
            // First launch: ship with Deep Research pre-installed.
            commit(SkillCatalog.builtins.filter { $0.slug == "deep-research" })
            return
        }
        commit(saved)
    }

    private func commit(_ skills: [Skill], save: Bool = true) {
        lock.lock()
        boxed = skills
        lock.unlock()

        installed = skills

        if save {
            persist(skills)
        }
    }

    private func persist(_ skills: [Skill]) {
        do {
            let data = try JSONEncoder().encode(skills)
            try data.write(to: manifestURL, options: [.atomic, .completeFileProtection])
        } catch {
            NSLog("SkillStore: failed to persist skills: \(error.localizedDescription)")
        }
    }

    // MARK: Helpers

    public static func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var slug = ""
        var lastDash = false
        for char in lowered {
            let isASCIIAlphanumeric = (char.isLetter || char.isNumber) && char.isASCII
            if isASCIIAlphanumeric {
                slug.append(char)
                lastDash = false
            } else if !lastDash && !slug.isEmpty {
                slug.append("-")
                lastDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }
}
