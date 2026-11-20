import Foundation
import SwiftUI

// MARK: - Google Antigravity Plan Tiers

/// Subscription plan tiers supported by Google Antigravity IDE.
/// Each tier automatically unlocks the corresponding Google DeepMind Gemini
/// models and rate limits inside Astral AI — no PC required.
public enum AntigravityPlanTier: String, Codable, CaseIterable, Identifiable, Comparable {
    case free = "free"
    case pro = "pro"
    case ultra = "ultra"
    case enterprise = "enterprise"

    public var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .free: return 0
        case .pro: return 1
        case .ultra: return 2
        case .enterprise: return 3
        }
    }

    public static func < (lhs: AntigravityPlanTier, rhs: AntigravityPlanTier) -> Bool {
        lhs.rank < rhs.rank
    }

    public var displayName: String {
        switch self {
        case .free: return "Free / AI Plus"
        case .pro: return "Google AI Pro"
        case .ultra: return "Google AI Ultra"
        case .enterprise: return "Gemini Enterprise"
        }
    }

    public var localizedName: String {
        let isArabic = LocalizationManager.shared.effectiveCode == "ar"
        switch self {
        case .free: return isArabic ? "المجانية / AI Plus" : "Free / AI Plus"
        case .pro: return isArabic ? "Google AI Pro" : "Google AI Pro"
        case .ultra: return isArabic ? "Google AI Ultra (5x)" : "Google AI Ultra (5x)"
        case .enterprise: return isArabic ? "Gemini Enterprise" : "Gemini Enterprise"
        }
    }

    public var rateLimitSummary: String {
        let isArabic = LocalizationManager.shared.effectiveCode == "ar"
        switch self {
        case .free:
            return isArabic
                ? "نماذج Gemini 4 Hydrogen و Gemini 3.8/3.7 Flash مجاناً"
                : "Gemini 4 Hydrogen & Gemini 3.8/3.7 Flash included"
        case .pro:
            return isArabic
                ? "يفتح Gemini 4 Neon و Orchestrator و Gemini 3.1 Pro بحدود استخدام أعلى"
                : "Unlocks Gemini 4 Neon, Orchestrator & Gemini 3.1 Pro with expanded limits"
        case .ultra:
            return isArabic
                ? "أعلى حدود استخدام (5x) مع Gemini 4 Carbon و Gemini 4 Argon و Orchestrator"
                : "Highest 5x rate limits with Gemini 4 Carbon, Argon & Orchestrator"
        case .enterprise:
            return isArabic
                ? "حماية Google Cloud الكاملة مع جميع نماذج Gemini 4 و 3.x"
                : "Full Google Cloud security controls with all Gemini 4 & 3.x models"
        }
    }

    public var accentColor: Color {
        switch self {
        case .free: return Color(red: 0.35, green: 0.68, blue: 0.98)
        case .pro: return Color(red: 0.56, green: 0.45, blue: 0.98)
        case .ultra: return Color(red: 0.98, green: 0.68, blue: 0.24)
        case .enterprise: return Color(red: 0.19, green: 0.82, blue: 0.35)
        }
    }
}

// MARK: - Antigravity Thinking Levels

/// Reasoning effort budget supported by Google Antigravity models.
public enum AntigravityThinkingLevel: String, Codable, CaseIterable, Identifiable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case extra = "xhigh"

    public var id: String { rawValue }

    public var label: String {
        let isArabic = LocalizationManager.shared.effectiveCode == "ar"
        switch self {
        case .low: return isArabic ? "منخفض" : "Low"
        case .medium: return isArabic ? "متوسط" : "Medium"
        case .high: return isArabic ? "عالي" : "High"
        case .extra: return isArabic ? "فائق (Extra)" : "Extra"
        }
    }
}

// MARK: - Antigravity Model Descriptor

public struct AntigravityModelDescriptor: Identifiable, Codable, Equatable {
    public let id: String
    public let apiModelID: String
    public let name: String
    public let subtitle: String
    public let subtitleAr: String
    public let contextWindow: String
    public let minimumTier: AntigravityPlanTier
    public let supportsExtraThinking: Bool
    public let isOrchestrator: Bool
    public let badge: String?

