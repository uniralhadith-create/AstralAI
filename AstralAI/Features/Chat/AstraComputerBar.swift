import SwiftUI

// MARK: - Astra Computer bar (V5.0.0 — Pure System-Adaptive iOS 27 Liquid Glass)
//
// The Manus-style computer footer: a native iOS 27 Liquid Glass bar that sits
// ABOVE the message composer. Everything — the outer bar, the leading
// computer icon badge, and the local/cloud mode capsule — uses pure
// system-adaptive `.liquidGlass(..., interactive: true)` and system-adaptive
// `AIcon(AstralIcons.computer)` so it adapts seamlessly to Light & Dark mode
// and iOS 27 system materials.
struct AstraComputerBar: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var activity = AgentActivityLog.shared
    @ObservedObject private var cloud = E2BComputer.shared
    @ObservedObject private var mode = ComputerModeController.shared

    @State private var pulse = false

    var body: some View {
        Button {
            env.showTerminal = true
        } label: {
            HStack(spacing: 11) {
                leadingGlyph
                statusStack
                Spacer(minLength: 6)
                modeChip
                AIcon(
                    AstralIcons.chevronForward,
                    size: 15,
                    strokeWidth: 2.2,
                    color: AstralTheme.textSecondary)
                    .scaleEffect(x: language.layoutDirection == .rightToLeft ? -1 : 1, y: 1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                tint: isWorking
                    ? AstralTheme.orbGreen.opacity(0.08)
                    : .clear,
                interactive: true)
            .shimmer(active: isWorking, cornerRadius: 20)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableOrbStyle())
        .accessibilityLabel(Text(L("computer.barTitle", "Chat")))
        .animation(.smooth(duration: 0.3), value: activity.entries.count)
        .animation(.smooth(duration: 0.3), value: cloud.status)
        .animation(.smooth(duration: 0.3), value: mode.mode)
    }

    // MARK: Leading glyph (System-Adaptive iOS 27 Liquid Glass Tile + Vector Icon)

    /// The machine itself: the vector computer icon inside a native iOS 27
    /// Liquid Glass tile that adapts automatically to the system appearance,
    /// with a live activity dot when working.
    private var leadingGlyph: some View {
        ZStack(alignment: .bottomTrailing) {
            AIcon(
                AstralIcons.computer,
                size: 17.5,
                strokeWidth: 2.0,
                color: isWorking ? AstralTheme.orbGreen : AstralTheme.textPrimary)
                .frame(width: 34, height: 34)
                .liquidGlass(
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                    tint: isWorking
                        ? AstralTheme.orbGreen.opacity(0.14)
                        : AstralTheme.actionFill.opacity(0.06),
                    interactive: true)

            if isWorking {
                Circle()
                    .fill(AstralTheme.orbGreen)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(AstralTheme.background, lineWidth: 2))
                    .offset(x: 2.5, y: 2.5)
                    .scaleEffect(pulse ? 1.15 : 0.88)
                    .animation(
                        .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                        value: pulse)
            }
        }
        .onAppear { pulse = true }
    }

    // MARK: Status text

    private var statusStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("computer.barTitle", "Chat"))
                .font(AstralTheme.headline(13.5))
                .foregroundStyle(AstralTheme.textPrimary)
                .lineLimit(1)

            Text(statusDetail)
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(
                    isWorking ? AstralTheme.textPrimary.opacity(0.85) : AstralTheme.textSecondary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }

    /// The live second line — what the machine is doing RIGHT NOW.
    private var statusDetail: String {
        if mode.prefersCloud {
            if cloud.shuttingDown {
                return L("computer.poweringOff", "Chat")
            }
            switch cloud.status {
            case .starting:
                return L("computer.bootingCloud", "Chat")
            case .failed(let detail):
                return String(detail.prefix(60))
            default:
                break
            }
        }

        if let latest = activity.entries.last {
            let label = latest.title.isEmpty ? latest.toolName : latest.title
            let flat = label.replacingOccurrences(of: "\n", with: " ")
            let prefix = latest.status == .running
                ? L("computer.runningPrefix", "Chat")
                : (latest.status == .failed ? L("computer.failedPrefix", "Chat") : nil)
            if let prefix {
                return "\(prefix) \(String(flat.prefix(70)))"
            }
            if Date().timeIntervalSince(latest.startedAt) < 120 {
                return "✓ \(String(flat.prefix(70)))"
            }
        }

        return mode.prefersCloud
            ? L("computer.idleCloud", "Chat")
            : L("computer.idleLocal", "Chat")
    }

    private var isWorking: Bool {
        if cloud.status == .starting { return true }
        return activity.entries.last?.status == .running
    }

    // MARK: Mode chip (System-Adaptive Liquid Capsule)

    private var modeChip: some View {
        HStack(spacing: 4) {
            AIcon(
                mode.prefersCloud ? AstralIcons.cloud : AstralIcons.cpu,
                size: 11,
                strokeWidth: 2.2,
                color: mode.prefersCloud ? AstralTheme.accent : AstralTheme.textSecondary)
            Text(mode.prefersCloud ? L("computer.modeCloud", "Chat") : L("computer.modeLocal", "Chat"))
                .font(AstralTheme.mono(9.5).weight(.semibold))
                .foregroundStyle(mode.prefersCloud ? AstralTheme.accent : AstralTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .liquidCapsule(
            tint: mode.prefersCloud
                ? AstralTheme.accent.opacity(0.12)
                : .clear,
            interactive: true)
    }
}
