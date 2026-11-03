import WidgetKit
import SwiftUI
import ActivityKit

/// The agent Live Activity V3 — strict monochrome. Every Dynamic Island
/// presentation uses tightly bounded, fixed-size elements so nothing can
/// overflow the island when it's pressed, and the Lock Screen banner reads
/// as a near-black glass card with white typography.
/// Renders `AgentActivityAttributes` (compiled into this target from
/// WidgetsShared) so the app and the extension share one content type.
struct AgentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.055, green: 0.055, blue: 0.062),
                            Color(red: 0.13, green: 0.13, blue: 0.14),
                        ],
                        startPoint: .top,
                        endPoint: .bottom)
                }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.goal)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.state.step)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(WidgetPalette.clamped(context.state.progress) * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .fixedSize()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: WidgetPalette.clamped(context.state.progress))
                        .tint(.white)
                        .frame(height: 6)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                ProgressView(value: WidgetPalette.clamped(context.state.progress))
                    .tint(.white)
                    .frame(width: 34, height: 14)
            } minimal: {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .keylineTint(.white)
        }
    }
}

// MARK: - Lock Screen view

/// Monochrome near-black card: goal, current step, white progress and the
/// terminal-state icon. Every line is capped at one so long Arabic or
/// English goals can never push the layout apart.
private struct LockScreenActivityView: View {
    let context: ActivityViewContext<AgentActivityAttributes>

    private var progress: Double {
        WidgetPalette.clamped(context.state.progress)
    }

    var body: some View {
        HStack(spacing: 12) {
            iconCircle

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.goal)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(context.state.step)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.white)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize()
                    statusIcon
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var iconCircle: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }

    /// Terminal states replace the mono percent with a clear verdict icon.
    @ViewBuilder
    private var statusIcon: some View {
        switch context.state.status {
        case "done":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetPalette.success)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetPalette.danger)
        default:
            EmptyView()
        }
    }
}
