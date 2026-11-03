import Foundation
import SwiftUI

// MARK: - Language selection

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case arabic
    case english

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return L("lang.system", "Shared")
        case .arabic: return "العربية"
        case .english: return "English"
        }
    }

    public var code: String? {
        switch self {
        case .system: return nil
        case .arabic: return "ar"
        case .english: return "en"
        }
    }
}

// MARK: - Localization Manager

/// In-app language switcher with bundle-level string lookup.
/// Falls back to the system language, then to the key itself.
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    private static let storageKey = "astral.appLanguage"

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
            Self.directionCache = nil
        }
    }

    private var bundleCache: [String: Bundle] = [:]
    private let lock = NSLock()
    private static var directionCache: LayoutDirection?

    public var effectiveCode: String {
        if let code = language.code { return code }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ar") ? "ar" : "en"
    }

    public var isRTL: Bool { effectiveCode == "ar" }

    public var layoutDirection: LayoutDirection {
        if let cached = Self.directionCache { return cached }
        let dir: LayoutDirection = isRTL ? .rightToLeft : .leftToRight
        Self.directionCache = dir
        return dir
    }

    public init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    private func bundle(for code: String) -> Bundle {
        lock.lock()
        defer { lock.unlock() }
        if let cached = bundleCache[code] { return cached }
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            bundleCache[code] = bundle
            return bundle
        }
        return .main
    }

    /// Looks up a localized string in the given table.
    public func string(_ key: String, table: String) -> String {
        let code = effectiveCode
        let tableBundle = bundle(for: code)
        var value = tableBundle.localizedString(forKey: key, value: key, table: table)
        if value == key, code != "en" {
            // Fall back to English table, then the raw key.
            let english = bundle(for: "en")
            value = english.localizedString(forKey: key, value: key, table: table)
        }
        return value
    }
}

/// Global localized string lookup: L("key", "TableName")
@inline(__always)
public func L(_ key: String, _ table: String = "Shared") -> String {
    LocalizationManager.shared.string(key, table: table)
}

/// Localized string as a SwiftUI binding-friendly value.
public struct LocalizedText: Equatable {
    public let key: String
    public let table: String
    public init(_ key: String, _ table: String = "Shared") {
        self.key = key
        self.table = table
    }
    public var text: String { L(key, table) }
}
