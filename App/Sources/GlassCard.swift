import SwiftUI
import OpenMenuCore

/// Shared dark "glass" card background used by every panel surface (menu dropdown
/// and the system-monitor detail popup) so all cards share one edge + fill.
struct GlassCard: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LiquidGlass.cardFill)
            )
            .liquidGlassBorder(cornerRadius: cornerRadius, lineWidth: 1.5)
    }
}
