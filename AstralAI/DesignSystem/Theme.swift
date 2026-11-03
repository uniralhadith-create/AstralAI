import SwiftUI
import UIKit

// MARK: - Color helpers

public extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// Builds a color that adapts to light / dark mode from one hex pair.
private func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1)
    })
}

// MARK: - Astral theme tokens

/// V3 — Liquid Glass monochrome.
///
/// The V3 design language: strict black ↔ white. Ink on paper in light
/// mode, paper on pure black in dark mode, one adaptive monochrome accent
/// shared by every legacy token name (so nothing anywhere in the app can
/// render purple). Semantic colors (success / warning / danger) keep their
/// hues — meaning must survive the palette. Liquid Glass surfaces come from
/// `LiquidGlass.swift`; this type remains the single source of color truth.
public enum AstralTheme {
    // Core palette (adaptive)
    public static let spaceBlack = adaptive(0xF4F4F6, 0x000000)   // app background (near-white gray / pure black)
    public static let spaceDeep = adaptive(0xFFFFFF, 0x101014)    // card surface
    public static let nebulaViolet = adaptive(0x0A0A0A, 0xF5F5F7) // accent — monochrome (ink / paper)
    public static let auroraCyan = adaptive(0x0A0A0A, 0xF5F5F7)   // accent (unified monochrome)
    public static let auroraMagenta = adaptive(0x0A0A0A, 0xF5F5F7)
    public static let starlight = adaptive(0x0A0A0A, 0xF5F5F7)    // primary text (ink / paper)
    public static let moonDust = adaptive(0x6E6E73, 0x9A9AA2)     // secondary text
    public static let success = adaptive(0x2F9E5F, 0x57C98A)
    public static let warning = adaptive(0xB8860B, 0xE0A82E)
    public static let danger = adaptive(0xD93025, 0xF0716A)

    // New semantic tokens
    /// App-level background.
    public static let background = spaceBlack
    /// Card / sheet surface.
    public static let surface = spaceDeep
    /// Slightly recessed surface (chips, input wells, banners).
    public static let surfaceSecondary = adaptive(0xE9E9EE, 0x1A1A1F)
    /// Hairline separators and borders.
    public static let separator = adaptive(0xE3E3E8, 0x26262C)
    /// The single brand accent — V3 monochrome ink / paper.
    public static let accent = nebulaViolet
    /// V3 primary action: ink-dark button in light mode, paper-white in
    /// dark mode — pure monochrome contrast.
    public static let actionFill = adaptive(0x0A0A0A, 0xF5F5F7)
    public static let actionForeground = adaptive(0xFFFFFF, 0x0A0A0A)
    /// User chat bubble fill — monochrome.
    public static let userBubbleFill = adaptive(0xE9E9EE, 0x1E1E24)
    /// The living work orb's green (V4.6.0) — the same green the terminal
    /// has always used for its busy orb and running steps. One color for
    /// every "the machine is working" signal in the app.
    public static let orbGreen = Color(red: 0.42, green: 0.85, blue: 0.55)

    // Text hierarchy
    public static let textPrimary = starlight
    public static let textSecondary = moonDust

    // Signature gradients — monochrome: the action ink/paper fading into
    // itself. Near-solid on purpose so the interface reads as calm and
    // professional rather than decorative.
    public static let aurora = LinearGradient(
        colors: [actionFill, actionFill.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    public static let auroraWide = LinearGradient(
        colors: [actionFill, actionFill.opacity(0.85)],
        startPoint: .leading,
        endPoint: .trailing)

    public static let nebula = LinearGradient(
        colors: [background, background],
        startPoint: .top,
        endPoint: .bottom)

    public static let userBubble = LinearGradient(
        colors: [userBubbleFill, userBubbleFill],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    // Spacing scale
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let s: CGFloat = 12
        public static let m: CGFloat = 16
        public static let l: CGFloat = 22
        public static let xl: CGFloat = 30
        public static let xxl: CGFloat = 44
    }

    // Corner radii
    public enum Radius {
        public static let small: CGFloat = 12
        public static let medium: CGFloat = 18
        public static let large: CGFloat = 26
        public static let pill: CGFloat = 999
    }

    // Typography helpers — clean SF Pro, Manus-grade restraint.
    public static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold)
    }
    public static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold)
    }
    public static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }
    public static func mono(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    /// Serif display face (New York) — the V3 signature for greetings and
    /// section titles. Elegant, editorial, unmistakably premium.
    public static func display(_ size: CGFloat = 30, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Glass elevation

public enum GlassDepth {
    case raised
    case panel
    case floating

    var materialOpacity: Double {
        switch self {
        case .raised: return 0.0
        case .panel: return 0.03
        case .floating: return 0.05
        }
    }
    var shadowRadius: CGFloat {
        switch self {
        case .raised: return 1
        case .panel: return 8
        case .floating: return 18
        }
    }
    var shadowY: CGFloat {
        switch self {
        case .raised: return 1
        case .panel: return 4
        case .floating: return 8
        }
    }
}
