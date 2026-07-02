import SwiftUI

/// Shared card styling and brand palette so every surface across OpenMenu has a
/// consistent edge and one signature accent.
///
/// Identity: a warm "instrument panel" — copper accent on warm charcoal glass —
/// deliberately distinct from the cool-blue look common to menu bar utilities.
public enum LiquidGlass {

    /// Uniform edge colour for glass cards. Warm grey, visible on every side.
    public static let borderColor = Color(red: 0.48, green: 0.45, blue: 0.40).opacity(0.7)

    /// Dark warm tint laid over the material so cards read as smoked glass.
    /// Lower opacity = lighter card.
    public static let cardFill = Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.24)

    /// Signature copper accent — controls, lit gauge ticks, selection.
    public static let accent = Color(red: 0.855, green: 0.561, blue: 0.298)

    /// Brighter copper for strokes, highlights and hover states.
    public static let accentBright = Color(red: 0.949, green: 0.694, blue: 0.451)

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
