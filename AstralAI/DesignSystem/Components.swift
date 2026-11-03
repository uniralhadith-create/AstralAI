import SwiftUI

// MARK: - Section header (System-Adaptive iOS 27 Liquid Glass)

public struct SectionHeader: View {
    let icon: String
    let titleKey: String
    let table: String

    public init(icon: String, _ titleKey: String, table: String = "Shared") {
        self.icon = icon
        self.titleKey = titleKey
        self.table = table
    }

    private var mappedAstralIcon: String? {
        switch icon {
        case "checklist": return AstralIcons.todo
        case "folder": return AstralIcons.folder
        case "sparkles": return AstralIcons.sparkles
        case "key.fill", "key": return AstralIcons.key
        case "cpu": return AstralIcons.cpu
        case "globe": return AstralIcons.browser
        case "checkmark.circle": return AstralIcons.checkCircle
        case "arrow.down.circle": return AstralIcons.download
        case "server.rack": return AstralIcons.hardDrive
        case "antenna.radiowaves.left.and.right": return AstralIcons.wifi
        case "slider.horizontal.3": return AstralIcons.settings
        case "cube.transparent": return AstralIcons.package
        default: return nil
        }
    }

    public var body: some View {
        HStack(spacing: AstralTheme.Spacings.s) {
            Group {
                if let lucide = mappedAstralIcon {
                    AIcon(
                        lucide,
                        size: 13,
                        strokeWidth: 2.2,
                        color: AstralTheme.textPrimary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AstralTheme.textPrimary)
                }
            }
            .frame(width: 26, height: 26)
            .liquidGlass(
                in: Circle(),
                tint: AstralTheme.actionFill.opacity(0.08),
                interactive: true)

            Text(L(titleKey, table))
                .font(AstralTheme.headline(15))
                .foregroundStyle(AstralTheme.textPrimary)
            Spacer()
        }
    }
}

// MARK: - Gradient wordmark

public struct AstralWordmark: View {
    public var fontSize: CGFloat = 30

    public init(fontSize: CGFloat = 30) {
        self.fontSize = fontSize
    }

    public var body: some View {
        HStack(spacing: AstralTheme.Spacings.xs) {
            Image("AstralMark")
                .resizable()
                .interpolation(.high)
                .frame(width: fontSize * 0.9, height: fontSize * 0.9)
            Text("Astral AI")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AstralTheme.textPrimary, AstralTheme.auroraCyan],
                        startPoint: .leading,
                        endPoint: .trailing))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Error banner

public struct ErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)?

    public init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: AstralTheme.Spacings.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AstralTheme.danger)
                .frame(width: 28, height: 28)
                .liquidGlass(in: Circle(), tint: AstralTheme.danger.opacity(0.14))

            Text(message)
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textPrimary)
                .lineLimit(3)
            Spacer()
            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        AIcon(AstralIcons.refresh, size: 11, strokeWidth: 2.4, color: AstralTheme.textPrimary)
                        Text(L("common.retry", "Shared"))
                            .font(AstralTheme.headline(12))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .liquidCapsule(interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AstralTheme.Spacings.m)
        .liquidGlass(in: RoundedRectangle(cornerRadius: AstralTheme.Radius.medium, style: .continuous))
    }
}

// MARK: - Agent activity orb

public struct ActivityOrb: View {
    public var color: Color = AstralTheme.orbGreen
    public var size: CGFloat = 22
    @State private var spinning = false

    public init(color: Color = AstralTheme.orbGreen, size: CGFloat = 22) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(AstralTheme.textPrimary.opacity(0.42), lineWidth: 1.2)
            Circle()
                .fill(color.opacity(0.24))
                .frame(width: size * 0.56)
            Circle()
                .fill(color)
                .frame(width: size * 0.22)
                .offset(x: size * 0.42)
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
    }
}

// MARK: - Progress bar (System-Adaptive iOS 27 Liquid Glass)

public struct GlassProgressView: View {
    public var progress: Double
    public var height: CGFloat = 6

    public init(progress: Double, height: CGFloat = 6) {
        self.progress = progress
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            let fillWidth = max(height, geo.size.width * CGFloat(clamped))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AstralTheme.separator.opacity(0.65))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AstralTheme.actionFill.opacity(0.75),
                                AstralTheme.actionFill,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing))
                    .frame(width: fillWidth, height: height)
                    .shimmer(active: progress < 1, cornerRadius: height / 2)
                    .clipShape(Capsule(style: .continuous))
            }
            .clipShape(Capsule(style: .continuous))
        }
        .frame(height: height)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: progress)
    }
}

// MARK: - Empty state

public struct EmptyStateView: View {
    let icon: String
    let titleKey: String
    let messageKey: String
    let table: String

    public init(icon: String, titleKey: String, messageKey: String, table: String = "Shared") {
        self.icon = icon
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.table = table
    }

    private var mappedAstralIcon: String? {
        switch icon {
        case "folder.badge.plus", "folder": return AstralIcons.folderPlus
        case "magnifyingglass": return AstralIcons.search
        default: return nil
        }
    }

    public var body: some View {
        VStack(spacing: AstralTheme.Spacings.m) {
            Group {
                if let lucide = mappedAstralIcon {
                    AIcon(lucide, size: 32, strokeWidth: 1.8, color: AstralTheme.accent)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(AstralTheme.accent)
                }
            }
            .frame(width: 84, height: 84)
            .liquidGlass(in: Circle(), interactive: true)

            Text(L(titleKey, table))
                .font(AstralTheme.headline(18))
                .foregroundStyle(AstralTheme.textPrimary)
            Text(L(messageKey, table))
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AstralTheme.Spacings.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Animated typing caret

public struct TypingCaret: View {
    @State private var visible = true

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(AstralTheme.accent)
            .frame(width: 3, height: 16)
            .opacity(visible ? 1 : 0.15)
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}
