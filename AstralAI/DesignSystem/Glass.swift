import SwiftUI

// MARK: - Surface card modifier (Pure System-Adaptive iOS 27 Liquid Glass)

/// The V5 surface system: every card, panel, and floating surface routes
/// directly through ``liquidGlass(in:tint:interactive:)`` so on iOS 26/27
/// the entire app uses the real system `glassEffect` material — adapting
/// seamlessly to light/dark mode and content behind it instead of using
/// opaque fills or hand-drawn borders.
public struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var depth: GlassDepth
    var tint: Color

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let effectiveTint: Color = {
            if tint == .white || tint == .clear {
                return AstralTheme.actionFill.opacity(depth.materialOpacity)
            }
            return tint.opacity(max(depth.materialOpacity, 0.06))
        }()

        content
            .liquidGlass(
                in: shape,
                tint: effectiveTint,
                interactive: depth == .floating)
    }
}

public extension View {
    /// Wraps the view in a system-adaptive iOS 27 Liquid Glass card.
    func glassCard(
        cornerRadius: CGFloat = AstralTheme.Radius.large,
        depth: GlassDepth = .panel,
        tint: Color = .white
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, depth: depth, tint: tint))
    }

    /// Subtle system-adaptive liquid-glass capsule for inline elements (chips, pills).
    func glassPill(tint: Color = .white) -> some View {
        let effectiveTint = (tint == .white) ? Color.clear : tint.opacity(0.10)
        return self.liquidCapsule(tint: effectiveTint, interactive: true)
    }
}

// MARK: - Button styles

/// Secondary button rendered in true system-adaptive iOS 27 Liquid Glass.
public struct GlassButtonStyle: ButtonStyle {
    var tint: Color
    var cornerRadius: CGFloat

    public init(tint: Color = AstralTheme.nebulaViolet, cornerRadius: CGFloat = AstralTheme.Radius.medium) {
        self.tint = tint
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .font(AstralTheme.headline())
            .foregroundStyle(AstralTheme.textPrimary)
            .padding(.horizontal, AstralTheme.Spacings.l)
            .padding(.vertical, AstralTheme.Spacings.s)
            .liquidGlass(in: shape, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.smooth(duration: 0.2), value: configuration.isPressed)
    }
}

/// Primary monochrome action — the ink/paper capsule.
public struct AuroraButtonStyle: ButtonStyle {
    public var cornerRadius: CGFloat = AstralTheme.Radius.medium

    public init(cornerRadius: CGFloat = AstralTheme.Radius.medium) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .font(AstralTheme.headline())
            .foregroundStyle(AstralTheme.actionForeground)
            .padding(.horizontal, AstralTheme.Spacings.l)
            .padding(.vertical, AstralTheme.Spacings.s)
            .background(shape.fill(AstralTheme.actionFill))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(color: Color.black.opacity(0.16), radius: configuration.isPressed ? 3 : 8, y: 3)
            .animation(.smooth(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Text field style

/// System-adaptive iOS 27 Liquid Glass text field style.
public struct GlassTextFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(configuration: TextField<_Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: AstralTheme.Radius.medium, style: .continuous)
        configuration
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.vertical, AstralTheme.Spacings.s + 2)
            .liquidGlass(in: shape, interactive: true)
            .foregroundStyle(AstralTheme.textPrimary)
    }
}

// MARK: - Shimmer V5 (System-Adaptive Feathered Capsule Sheen)

/// System-adaptive Liquid Glass Shimmer: uses `Color.primary` with a soft
/// cosine-feathered capsule gradient and Gaussian blur so the moving sheen
/// adapts naturally to both Light and Dark mode with zero sharp or pixelated
/// edges.
public struct ShimmerModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    @State private var phase: CGFloat = -1.15

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = max(1, geo.size.width)
                    let height = max(1, geo.size.height)
                    let bandWidth = max(48, width * 0.65)
                    let radius = min(cornerRadius, height / 2)

                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.primary.opacity(0.0), location: 0.0),
                                        .init(color: Color.primary.opacity(0.03), location: 0.18),
                                        .init(color: Color.primary.opacity(0.09), location: 0.42),
                                        .init(color: Color.primary.opacity(0.14), location: 0.50),
                                        .init(color: Color.primary.opacity(0.09), location: 0.58),
                                        .init(color: Color.primary.opacity(0.03), location: 0.82),
                                        .init(color: Color.primary.opacity(0.0), location: 1.0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing)
                            )
                            .frame(width: bandWidth, height: height)
                            .blur(radius: 3.5)
                            .offset(x: width * phase)
                    }
                    .frame(width: width, height: height, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
                .allowsHitTesting(false)
            )
            .task {
                phase = -1.15
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
                    phase = 1.35
                }
            }
    }
}

public extension View {
    @ViewBuilder
    func shimmer(active: Bool = true, cornerRadius: CGFloat = 12) -> some View {
        if active {
            modifier(ShimmerModifier(cornerRadius: cornerRadius))
        } else {
            self
        }
    }
}
