import WidgetKit
import SwiftUI
import ActivityKit

/// Astral AI Live Activity & Dynamic Island — Liquid Glass Edition.
/// Crisp, high-contrast layout across Compact, Minimal, Expanded, and Lock Screen
/// presentations with glowing active status ring, live progress capsule,
/// step label, and terminal verdict badge.
struct AgentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .containerBackground(for: .widget) {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(red: 0.045, green: 0.055, blue: 0.075),
                                Color(red: 0.095, green: 0.11, blue: 0.145),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing)
                        RadialGradient(
                            colors: [
                                accentColor(for: context.state.status).opacity(0.18),
                                Color.clear,
                            ],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 180)
                    }
                }
        } dynamicIsland: { context in
            let progress = WidgetPalette.clamped(context.state.progress)
            let accent = accentColor(for: context.state.status)

            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.20))
                                .frame(width: 30, height: 30)
                            Circle()
                                .strokeBorder(accent.opacity(0.55), lineWidth: 1.2)
                                .frame(width: 30, height: 30)
                            Image(systemName: statusSymbol(for: context.state.status))
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(accent)
                        }
                        Text("Astral")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accent.opacity(0.16)))
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.goal)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.state.step)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [accent, Color.white.opacity(0.9)],
                                            startPoint: .leading,
                                            endPoint: .trailing))
                                    .frame(width: max(8, geo.size.width * progress))
                            }
                        }
                        .frame(height: 6)
                        .padding(.horizontal, 4)
                    }
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.22))
                        .frame(width: 22, height: 22)
                    Image(systemName: statusSymbol(for: context.state.status))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(accent)
                }
            } compactTrailing: {
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.20), lineWidth: 2.2)
                        Circle()
                            .trim(from: 0, to: max(0.08, progress))
                            .stroke(accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 14, height: 14)

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .fixedSize()
                }
                .padding(.trailing, 2)
            } minimal: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.20), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.10, progress))
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: statusSymbol(for: context.state.status))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 20, height: 20)
            }
            .keylineTint(accent)
        }
    }

    private func accentColor(for status: String) -> Color {
        switch status {
        case "done": return WidgetPalette.success
        case "failed": return WidgetPalette.danger
        default: return Color(red: 0.24, green: 0.86, blue: 0.58)
        }
    }

    private func statusSymbol(for status: String) -> String {
        switch status {
        case "done": return "checkmark"
        case "failed": return "xmark"
        default: return "sparkles"
        }
    }
}

// MARK: - Lock Screen Live Activity Banner

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<AgentActivityAttributes>

    private var progress: Double {
        WidgetPalette.clamped(context.state.progress)
    }

    private var accent: Color {
        switch context.state.status {
        case "done": return WidgetPalette.success
        case "failed": return WidgetPalette.danger
        default: return Color(red: 0.24, green: 0.86, blue: 0.58)
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                Circle()
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1.2)
                Image(systemName: context.state.status == "done" ? "checkmark" : (context.state.status == "failed" ? "xmark" : "sparkles"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(context.attributes.goal)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .fixedSize()
                }

                Text(context.state.step)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.14))
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent, Color.white.opacity(0.92)],
                                    startPoint: .leading,
                                    endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 5.5)
            }
        }
        .padding(14)
    }
}