    public var localizedSubtitle: String {
        LocalizationManager.shared.effectiveCode == "ar" ? subtitleAr : subtitle
    }

    public func isUnlocked(for tier: AntigravityPlanTier) -> Bool {
        tier >= minimumTier
    }
}

public enum AntigravityModelCatalog {
    /// Curated Google Antigravity model catalog aligned with Google AI plans.
    public static let all: [AntigravityModelDescriptor] = [
        AntigravityModelDescriptor(
            id: "gemini-4-hydrogen",
            apiModelID: "gemini-4-hydrogen",
            name: "Gemini 4 Hydrogen",
            subtitle: "Fast agentic coding & everyday workflows",
            subtitleAr: "سريع للبرمجة الذاتية ومهام الوكيل اليومية",
            contextWindow: "1M",
            minimumTier: .free,
            supportsExtraThinking: true,
            isOrchestrator: false,
            badge: "FREE+"),
        AntigravityModelDescriptor(
            id: "gemini-3.8-flash",
            apiModelID: "gemini-3.8-flash",
            name: "Gemini 3.8 Flash",
            subtitle: "Balanced speed & multi-file edits",
            subtitleAr: "سرعة متوازنة لتعديل الملفات المتعددة",
            contextWindow: "1M",
            minimumTier: .free,
            supportsExtraThinking: false,
            isOrchestrator: false,
            badge: "FAST"),
        AntigravityModelDescriptor(
            id: "gemini-2.5-flash",
            apiModelID: "gemini-2.5-flash",
            name: "Gemini 2.5 Flash",
            subtitle: "Widely available Gemini API workhorse",
            subtitleAr: "متاح على نطاق واسع عبر Gemini API",
            contextWindow: "1M",
            minimumTier: .free,
            supportsExtraThinking: false,
            isOrchestrator: false,
            badge: "STABLE"),
        AntigravityModelDescriptor(
            id: "gemini-4-neon",
            apiModelID: "gemini-4-neon",
            name: "Gemini 4 Neon",
            subtitle: "Default frontier reasoning & architecture model",
            subtitleAr: "نموذج التفكير المتقدم وهندسة الأنظمة الافتراضي",
            contextWindow: "512K",
            minimumTier: .pro,
            supportsExtraThinking: true,
            isOrchestrator: false,
            badge: "PRO"),
        AntigravityModelDescriptor(
            id: "orchestrator-neon",
            apiModelID: "gemini-4-neon",
            name: "Orchestrator (Neon)",
            subtitle: "Plans with Neon, executes fast with Hydrogen",
            subtitleAr: "يخطط بـ Neon وينفذ بسرعة عبر Hydrogen",
            contextWindow: "512K",
            minimumTier: .pro,
            supportsExtraThinking: true,
            isOrchestrator: true,
            badge: "AUTO"),
        AntigravityModelDescriptor(
            id: "gemini-3.1-pro",
            apiModelID: "gemini-3.1-pro",
            name: "Gemini 3.1 Pro",
            subtitle: "Deep codebase debugging & refactoring",
            subtitleAr: "تصحيح أخطاء عميق وإعادة هيكلة المشاريع",
            contextWindow: "1M",
            minimumTier: .pro,
            supportsExtraThinking: false,
            isOrchestrator: false,
            badge: "PRO"),
        AntigravityModelDescriptor(
            id: "gemini-2.5-pro",
            apiModelID: "gemini-2.5-pro",
            name: "Gemini 2.5 Pro",
            subtitle: "Reliable deep coding via Google AI Studio",
            subtitleAr: "برمجة عميقة مستقرة عبر Google AI Studio",
            contextWindow: "1M",
            minimumTier: .pro,
            supportsExtraThinking: false,
            isOrchestrator: false,
            badge: "PRO"),
        AntigravityModelDescriptor(
            id: "gemini-4-carbon",
            apiModelID: "gemini-4-carbon",
            name: "Gemini 4 Carbon",
            subtitle: "Frontier long-horizon systems reasoning",
            subtitleAr: "تفكير استراتيجي طويل المدى للمشاريع المعقدة",
            contextWindow: "1M",
            minimumTier: .ultra,
            supportsExtraThinking: false,
            isOrchestrator: false,
            badge: "ULTRA"),
        AntigravityModelDescriptor(
            id: "gemini-4-argon",
            apiModelID: "gemini-4-argon",
            name: "Gemini 4 Argon",
            subtitle: "Maximum depth for hardest engineering tasks",
            subtitleAr: "أقصى عمق هندسي لحل أعقد المشكلات البرمجية",
            contextWindow: "1M",
            minimumTier: .ultra,
            supportsExtraThinking: false,
            isOrchestrator: false,
            badge: "ULTRA 5x"),
        AntigravityModelDescriptor(
            id: "orchestrator-argon",
            apiModelID: "gemini-4-argon",
            name: "Orchestrator (Argon)",
            subtitle: "Plans with Argon, implements with Hydrogen",
            subtitleAr: "يخطط بـ Argon وينفذ الكود بسرعة عبر Hydrogen",
            contextWindow: "1M",
            minimumTier: .ultra,
            supportsExtraThinking: true,
            isOrchestrator: true,
            badge: "ULTRA"),
    ]

