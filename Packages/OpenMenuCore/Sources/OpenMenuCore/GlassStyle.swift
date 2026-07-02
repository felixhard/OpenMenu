import SwiftUI

/// Shared card styling and brand palette so every surface across OpenMenu has a
/// consistent edge and one signature accent.
///
/// Identity: an "instrument panel" — teal-mint accent on dark graphite glass —
/// deliberately distinct from the cool-blue look common to menu bar utilities.
public enum LiquidGlass {

    /// Uniform edge colour for glass cards. Neutral grey, visible on every side.
    public static let borderColor = Color(white: 0.44).opacity(0.7)

    /// Dark tint laid over the material so cards read as dark glass.
    /// Lower opacity = lighter card.
    public static let cardFill = Color.black.opacity(0.18)

    /// Signature teal-mint accent — controls, lit gauge ticks, selection.
    public static let accent = Color(red: 0.27, green: 0.82, blue: 0.68)

    /// Brighter mint for strokes, highlights and hover states.
    public static let accentBright = Color(red: 0.50, green: 0.89, blue: 0.79)

    /// Redline: critical load, destructive actions.
    public static let critical = Color(red: 0.886, green: 0.373, blue: 0.333)
}

public extension View {
    /// Overlays a uniform hairline edge on a rounded-rect card.
    func liquidGlassBorder(cornerRadius: CGFloat, lineWidth: CGFloat = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LiquidGlass.borderColor, lineWidth: lineWidth)
        )
    }
}
