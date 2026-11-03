import SwiftUI

// MARK: - Design token compatibility

/// Compatibility bridge for the frozen design system.
///
/// `DesignSystem/Theme.swift` declares the spacing scale as the nested type
/// `AstralTheme.Spacing`, while the rest of the codebase — including the
/// equally frozen `Glass.swift` and `Components.swift` — references it as
/// `AstralTheme.Spacings` (160 call sites across 17 files). Theme.swift is
/// frozen and must not be modified, so the plural spelling is provided here
/// as a type alias. Both spellings resolve to the same type and the exact
/// same constants; nothing about the visual design changes.
extension AstralTheme {
    /// Alias of the frozen `AstralTheme.Spacing` scale.
    public typealias Spacings = Spacing
}
