import SwiftUI

// MARK: - Astra Computer bar (V5.0.0 — iOS 27 Liquid Glass + Custom Vector Computer)
//
// The Manus-style computer footer: a layered Liquid Glass V5 bar that sits
// ABOVE the message composer. The chat stays a clean conversation of
// steps and answers; everything the machine executes streams HERE —
// the current command, page or file, live, with one tap opening the
// full Astra Computer (terminal · browser · files).
//
// V5.0.0 upgrades:
// - Custom `AstralComputerIcon` vector workstation icon (Studio Display
//   bezel, live terminal `>_` prompt, and sculpted stand)
// - RTL-aware chevron direction
// - Smooth feathered capsule shimmer when the machine is actively running
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
                in: RoundedRectangle(cornerRadius: 19, style: .continuous),
                tint: isWorking
                    ? AstralTheme.orbGreen.opacity(0.08)
                    : AstralTheme.actionFill.opacity(0.07),
                interactive: true)
            .shimmer(active: isWorking, cornerRadius: 19)
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(PressableOrbStyle())
        .accessibilityLabel(Text(L("computer.barTitle", "Chat")))
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: activity.entries.count)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: cloud.status)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: mode.mode)
    }

    // MARK: Leading glyph

    /// The machine itself: the custom V5 Studio Display computer vector icon
    /// in a refractive glass tile, with a live activity orb when the agent is
    /// working.
    private var leadingGlyph: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                isWorking
                                    ? AstralTheme.orbGreen.opacity(0.24)
                                    : AstralTheme.accent.opacity(0.22),
                                isWorking
                                    ? AstralTheme.orbGreen.opacity(0.08)
                                    : AstralTheme.accent.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.32),
                                        Color.white.opacity(0.06),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                lineWidth: 0.8))

                AstralComputerIcon(
                    size: 19,
                    color: AstralTheme.textPrimary,
                    accentColor: AstralTheme.orbGreen,
                    isActive: isWorking)
            }
            .frame(width: 36, height: 36)

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
            HStack(spacing: 6) {
                Text(L("computer.barTitle", "Chat"))
                    .font(AstralTheme.headline(13.5))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .lineLimit(1)

                Text("V8.0")
                    .font(AstralTheme.mono(8.5).weight(.bold))
                    .foregroundStyle(AstralTheme.orbGreen)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AstralTheme.orbGreen.opacity(0.14)))
            }

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

    // MARK: Mode chip

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
                ? AstralTheme.accent.opacity(0.14)
                : AstralTheme.textPrimary.opacity(0.06))
    }
}
