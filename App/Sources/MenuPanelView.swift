import SwiftUI
import SystemMonitor
import OpenMenuCore

/// The menu bar drop-down: one warm glass card — tick-mark instrument dials for
/// CPU/MEM/DISK, icon toggle rows, a brightness slider, and a footer.
///
/// Layout rule: every label starts at the same leading inset and every control
/// ends at the same trailing inset, so the rows form clean left/right columns.
struct MenuPanelView: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject var settings: AppSettings
    @Environment(\.openSettings) private var openSettings
    /// Open the system-monitor detail popup on the given tab.
    var openMonitor: (MonitorTab) -> Void
    var dismiss: () -> Void

    private enum Metric {
        static let width: CGFloat = 272
        static let cardRadius: CGFloat = 16
        static let hPad: CGFloat = 16
    }

    var body: some View {
        VStack(spacing: 0) {
            dials
            divider
            toggles
            divider
            brightness
            divider
            footer
        }
        .background(GlassCard(cornerRadius: Metric.cardRadius))
        .padding(11)
        .frame(width: Metric.width)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Dials

    private var dials: some View {
        HStack(spacing: 0) {
            TickDial(value: stats.cpu, label: "CPU") { openMonitor(.cpu) }
            TickDial(value: stats.memory, label: "MEM") { openMonitor(.memory) }
            TickDial(value: stats.disk, label: "DISK") { openMonitor(.disk) }
        }
        .padding(.horizontal, Metric.hPad)
        .padding(.top, 15)
        .padding(.bottom, 11)
    }

    // MARK: Toggles

    private var toggles: some View {
        VStack(spacing: 11) {
            toggleRow("Window Manager", icon: "rectangle.split.2x2", isOn: $settings.windowManager)
            toggleRow("Clipboard History", icon: "doc.on.clipboard", isOn: $settings.clipboard)
            toggleRow("Keyboard Cleaning", icon: "keyboard", isOn: $settings.keyboardCleaning)
            toggleRow("Prevent Sleep", icon: "cup.and.saucer.fill", isOn: $settings.preventSleep)
        }
        .padding(.horizontal, Metric.hPad)
        .padding(.vertical, 14)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LiquidGlass.accent)
                .frame(width: 18, alignment: .center)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(LiquidGlass.accent)
        }
    }

    // MARK: Brightness

    private var brightness: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("EXTERNAL BRIGHTNESS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 9) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                Slider(value: $settings.externalBrightness, in: 0...1)
                    .controlSize(.small)
                    .tint(LiquidGlass.accent)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, Metric.hPad)
        .padding(.vertical, 13)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: openPreferences) {
                Text("Preferences")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, Metric.hPad)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }

    private func openPreferences() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        // This view is hosted in a bare NSPanel, outside any SwiftUI scene, where
        // the environment action can silently no-op. If no settings window showed
        // up, fall back to the legacy selector.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let opened = NSApp.windows.contains {
                $0.isVisible && $0.identifier?.rawValue.contains("Settings") == true
            }
            if !opened {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}

// MARK: - Tick dial

/// OpenMenu's signature gauge: a 240° arc of instrument ticks that light copper
/// as load rises — the last stretch is a redline — with the live value in
/// monospaced digits at the centre and the label in the bottom gap.
private struct TickDial: View {
    let value: Double
    let label: String
    var action: () -> Void
    @State private var hovering = false

    private static let tickCount = 25
    private static let sweep = 240.0
    /// Ticks in the top decile light red — the dial's fixed redline zone.
    private static let redline = 0.9

    var body: some View {
        ZStack {
            ForEach(0..<Self.tickCount, id: \.self) { index in
                let fraction = Double(index) / Double(Self.tickCount - 1)
                Capsule()
                    .fill(tickColor(fraction))
                    .frame(width: 2, height: 6)
                    .offset(y: -23)
                    .rotationEffect(.degrees(-120 + fraction * Self.sweep))
            }

            Text("\(percent)%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(hovering ? LiquidGlass.accentBright : .white)

            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 58, height: 58)
        .scaleEffect(hovering ? 1.05 : 1)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onTapGesture { action() }
        .animation(.easeInOut(duration: 0.4), value: value)
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .frame(maxWidth: .infinity)
    }

    private var percent: Int { Int((min(max(value, 0), 1) * 100).rounded()) }

    private func tickColor(_ fraction: Double) -> Color {
        let lit = fraction <= max(0.02, min(value, 1))
        guard lit else { return .white.opacity(0.14) }
        return fraction >= Self.redline ? LiquidGlass.critical : LiquidGlass.accent
    }
}
