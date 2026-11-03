import SwiftUI

// MARK: - Plan tracker (V5 System-Adaptive iOS 27 Liquid Glass)

/// Collapsible execution-plan card pinned above the conversation. Shows the
/// overall progress bar plus one status row per step with smooth feathered
/// capsule shimmer and crisp vector icons.
struct PlanTrackerView: View {
    let plan: ExecutionPlan
    let currentStepIndex: Int
    let progress: Double

    @State private var collapsed = false

    private var doneCount: Int {
        plan.steps.filter { $0.status == .done }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    collapsed.toggle()
                }
            } label: {
                VStack(spacing: 9) {
                    HStack(spacing: AstralTheme.Spacings.s) {
                        Text("\(doneCount)/\(plan.steps.count)")
                            .font(AstralTheme.mono(11).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AstralTheme.textPrimary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .liquidCapsule(
                                tint: AstralTheme.actionFill.opacity(0.14),
                                interactive: true)

                        SectionHeader(icon: "checklist", "chat.plan", table: "Chat")

                        AIcon(
                            AstralIcons.chevronDown,
                            size: 13,
                            strokeWidth: 2.3,
                            color: AstralTheme.textSecondary)
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                    }

                    if !collapsed {
                        GlassProgressView(progress: progress, height: 6)
                            .padding(.top, 2)
                    }
                }
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, isActive: index == currentStepIndex)
                    }
                }
                .transition(
                    .opacity.combined(
                        with: .move(edge: .top).combined(with: .scale(scale: 0.98, anchor: .top))))
            }
        }
        .padding(AstralTheme.Spacings.m)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            interactive: true)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Rows

    @ViewBuilder
    private func stepRow(_ step: PlanStep, isActive: Bool) -> some View {
        let inProgress = step.status == .inProgress
        let dimmed = step.status == .done || step.status == .failed || step.status == .skipped
        let activeRow = inProgress || (isActive && step.status == .pending)

        HStack(alignment: .top, spacing: 10) {
            statusIcon(step.status)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(AstralTheme.headline(13.5))
                    .foregroundStyle(inProgress ? AstralTheme.textPrimary : AstralTheme.textSecondary)
                    .strikethrough(dimmed)
                    .lineLimit(2)

                if inProgress, !step.detail.isEmpty {
                    Text(step.detail)
                        .font(AstralTheme.body(12))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if activeRow {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill( Color.clear )
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .shimmer(active: activeRow, cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: step.status)
    }

    @ViewBuilder
    private func statusIcon(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .strokeBorder(AstralTheme.moonDust.opacity(0.55), lineWidth: 1.5)
                .frame(width: 13, height: 13)
        case .inProgress:
            ActivityOrb(color: AstralTheme.orbGreen, size: 14)
        case .done:
            ZStack {
                Circle()
                    .fill(AstralTheme.success)
                    .frame(width: 14, height: 14)
                AIcon(AstralIcons.check, size: 8.5, strokeWidth: 3.0, color: .white)
            }
        case .failed:
            ZStack {
                Circle()
                    .fill(AstralTheme.danger)
                    .frame(width: 14, height: 14)
                AIcon(AstralIcons.close, size: 8.5, strokeWidth: 3.0, color: .white)
            }
        case .skipped:
            Circle()
                .strokeBorder(AstralTheme.moonDust.opacity(0.4), lineWidth: 1.4)
                .frame(width: 13, height: 13)
        }
    }
}
