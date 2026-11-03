import SwiftUI

// MARK: - Sub-agent bar (V5 Liquid Glass)

/// Horizontal monitor strip for the parallel sub-agents currently working
/// for the active session. Each pill pairs the Lucide `bot` glyph in a
/// state-tinted badge with the agent name and its current action, wrapped
/// in a smooth capsule shimmer while running.
struct SubAgentBar: View {
    let agents: [SubAgentStatus]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(agents) { agent in
                    pill(for: agent)
                }
            }
            .padding(.vertical, 2)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func pill(for agent: SubAgentStatus) -> some View {
        let isRunning = agent.state == .running
        return HStack(spacing: 9) {
            agentBadge(for: agent)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(agent.name)
                    .font(AstralTheme.headline(12))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .lineLimit(1)

                if !agent.currentAction.isEmpty {
                    Text(agent.currentAction)
                        .font(AstralTheme.body(10.5))
                        .foregroundStyle(AstralTheme.moonDust)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidCapsule(
            tint: isRunning
                ? AstralTheme.orbGreen.opacity(0.08)
                : AstralTheme.actionFill.opacity(0.04),
            interactive: true)
        .shimmer(active: isRunning, cornerRadius: 999)
        .clipShape(Capsule(style: .continuous))
    }

    private func agentBadge(for agent: SubAgentStatus) -> some View {
        let tint = orbColor(for: agent.state)
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint.opacity(0.28), lineWidth: 0.8))

            AIcon(
                AstralIcons.bot,
                size: 15,
                strokeWidth: 2.1,
                color: tint)

            stateBadge(for: agent.state)
                .offset(x: 3.5, y: 3.5)
        }
    }

    @ViewBuilder
    private func stateBadge(for state: SubAgentState) -> some View {
        let tint = orbColor(for: state)
        switch state {
        case .running:
            ZStack {
                Circle()
                    .fill(AstralTheme.background)
                    .frame(width: 13, height: 13)
                ActivityOrb(color: tint, size: 9)
            }
        case .finished:
            badgeDisc(color: AstralTheme.success) {
                AIcon(AstralIcons.check, size: 7, strokeWidth: 3.2, color: .white)
            }
        case .failed:
            badgeDisc(color: AstralTheme.danger) {
                AIcon(AstralIcons.close, size: 7, strokeWidth: 3.2, color: .white)
            }
        }
    }

    private func badgeDisc<Content: View>(
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(AstralTheme.background, lineWidth: 1.6))
            content()
        }
    }

    private func orbColor(for state: SubAgentState) -> Color {
        switch state {
        case .running: return AstralTheme.orbGreen
        case .finished: return AstralTheme.success
        case .failed: return AstralTheme.danger
        }
    }
}
