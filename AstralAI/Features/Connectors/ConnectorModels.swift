import Foundation
import SwiftUI

// MARK: - Connector Categories

public enum ConnectorCategory: String, CaseIterable, Identifiable, Codable {
    case developer
    case messaging
    case productivity
    case searchMedia
    case mcp

    public var id: String { rawValue }

    public var title: String {
        let isArabic = LocalizationManager.shared.effectiveCode == "ar"
        switch self {
        case .developer: return isArabic ? "المطورون" : "Developer"
        case .messaging: return isArabic ? "المراسلة" : "Messaging"
        case .productivity: return isArabic ? "الإنتاجية" : "Productivity"
        case .searchMedia: return isArabic ? "البحث والوسائط" : "Search & Media"
        case .mcp: return "MCP & APIs"
        }
    }
}

// MARK: - Built-in Connector & Plugin Catalog

public enum ConnectorKind: String, CaseIterable, Identifiable, Codable {
    case github
    case telegram
    case mcp
    case notion
    case slack
    case discord
    case linear
    case trello
    case googleDrive
    case braveSearch
    case tavily
    case vercel
    case supabase
    case cobaltVideo
    case webhook

    public var id: String { rawValue }

    public var category: ConnectorCategory {
        switch self {
        case .github, .linear, .vercel, .supabase: return .developer
        case .telegram, .slack, .discord: return .messaging
        case .notion, .trello, .googleDrive: return .productivity
        case .braveSearch, .tavily, .cobaltVideo: return .searchMedia
        case .mcp, .webhook: return .mcp
        }
    }

