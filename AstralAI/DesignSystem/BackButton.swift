import SwiftUI

// MARK: - Glass back button

/// The V4.5.6 back control — a circular Liquid Glass orb carrying the
/// Lucide `arrow-left` icon: a professionally drawn vector glyph (rounded
/// caps, 2.4 stroke) instead of a hand-built path. It looks identical in
/// every iOS version, mirrors correctly in RTL and matches the circular
/// glass header controls.
public struct GlassBackButton: View {
    var action: () -> Void
    var size: CGFloat = 34

    @Environment(\.layoutDirection) private var layoutDirection

    public init(size: CGFloat = 34, action: @escaping () -> Void) {
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            AIcon(
                AstralIcons.back,
                size: size * 0.46,
                strokeWidth: 2.4,
                color: AstralTheme.textPrimary)
                .frame(width: size, height: size)
                .liquidGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
                // Mirror the arrow in RTL so it always points "back".
                .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
        }
        .buttonStyle(PressableOrbStyle())
        .accessibilityLabel(Text(L("common.back", "Shared")))
    }
}

// MARK: - Glass close button

/// The V4.5.6 close control — a circular Liquid Glass orb with the Lucide
/// `x` glyph. The Manus-style dismissal control for full-screen views
/// (the Astra Computer modal uses this instead of a back arrow).
public struct GlassCloseButton: View {
    var action: () -> Void
    var size: CGFloat = 34

    public init(size: CGFloat = 34, action: @escaping () -> Void) {
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            AIcon(
                AstralIcons.close,
                size: size * 0.42,
                strokeWidth: 2.4,
                color: AstralTheme.textPrimary)
                .frame(width: size, height: size)
                .liquidGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PressableOrbStyle())
        .accessibilityLabel(Text(L("common.close", "Shared")))
    }
}

// MARK: - Press feedback

/// Scale-down press feedback that preserves the glass feel.
struct PressableOrbStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