    public static func models(for tier: AntigravityPlanTier) -> [AntigravityModelDescriptor] {
        all.filter { $0.isUnlocked(for: tier) }
    }

    public static func defaultModel(for tier: AntigravityPlanTier) -> AntigravityModelDescriptor {
        switch tier {
        case .free:
            return all.first { $0.id == "gemini-4-hydrogen" } ?? all[0]
        case .pro:
            return all.first { $0.id == "gemini-4-neon" } ?? all[0]
        case .ultra, .enterprise:
            return all.first { $0.id == "gemini-4-argon" } ?? all[0]
        }
    }
}

// MARK: - Auth Method & Connected Account

public enum AntigravityAuthMethod: String, Codable {
    case googleOAuth = "google_oauth"
    case aiStudioKey = "ai_studio_key"
}

public struct AntigravityAccount: Codable, Equatable {
    public var email: String
    public var displayName: String
    public var planTier: AntigravityPlanTier
    public var authMethod: AntigravityAuthMethod
    public var connectedAt: Date
    public var discoveredModels: [String]
    public var syncedProviderID: UUID?
    public var quotaRemainingPercent: Int
}

// MARK: - IDE Mission & Artifacts

public enum AntigravityArtifactKind: String, Codable {
    case plan = "plan"
    case codeDiff = "diff"
    case terminal = "terminal"
    case walkthrough = "walkthrough"
}

public struct AntigravityArtifact: Identifiable, Codable, Equatable {
    public let id: UUID
    public var kind: AntigravityArtifactKind
    public var title: String
    public var filePath: String?
    public var content: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: AntigravityArtifactKind,
        title: String,
        filePath: String? = nil,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.filePath = filePath
        self.content = content
        self.createdAt = createdAt
    }
}

public enum AntigravityMissionStatus: String, Codable {
    case planning
    case coding
    case verifying
    case completed
    case failed
}

public struct AntigravityMission: Identifiable, Codable, Equatable {
    public let id: UUID
    public var prompt: String
    public var modelName: String
    public var thinkingLevel: AntigravityThinkingLevel
    public var status: AntigravityMissionStatus
    public var summary: String
    public var artifacts: [AntigravityArtifact]
    public var touchedFiles: [String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        prompt: String,
        modelName: String,
        thinkingLevel: AntigravityThinkingLevel,
        status: AntigravityMissionStatus = .planning,
        summary: String = "",
        artifacts: [AntigravityArtifact] = [],
        touchedFiles: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.modelName = modelName
        self.thinkingLevel = thinkingLevel
        self.status = status
        self.summary = summary
        self.artifacts = artifacts
        self.touchedFiles = touchedFiles
        self.createdAt = createdAt
    }
}