    public var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .telegram: return "Telegram Bot Agent"
        case .mcp: return "MCP Servers"
        case .notion: return "Notion"
        case .slack: return "Slack"
        case .discord: return "Discord"
        case .linear: return "Linear"
        case .trello: return "Trello"
        case .googleDrive: return "Google Drive"
        case .braveSearch: return "Brave Search"
        case .tavily: return "Tavily AI Search"
        case .vercel: return "Vercel"
        case .supabase: return "Supabase"
        case .cobaltVideo: return "Video Downloader API"
        case .webhook: return "Custom Webhook"
        }
    }

    public var localizedSubtitle: String {
        let ar = LocalizationManager.shared.effectiveCode == "ar"
        switch self {
        case .github:
            return ar ? "المستودعات، الملفات، الـ Issues، الـ PRs والبحث في الكود" : "Repos, files, issues, PRs & code search"
        case .telegram:
            return ar ? "إدارة البوت والرد التلقائي الذكي على رسائل تليجرام" : "Live Telegram bot management & AI auto-reply"
        case .mcp:
            return ar ? "ربط خوادم Model Context Protocol واكتشاف أدواتها تلقائياً" : "Connect remote MCP servers & auto-discover tools"
        case .notion:
            return ar ? "البحث في صفحات Notion وقراءتها وإنشاء ملاحظات" : "Search, read & create Notion pages"
        case .slack:
            return ar ? "قراءة القنوات وإرسال رسائل وتنبيهات الفريق" : "Read channels & post team updates"
        case .discord:
            return ar ? "إرسال رسائل وتنبيهات لقنوات Discord عبر Webhook" : "Send messages & embeds via Discord webhooks"
        case .linear:
            return ar ? "عرض وإنشاء مهام و Issues فرق التطوير" : "List & create engineering issues"
        case .trello:
            return ar ? "إدارة اللوحات وإضافة البطاقات والمهام" : "Manage boards, lists & cards"
        case .googleDrive:
            return ar ? "البحث في ملفات Google Drive وقراءتها" : "Search & read Google Drive documents"
        case .braveSearch:
            return ar ? "بحث ويب فوري عالي الدقة للوكيل الذكي" : "Fast real-time web search API for the agent"
        case .tavily:
            return ar ? "بحث ذكي عميق واستخراج محتوى الصفحات" : "Deep AI research & content extraction"
        case .vercel:
            return ar ? "متابعة المشاريع وحالة النشر على Vercel" : "Monitor Vercel projects & deployments"
        case .supabase:
            return ar ? "الاستعلام المباشر عن جداول ووظائف Supabase" : "Query Supabase REST tables & RPCs"
        case .cobaltVideo:
            return ar ? "رابط API (مثل Cobalt) لتحميل فيديوهات يوتيوب وتيك توك" : "Cobalt-compatible API for YouTube/TikTok downloads"
        case .webhook:
            return ar ? "استدعاء أي REST API أو Webhook مخصص" : "Trigger any custom REST API or webhook"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .telegram: return "paperplane.fill"
        case .mcp: return "point.3.connected.trianglepath.dotted"
        case .notion: return "doc.richtext.fill"
        case .slack: return "number.square.fill"
        case .discord: return "bubble.left.and.exclamationmark.bubble.right.fill"
        case .linear: return "circle.lefthalf.filled"
        case .trello: return "rectangle.split.3x1.fill"
        case .googleDrive: return "externaldrive.fill.badge.icloud"
        case .braveSearch: return "magnifyingglass.circle.fill"
        case .tavily: return "globe.americas.fill"
        case .vercel: return "triangle.fill"
        case .supabase: return "bolt.shield.fill"
        case .cobaltVideo: return "play.rectangle.fill"
        case .webhook: return "link.circle.fill"
        }
    }

    public var monogram: String {
        switch self {
        case .github: return "GH"
        case .telegram: return "TG"
        case .mcp: return "MCP"
        case .notion: return "N"
        case .slack: return "SL"
        case .discord: return "DC"
        case .linear: return "LN"
        case .trello: return "TR"
        case .googleDrive: return "GD"
        case .braveSearch: return "BR"
        case .tavily: return "TV"
        case .vercel: return "▲"
        case .supabase: return "SB"
        case .cobaltVideo: return "VD"
        case .webhook: return "API"
        }
    }

    public var brandColors: [Color] {
        switch self {
        case .github: return [Color(red: 0.16, green: 0.18, blue: 0.22), Color(red: 0.30, green: 0.34, blue: 0.42)]
        case .telegram: return [Color(red: 0.14, green: 0.64, blue: 0.94), Color(red: 0.08, green: 0.48, blue: 0.82)]
        case .mcp: return [Color(red: 0.46, green: 0.36, blue: 0.96), Color(red: 0.24, green: 0.68, blue: 0.98)]
        case .notion: return [Color(red: 0.20, green: 0.20, blue: 0.22), Color(red: 0.38, green: 0.38, blue: 0.42)]
        case .slack: return [Color(red: 0.88, green: 0.18, blue: 0.44), Color(red: 0.36, green: 0.18, blue: 0.52)]
        case .discord: return [Color(red: 0.35, green: 0.40, blue: 0.95), Color(red: 0.25, green: 0.28, blue: 0.78)]
        case .linear: return [Color(red: 0.37, green: 0.42, blue: 0.92), Color(red: 0.22, green: 0.24, blue: 0.65)]
        case .trello: return [Color(red: 0.00, green: 0.48, blue: 0.80), Color(red: 0.00, green: 0.66, blue: 0.92)]
        case .googleDrive: return [Color(red: 0.20, green: 0.66, blue: 0.33), Color(red: 0.26, green: 0.52, blue: 0.96)]
        case .braveSearch: return [Color(red: 0.98, green: 0.33, blue: 0.12), Color(red: 0.96, green: 0.56, blue: 0.14)]
        case .tavily: return [Color(red: 0.16, green: 0.72, blue: 0.64), Color(red: 0.10, green: 0.48, blue: 0.78)]
        case .vercel: return [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.32, green: 0.32, blue: 0.36)]
        case .supabase: return [Color(red: 0.24, green: 0.81, blue: 0.56), Color(red: 0.11, green: 0.56, blue: 0.42)]
        case .cobaltVideo: return [Color(red: 0.92, green: 0.24, blue: 0.36), Color(red: 0.68, green: 0.22, blue: 0.86)]
        case .webhook: return [Color(red: 0.96, green: 0.62, blue: 0.14), Color(red: 0.86, green: 0.38, blue: 0.18)]
        }
    }

    public var tokenLabel: String {
        let ar = LocalizationManager.shared.effectiveCode == "ar"
        switch self {
        case .github: return ar ? "Personal Access Token (ghp_...)" : "Personal Access Token (ghp_...)"
        case .telegram: return ar ? "Telegram Bot Token (من @BotFather)" : "Telegram Bot Token (@BotFather)"
        case .mcp: return ar ? "Bearer Token (اختياري)" : "Bearer Token (Optional)"
        case .notion: return ar ? "Notion Integration Secret (ntn_...)" : "Notion Integration Secret (ntn_...)"
        case .slack: return ar ? "Slack Bot Token (xoxb-...)" : "Slack Bot Token (xoxb-...)"
        case .discord: return ar ? "Discord Webhook URL أو Bot Token" : "Discord Webhook URL or Bot Token"
        case .linear: return ar ? "Linear API Key (lin_api_...)" : "Linear API Key (lin_api_...)"
        case .trello: return ar ? "Trello API Key:Token (مفصول بـ :)" : "Trello Key:Token (colon-separated)"
        case .googleDrive: return ar ? "Google OAuth Access Token" : "Google OAuth Access Token"
        case .braveSearch: return ar ? "Brave Search Subscription Token" : "Brave Search API Key"
        case .tavily: return ar ? "Tavily API Key (tvly-...)" : "Tavily API Key (tvly-...)"
        case .vercel: return ar ? "Vercel Access Token" : "Vercel Access Token"
        case .supabase: return ar ? "Supabase Anon / Service Key" : "Supabase Anon / Service Key"
        case .cobaltVideo: return ar ? "مفتاح API (اختياري لخوادم Cobalt)" : "API Key (Optional for Cobalt)"
        case .webhook: return ar ? "Bearer Token / Secret (اختياري)" : "Bearer Token / Secret (Optional)"
        }
    }

    public var secondaryLabel: String? {
        let ar = LocalizationManager.shared.effectiveCode == "ar"
        switch self {
        case .mcp: return ar ? "رابط خادم MCP الافتراضي (https://...)" : "Default MCP Endpoint URL (https://...)"
        case .supabase: return ar ? "رابط مشروع Supabase (https://xxx.supabase.co)" : "Supabase Project URL (https://xxx.supabase.co)"
        case .cobaltVideo: return ar ? "رابط API التحميل (مثل https://api.cobalt.tools)" : "Downloader Endpoint URL (e.g. Cobalt API)"
        case .webhook: return ar ? "رابط الـ Webhook الافتراضي (https://...)" : "Default Webhook URL (https://...)"
        default: return nil
        }
    }

    public var requiresToken: Bool {
        switch self {
        case .mcp, .cobaltVideo, .webhook: return false
        default: return true
        }
    }

    public var docsURL: String {
        switch self {
        case .github: return "https://github.com/settings/tokens"
        case .telegram: return "https://t.me/BotFather"
        case .mcp: return "https://modelcontextprotocol.io"
        case .notion: return "https://www.notion.so/my-integrations"
        case .slack: return "https://api.slack.com/apps"
        case .discord: return "https://discord.com/developers/applications"
        case .linear: return "https://linear.app/settings/api"
        case .trello: return "https://trello.com/power-ups/admin"
        case .googleDrive: return "https://console.cloud.google.com/apis/library/drive.googleapis.com"
        case .braveSearch: return "https://api.search.brave.com/"
        case .tavily: return "https://app.tavily.com/"
        case .vercel: return "https://vercel.com/account/tokens"
        case .supabase: return "https://supabase.com/dashboard"
        case .cobaltVideo: return "https://cobalt.tools"
        case .webhook: return "https://astral.uniral.app"
        }
    }
}

// MARK: - MCP Server Models

public struct MCPDiscoveredTool: Identifiable, Codable, Equatable {
    public var id: String { name }
    public let name: String
    public let description: String
}

public struct MCPServerConfig: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var endpointURL: String
    public var isEnabled: Bool
    public var discoveredTools: [MCPDiscoveredTool]

    public init(
        id: UUID = UUID(),
        name: String,
        endpointURL: String,
        isEnabled: Bool = true,
        discoveredTools: [MCPDiscoveredTool] = []
    ) {
        self.id = id
        self.name = name
        self.endpointURL = endpointURL
        self.isEnabled = isEnabled
        self.discoveredTools = discoveredTools
    }
}

// MARK: - Branded Connector Icon View

public struct ConnectorBrandIcon: View {
    public let kind: ConnectorKind
    public var size: CGFloat = 40

    public init(kind: ConnectorKind, size: CGFloat = 40) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: kind.brandColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.9))

            Image(systemName: kind.sfSymbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
    }
}
