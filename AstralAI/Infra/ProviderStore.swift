import Foundation

// MARK: - Provider store

/// Owns the user's provider configurations, persists them to
/// `Documents/AstralAI/providers.json`, keeps the API keys in the Keychain
/// and exposes the shared LLM client bound to the active provider.
@MainActor
final class ProviderStore: ObservableObject {

    @Published private(set) var providers: [ProviderConfig]
    @Published var activeProviderID: UUID?

    /// The unified LLM client consumed by the agent core.
    let llm: LLMService

    /// Thread-safe snapshot of the active provider. A dedicated reference
    /// type is used because the configProvider closure is created before
    /// the store finishes initializing, so it must not capture `self`.
    private final class ActiveSnapshot {
        let lock = NSLock()
        var value: ProviderConfig?
    }

    private let snapshot: ActiveSnapshot

    private static let activeIDKey = "astral.activeProviderID"

    private static var storageDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("AstralAI", isDirectory: true)
    }

    private static var storageURL: URL {
        storageDirectory.appendingPathComponent("providers.json")
    }

    /// The configuration of the currently active provider, if any.
    var active: ProviderConfig? {
        providers.first { $0.id == activeProviderID }
    }

    init() {
        // 1. Load persisted providers.
        var loaded: [ProviderConfig] = []
        if let data = try? Data(contentsOf: Self.storageURL),
           let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            loaded = decoded
        }
        providers = loaded

        // 2. Restore the active selection; fall back to the first provider.
        //    Resolved through locals because `self` cannot be read (methods,
        //    computed properties) until every stored property is assigned.
        let savedID = UserDefaults.standard
            .string(forKey: Self.activeIDKey)
            .flatMap(UUID.init(uuidString:))
        var initialActive: ProviderConfig?
        if let savedID, loaded.contains(where: { $0.id == savedID }) {
            activeProviderID = savedID
            initialActive = loaded.first { $0.id == savedID }
        } else if let first = loaded.first {
            activeProviderID = first.id
            initialActive = first
        } else {
            activeProviderID = nil
            initialActive = nil
        }

        // 3. Seed the thread-safe snapshot box.
        let snapshot = ActiveSnapshot()
        snapshot.value = initialActive
        self.snapshot = snapshot

        // 4. Create the LLM client last. The closure captures only the
        //    snapshot box (weakly), keeping cross-thread reads lock-guarded
        //    while letting the store finish initializing safely.
        llm = LLMService(configProvider: { [weak snapshot] in
            guard let snapshot else { return nil }
            snapshot.lock.lock()
            defer { snapshot.lock.unlock() }
            return snapshot.value
        })

        // 5. All stored properties are assigned; self is usable now.
        persistActiveID()
    }

    // MARK: - Mutations

    func setActive(_ id: UUID) {
        guard providers.contains(where: { $0.id == id }) else { return }
        guard activeProviderID != id else { return }
        activeProviderID = id
        persistActiveID()
        refreshSnapshot()
        persist()
    }

    func add(_ config: ProviderConfig) {
        guard !providers.contains(where: { $0.id == config.id }) else { return }
        providers.append(config)
        if activeProviderID == nil {
            activeProviderID = config.id
            persistActiveID()
        }
        refreshSnapshot()
        persist()
    }

    func update(_ config: ProviderConfig) {
        guard let index = providers.firstIndex(where: { $0.id == config.id }) else { return }
        providers[index] = config
        refreshSnapshot()
        persist()
    }

    func delete(_ id: UUID) {
        providers.removeAll { $0.id == id }
        try? KeychainStore.delete(account: id.uuidString)
        if activeProviderID == id {
            activeProviderID = providers.first?.id
            persistActiveID()
        }
        refreshSnapshot()
        persist()
    }

    // MARK: - API keys

    func saveKey(_ key: String, for id: UUID) {
        guard !key.isEmpty else { return }
        try? KeychainStore.save(key, account: id.uuidString)
    }

    func key(for id: UUID) -> String? {
        try? KeychainStore.get(account: id.uuidString)
    }

    // MARK: - Model discovery

    /// Discovers the models exposed by any persisted provider (active or not).
    func discoverModels(for id: UUID) async throws -> [ModelInfo] {
        guard let config = providers.first(where: { $0.id == id }) else {
            throw LLMError.badResponse("Provider not found")
        }
        let apiKey = key(for: id)
        return try await LLMService.fetchModels(config: config, apiKey: apiKey)
    }

    // MARK: - Persistence

    /// Publishes the current active provider to the lock-guarded snapshot
    /// consumed by the LLM client on background threads.
    private func refreshSnapshot() {
        snapshot.lock.lock()
        snapshot.value = active
        snapshot.lock.unlock()
    }

    private func persistActiveID() {
        if let id = activeProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.activeIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeIDKey)
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: Self.storageDirectory,
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(providers)
            try data.write(to: Self.storageURL, options: [.atomic])
        } catch {
            // Persistence is best-effort; the in-memory state stays usable
            // and the next mutation retries the write.
            print("ProviderStore: failed to persist providers (\(error.localizedDescription))")
        }
    }
}
