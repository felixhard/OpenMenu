import SwiftUI
import SystemMonitor

/// The four sections of the system-monitor detail popup.
enum MonitorTab: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"

    var id: String { rawValue }
}

/// Reveal state for the menu drop-down: drives the fade + de-blur animation.
final class RevealState: ObservableObject {
    @Published var revealed = false
}

/// State for the system-monitor detail window: which tab is shown plus the reveal
/// animation flag. Owned by `StatusItemController`.
final class MonitorState: ObservableObject {
    @Published var tab: MonitorTab = .cpu
    @Published var revealed = false
}

/// Fade + de-blur reveal shared by the menu and the detail window. Opacity and blur
/// are render-only effects (they don't change layout size), so they're safe to apply
/// inside a sized hosting view.
private struct Reveal: ViewModifier {
    let revealed: Bool
    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .blur(radius: revealed ? 0 : 7)
            .scaleEffect(revealed ? 1 : 0.97, anchor: .top)
    }
}

extension View {
    func reveal(_ on: Bool) -> some View { modifier(Reveal(revealed: on)) }
}

/// Root content of the menu-bar drop-down panel.
struct MenuRootView: View {
    @ObservedObject var reveal: RevealState
    @ObservedObject var stats: SystemStats
    @ObservedObject var settings: AppSettings
    var openMonitor: (MonitorTab) -> Void
    var dismiss: () -> Void

    var body: some View {
        MenuPanelView(stats: stats, settings: settings, openMonitor: openMonitor, dismiss: dismiss)
            .reveal(reveal.revealed)
    }
}

/// Root content of the standalone, centered system-monitor detail window.
struct MonitorRootView: View {
    @ObservedObject var state: MonitorState
    @ObservedObject var stats: SystemStats
    @ObservedObject var processes: ProcessSampler
    @ObservedObject var cleaner: DiskCleaner

    var body: some View {
        SystemMonitorView(tab: $state.tab, stats: stats, processes: processes, cleaner: cleaner)
            .reveal(state.revealed)
    }
}
