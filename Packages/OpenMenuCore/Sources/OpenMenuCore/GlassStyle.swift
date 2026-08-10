import SwiftUI

/// Shared card styling and brand palette so every surface across OpenMenu has a
/// consistent edge and one signature accent.
///
/// Identity: an "instrument panel" - system-blue accent on dark graphite glass,
/// with the signature tick-dial gauges carrying the character.
public enum LiquidGlass {

    /// Uniform edge colour for glass cards. Neutral grey, visible on every side.
    public static let borderColor = Color(white: 0.44).opacity(0.7)

    /// Dark tint laid over the material so cards read as dark glass.
    /// Lower opacity = lighter card.
    public static let cardFill = Color.black.opacity(0.18)

    /// Accent for controls, lit gauge ticks, selection: the standard macOS blue.
    public static let accent = Color(nsColor: .systemBlue)

    /// Brighter blue for strokes, highlights and hover states.
    public static let accentBright = Color(red: 0.35, green: 0.66, blue: 1.0)

    /// Redline: critical load, destructive actions.
    public static let critical = Color(red: 0.886, green: 0.373, blue: 0.333)

    /// Healthy load: the calm end of the gauge scale.
    public static let good = Color(nsColor: .systemGreen)

    /// Elevated load: worth a glance, not yet a problem.
    public static let warning = Color(nsColor: .systemYellow)

    /// Maps a 0...1 load to its status colour: green to 69%, yellow to 89%, red above.
    public static func status(for value: Double) -> Color {
        if value >= 0.9 { return critical }
        if value >= 0.7 { return warning }
        return good
    }
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
