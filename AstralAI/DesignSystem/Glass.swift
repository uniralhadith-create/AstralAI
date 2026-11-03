import SwiftUI

// MARK: - Surface card modifier (V5 iOS 27 Liquid Glass)

/// The V5 surface system: refined glass-infused cards with specular hairline
/// borders for panels and raised cards, and **true iOS 27 Liquid Glass** for
/// floating elements.
public struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var depth: GlassDepth
    var tint: Color

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch depth {
        case .raised:
            content
                .background(
                    ZStack {
                        shape.fill(AstralTheme.surface)
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.06),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    }
                )
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                AstralTheme.separator,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 0.9))
                .clipShape(shape)
                .shadow(
                    color: Color.black.opacity(0.05),
                    radius: depth.shadowRadius + 2,
                    y: depth.shadowY)
        case .panel:
            content
                .background(
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(AstralTheme.surface.opacity(0.82))
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    }
                )
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.28), location: 0.0),
                                .init(color: AstralTheme.separator.opacity(0.85), location: 0.55),
                                .init(color: Color.white.opacity(0.12), location: 1.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 1.0))
                .clipShape(shape)
                .shadow(
                    color: Color.black.opacity(0.08),
                    radius: depth.shadowRadius + 2,
                    y: depth.shadowY)
        case .floating:
            floatingSurface(content, shape: shape)
        }
    }

    /// Floating elements get Liquid Glass on iOS 26+, and keep the classic
    /// translucent material stack on earlier systems.
    @ViewBuilder
    private func floatingSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        if #available(iOS 26.0, *) {
            content
                .liquidGlass(in: shape, tint: tint.opacity(depth.materialOpacity))
                .clipShape(shape)
        } else {
            content
                .background(
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Rectangle().fill(AstralTheme.surface.opacity(0.55))
                        Rectangle().fill(tint.opacity(depth.materialOpacity))
                    }
                    .clipShape(shape)
                )
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                AstralTheme.separator.opacity(0.6),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 1))
                .clipShape(shape)
                .shadow(color: Color.black.opacity(0.14), radius: depth.shadowRadius, y: depth.shadowY)
        }
    }
}

public extension View {
    /// Wraps the view in an Astral V5 surface card.
    func glassCard(
        cornerRadius: CGFloat = AstralTheme.Radius.large,
        depth: GlassDepth = .panel,
        tint: Color = .white
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, depth: depth, tint: tint))
    }

    /// Subtle liquid-glass capsule for inline elements (chips, pills).
    func glassPill(tint: Color = .white) -> some View {
        self.liquidCapsule(tint: tint.opacity(0.10))
    }
}

// MARK: - Button styles

/// Quiet secondary button on a raised Liquid Glass surface.
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
            .background(
                ZStack {
                    shape.fill(AstralTheme.surfaceSecondary)
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                }
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), AstralTheme.separator],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

/// Primary monochrome action — the V5 ink/paper capsule with specular rim.
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
            .background(
                ZStack {
                    shape.fill(AstralTheme.actionFill)
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom))
                }
            )
            .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.8))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(color: Color.black.opacity(0.18), radius: configuration.isPressed ? 3 : 9, y: 3)
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

// MARK: - Text field style

public struct GlassTextFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(configuration: TextField<_Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: AstralTheme.Radius.medium, style: .continuous)
        configuration
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.vertical, AstralTheme.Spacings.s + 2)
            .background(
                ZStack {
                    shape.fill(AstralTheme.surfaceSecondary)
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                }
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), AstralTheme.separator],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 1))
            .foregroundStyle(AstralTheme.textPrimary)
    }
}

// MARK: - Shimmer V5 (Smooth Feathered Capsule Sheen — Zero Sharp/Pixelated Edges)

/// V5 Liquid Glass Shimmer: replaces the old rectangular `.clipped()` gradient
/// (which produced harsh vertical cutoffs and pixelated edges on task rows and
/// progress bars) with a soft, multi-stop cosine-feathered capsule light wave
/// masked smoothly to a continuous rounded shape.
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
                                        .init(color: Color.white.opacity(0.0), location: 0.0),
                                        .init(color: Color.white.opacity(0.03), location: 0.18),
                                        .init(color: Color.white.opacity(0.11), location: 0.42),
                                        .init(color: Color.white.opacity(0.16), location: 0.50),
                                        .init(color: Color.white.opacity(0.11), location: 0.58),
                                        .init(color: Color.white.opacity(0.03), location: 0.82),
                                        .init(color: Color.white.opacity(0.0), location: 1.0),
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
