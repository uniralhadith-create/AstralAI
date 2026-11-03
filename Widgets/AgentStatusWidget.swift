import WidgetKit
import SwiftUI

// MARK: - Local palette (self-contained — the widget target cannot import the app's DesignSystem)

/// V3 monochrome palette mirroring the app's design language, declared
/// locally so this target stays fully self-contained. Paper-on-ink tones
/// only; success/danger keep their semantic hues.
enum WidgetPalette {
    static let spaceBlack = Color(red: 0.043, green: 0.043, blue: 0.051)
    static let spaceDeep = Color(red: 0.059, green: 0.059, blue: 0.066)
    static let nebulaDeep = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let nebulaViolet = Color(red: 0.85, green: 0.85, blue: 0.87)
    static let auroraCyan = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let starlight = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let moonDust = Color(red: 0.68, green: 0.68, blue: 0.72)
    static let success = Color(red: 0.204, green: 0.827, blue: 0.600)
    static let danger = Color(red: 0.973, green: 0.443, blue: 0.443)

    static let deepSpaceGradient = LinearGradient(
        colors: [spaceDeep, nebulaDeep],
        startPoint: .top,
        endPoint: .bottom)

    static let auroraGradient = LinearGradient(
        colors: [nebulaViolet, auroraCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    /// Clamps a progress value into 0...1 for the system progress views.
    static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - Timeline

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: AgentStatusSnapshot?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, snapshot: SharedStatusStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: .now, snapshot: SharedStatusStore.read())
        // Poll faster while an agent is working, lazily when idle.
        let refresh = Calendar.current.date(
            byAdding: .minute,
            value: (entry.snapshot?.running == true) ? 5 : 30,
            to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Widget

struct AgentStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentStatusWidget", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.deepSpaceGradient
                }
        }
        .configurationDisplayName("Astral Agent")
        .description("Live status of your autonomous agents.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - View

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var isArabic: Bool {
        Locale.current.language.languageCode?.identifier == "ar"
    }

    private var snapshot: AgentStatusSnapshot? { entry.snapshot }
    private var isRunning: Bool { snapshot?.running == true }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "astral://chat"))
    }

    // MARK: Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isRunning {
                runningHeader
                Text(snapshot?.goal ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetPalette.starlight)
                    .lineLimit(2)
                if let step = snapshot?.step, !step.isEmpty {
                    Text(step)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetPalette.auroraCyan)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                progressRow
            } else {
                idleLayout
            }
        }
        .padding(14)
    }

    // MARK: Medium

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(WidgetPalette.auroraGradient)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [WidgetPalette.spaceBlack.opacity(0.8), WidgetPalette.nebulaDeep.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(WidgetPalette.auroraCyan.opacity(0.35)))

            if isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    runningHeader
                    Text(snapshot?.goal ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WidgetPalette.starlight)
                        .lineLimit(1)
                    if let step = snapshot?.step, !step.isEmpty {
                        Text(step)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WidgetPalette.auroraCyan)
                            .lineLimit(1)
                    }
                    progressRow
                }
            } else {
                idleLayout
            }
        }
        .padding(14)
    }

    // MARK: Pieces

    private var runningHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetPalette.auroraCyan)
            Text(isArabic ? "الوكلاء يعملون" : "Agents at work")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetPalette.moonDust)
            Spacer(minLength: 0)
        }
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            ProgressView(value: WidgetPalette.clamped(snapshot?.progress ?? 0))
                .tint(WidgetPalette.auroraCyan)
            Text("\(Int(WidgetPalette.clamped(snapshot?.progress ?? 0) * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(WidgetPalette.moonDust)
        }
    }

    private var idleLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(WidgetPalette.auroraGradient)
            Text(isArabic ? "لا توجد مهام نشطة" : "No active agents")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetPalette.starlight.opacity(0.85))
            Text("Astral AI")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetPalette.moonDust)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
