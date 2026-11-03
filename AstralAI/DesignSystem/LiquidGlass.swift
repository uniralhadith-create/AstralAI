import SwiftUI

// MARK: - Liquid Glass V5 (iOS 27 Refractive Specular Design Language)

/// V5 — The iOS 27 Liquid Glass design language (monochrome & prismatic).
///
/// On iOS 26+ these helpers combine the system `glassEffect` material with
/// V5's multi-layered refractive rim, inner caustic highlight, and ambient
/// depth shadow so floating surfaces bend light with crystal clarity.
/// On iOS 17–25 they deliver the exact same optical recipe using ultra-thin
/// material, a subtle surface wash, a dual-angle specular stroke, and a
/// dual-radius elevation shadow.
extension View {
    /// True iOS 27 Liquid Glass V5 with multi-layered specular rim and inner
    /// caustic reflection.
    ///
    /// - Parameters:
    ///   - shape: the shape of the glass surface.
    ///   - tint: an optional tint blended into the glass (monochrome ink by
    ///     default — pass `AstralTheme.actionFill.opacity(x)` for subtlety).
    ///   - interactive: gives the surface touch-responsive "living" glass
    ///     behavior and enhanced specular rim.
    @ViewBuilder
    func liquidGlass(
        in shape: some Shape,
        tint: Color = .clear,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self
                    .glassEffect(Glass.regular.tint(tint).interactive(), in: shape)
                    .overlay(
                        shape.stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.42), location: 0.0),
                                    .init(color: Color.white.opacity(0.14), location: 0.38),
                                    .init(color: Color.white.opacity(0.04), location: 0.72),
                                    .init(color: Color.white.opacity(0.18), location: 1.0),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing),
                            lineWidth: 0.9)
                        .allowsHitTesting(false))
            } else {
                self
                    .glassEffect(Glass.regular.tint(tint), in: shape)
                    .overlay(
                        shape.stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.34), location: 0.0),
                                    .init(color: Color.white.opacity(0.10), location: 0.45),
                                    .init(color: Color.white.opacity(0.03), location: 0.75),
                                    .init(color: Color.white.opacity(0.14), location: 1.0),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing),
                            lineWidth: 0.75)
                        .allowsHitTesting(false))
            }
        } else {
            self
                .background(
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(AstralTheme.surface.opacity(0.38))
                        shape.fill(tint)
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(interactive ? 0.14 : 0.09),
                                    Color.white.opacity(0.02),
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
                                .init(color: Color.white.opacity(interactive ? 0.48 : 0.38), location: 0.0),
                                .init(color: Color.white.opacity(0.14), location: 0.40),
                                .init(color: Color.white.opacity(0.04), location: 0.72),
                                .init(color: Color.white.opacity(interactive ? 0.22 : 0.15), location: 1.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: interactive ? 1.0 : 0.85)
                    .allowsHitTesting(false)
                )
                .shadow(color: Color.black.opacity(0.12), radius: interactive ? 16 : 12, y: interactive ? 6 : 4)
        }
    }

    /// Capsule variant of ``liquidGlass(in:tint:interactive:)`` — the V5
    /// building block for pills, chips, and status strips.
    func liquidCapsule(tint: Color = .clear, interactive: Bool = false) -> some View {
        liquidGlass(in: Capsule(), tint: tint, interactive: interactive)
    }

    /// Elevated iOS 27 Liquid Glass V5 card with deeper refraction and subtle
    /// inner top-edge light bloom.
    func liquidGlassCard(
        cornerRadius: CGFloat = 22,
        tint: Color = .clear,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .liquidGlass(in: shape, tint: tint, interactive: interactive)
            .clipShape(shape)
    }
}

// MARK: - Prominent button style

/// The V5 monochrome primary action: an ink (light mode) / paper (dark mode)
/// capsule with specular top edge and responsive spring physics.
public struct GlassProminentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AstralTheme.headline())
            .foregroundStyle(AstralTheme.actionForeground)
            .padding(.horizontal, AstralTheme.Spacings.l)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    Capsule().fill(AstralTheme.actionFill)
                    Capsule().fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom))
                }
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.8))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.16), radius: configuration.isPressed ? 4 : 10, y: 4)
            .animation(.spring(response: 0.26, dampingFraction: 0.76), value: configuration.isPressed)
    }
}
