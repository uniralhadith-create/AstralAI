import SwiftUI

// MARK: - Liquid Glass V5 (Pure System-Adaptive iOS 26/27 Design Language)

/// V5 — The native iOS 26/27 Liquid Glass design language.
///
/// On iOS 26+ these helpers call the real system `glassEffect(Glass.regular...)`
/// material directly — with ZERO artificial overlays or hand-drawn borders on
/// top — so every header, composer, bar, card, and orb bends, refracts, and
/// adapts to light/dark mode and background content exactly like native iOS 27
/// system chrome.
///
/// On iOS 17–25 they fall back to a clean system `.ultraThinMaterial` recipe
/// that adapts automatically to the system's `colorScheme`.
extension View {
    /// True native system Liquid Glass on iOS 26+, adaptive `.ultraThinMaterial`
    /// fallback on iOS 17–25.
    ///
    /// - Parameters:
    ///   - shape: the shape of the glass surface.
    ///   - tint: an optional tint blended into the system glass.
    ///   - interactive: on iOS 26+, gives the surface the system's native
    ///     touch-responsive "living" glass refraction.
    @ViewBuilder
    func liquidGlass(
        in shape: some Shape,
        tint: Color = .clear,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        // Xcode 26+ ships the iOS 26 SDK where the native `glassEffect`
        // material and `Glass` type exist — use the real system glass.
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(Glass.regular.tint(tint).interactive(), in: shape)
            } else {
                self.glassEffect(Glass.regular.tint(tint), in: shape)
            }
        } else {
            liquidGlassFallback(in: shape, tint: tint)
        }
        #else
        // Xcode 16 / iOS 18 SDK: the `Glass` API does not exist yet, so the
        // adaptive fallback renders instead — identical to what iOS 17–25
        // devices see at runtime.
        liquidGlassFallback(in: shape, tint: tint)
        #endif
    }

    /// Adaptive pre-iOS-26 recipe: clean `.ultraThinMaterial` with a subtle
    /// dual-tone stroke and a soft elevation shadow.
    private func liquidGlassFallback(
        in shape: some Shape,
        tint: Color
    ) -> some View {
        self
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(AstralTheme.surface.opacity(0.32))
                    shape.fill(tint)
                }
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.18),
                            Color.primary.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 0.75)
                .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 12, y: 5)
    }

    /// Capsule variant of ``liquidGlass(in:tint:interactive:)`` — the native
    /// iOS 27 Liquid Glass building block for pills, chips, and status strips.
    func liquidCapsule(tint: Color = .clear, interactive: Bool = false) -> some View {
        liquidGlass(in: Capsule(), tint: tint, interactive: interactive)
    }

    /// Elevated native iOS 27 Liquid Glass card.
    func liquidGlassCard(
        cornerRadius: CGFloat = 22,
        tint: Color = .clear,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self.liquidGlass(in: shape, tint: tint, interactive: interactive)
    }
}

// MARK: - Prominent button style

/// The system-adaptive primary action capsule.
public struct GlassProminentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AstralTheme.headline())
            .foregroundStyle(AstralTheme.actionForeground)
            .padding(.horizontal, AstralTheme.Spacings.l)
            .padding(.vertical, 12)
            .background(Capsule().fill(AstralTheme.actionFill))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.2), value: configuration.isPressed)
    }
}
