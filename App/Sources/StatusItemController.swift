import AppKit
import SwiftUI
import QuartzCore
import SystemMonitor

/// Owns the menu bar status item, the drop-down menu panel, and the standalone
/// system-monitor detail window.
///
/// The menu is a borderless transparent `NSPanel` that auto-sizes to its SwiftUI
/// content and drops down from the status item. The detail popup is a *separate*,
/// fixed-size floating window centered on screen — deliberately not the same panel,
/// so its (scrolling, variable-height) content never drives a live window-resize
/// that would fight Auto Layout.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {

    private let statusItem: NSStatusItem

    // Menu drop-down.
    private let panel: NSPanel
    private let hosting: NSHostingController<MenuRootView>
    private let menuReveal: RevealState
    private var clickMonitor: Any?
    private var isHiding = false

    // System-monitor detail window.
    private let monitorPanel: NSPanel
    private let monitorHosting: NSHostingController<MonitorRootView>
    private let monitorState: MonitorState
    private let processes: ProcessSampler
    private let cleaner: DiskCleaner
    private var monitorClickMonitor: Any?
    private var isClosingMonitor = false

    private enum MonitorMetric {
        static let width: CGFloat = 300
        static let height: CGFloat = 648
    }

    init(stats: SystemStats, settings: AppSettings) {
        let menuReveal = RevealState()
        let monitorState = MonitorState()
        let processes = ProcessSampler()
        let cleaner = DiskCleaner()
        self.menuReveal = menuReveal
        self.monitorState = monitorState
        self.processes = processes
        self.cleaner = cleaner

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = MenuPanel()
        monitorPanel = MonitorPanel(width: MonitorMetric.width, height: MonitorMetric.height)
        hosting = NSHostingController(rootView: MenuRootView(
            reveal: menuReveal, stats: stats, settings: settings, openMonitor: { _ in }, dismiss: {}))
        monitorHosting = NSHostingController(rootView: MonitorRootView(
            state: monitorState, stats: stats, processes: processes, cleaner: cleaner))

        super.init()

        hosting.rootView = MenuRootView(
            reveal: menuReveal, stats: stats, settings: settings,
            openMonitor: { [weak self] tab in self?.openMonitor(tab) },
            dismiss: { [weak self] in self?.hide() }
        )
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.delegate = self
        transparentHost(hosting.view)

        monitorPanel.contentViewController = monitorHosting
        monitorPanel.delegate = self
        transparentHost(monitorHosting.view)

        if let button = statusItem.button {
            button.image = Self.statusGlyph()
            button.target = self
            button.action = #selector(togglePanel)
        }
    }

    /// OpenMenu's menu bar mark: a miniature of the panel's tick dial — a 240°
    /// arc of ticks with a bottom gap. Drawn as a template image so it adapts
    /// to menu bar appearance.
    private static func statusGlyph() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let center = CGPoint(x: side / 2, y: side / 2 - 0.5)
            let tickCount = 9
            let sweep = 240.0
            for i in 0..<tickCount {
                let frac = Double(i) / Double(tickCount - 1)
                let angle = (210.0 - frac * sweep) * .pi / 180
                let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
                let tick = NSBezierPath()
                tick.move(to: CGPoint(x: center.x + dx * 5.2, y: center.y + dy * 5.2))
                tick.line(to: CGPoint(x: center.x + dx * 7.6, y: center.y + dy * 7.6))
                tick.lineWidth = 1.7
                tick.lineCapStyle = .round
                NSColor.black.setStroke()
                tick.stroke()
            }
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 1.6, y: center.y - 1.6,
                                                  width: 3.2, height: 3.2))
            NSColor.black.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "OpenMenu"
        return image
    }

    /// Keep the hosting view transparent so only the SwiftUI cards are visible
    /// (no window/host backdrop showing through the padding margins).
    private func transparentHost(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    // MARK: - Menu drop-down

    @objc private func togglePanel() {
        if monitorPanel.isVisible { closeMonitor() }
        panel.isVisible ? hide() : show()
    }

    private func show() {
        isHiding = false
        menuReveal.revealed = false
        position()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey() // allow SwiftUI controls to receive the first click

        // Defer one hop so SwiftUI commits the hidden state before animating, then
        // fade in while the content de-blurs and settles.
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeOut(duration: 0.24)) { self?.menuReveal.revealed = true }
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true

        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }

        withAnimation(.easeIn(duration: 0.16)) { menuReveal.revealed = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            if !self.menuReveal.revealed { self.panel.orderOut(nil) }
            self.isHiding = false
        }
    }

    /// Anchors the menu just below the status item, clamped to the screen.
    private func position() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let size = hosting.view.fittingSize
        panel.setContentSize(size)

        let buttonOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonOnScreen.midX - size.width / 2
        let y = buttonOnScreen.minY - size.height - 4

        if let frame = buttonWindow.screen?.visibleFrame {
            x = min(max(x, frame.minX + 6), frame.maxX - size.width - 6)
        }
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    // MARK: - System-monitor detail window

    private func openMonitor(_ tab: MonitorTab) {
        hide() // dismiss the menu
        monitorState.tab = tab
        monitorState.revealed = false
        processes.start()
        centerMonitor()
        monitorPanel.alphaValue = 1
        monitorPanel.orderFrontRegardless()
        monitorPanel.makeKey()
        isClosingMonitor = false

        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeOut(duration: 0.26)) { self?.monitorState.revealed = true }
        }

        monitorClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeMonitor()
        }
    }

    private func closeMonitor() {
        guard monitorPanel.isVisible, !isClosingMonitor else { return }
        isClosingMonitor = true

        if let monitor = monitorClickMonitor {
            NSEvent.removeMonitor(monitor)
            monitorClickMonitor = nil
        }
        processes.stop()

        withAnimation(.easeIn(duration: 0.16)) { monitorState.revealed = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            if !self.monitorState.revealed { self.monitorPanel.orderOut(nil) }
            self.isClosingMonitor = false
        }
    }

    /// Centers the fixed-size detail window, biased slightly above screen center.
    private func centerMonitor() {
        let screen = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let w = MonitorMetric.width, h = MonitorMetric.height
        let x = screen.midX - w / 2
        let y = screen.midY - h / 2 + 60
        monitorPanel.setFrame(NSRect(x: x, y: max(screen.minY + 6, y), width: w, height: h), display: true)
    }

    // MARK: - NSWindowDelegate

    /// Close whichever surface lost focus — i.e. the user clicked elsewhere.
    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === monitorPanel {
            closeMonitor()
        } else {
            hide()
        }
    }
}

/// Borderless, transparent, non-activating panel for the menu bar drop-down.
private final class MenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
}

/// Borderless, transparent floating panel for the centered detail popup. Fixed size
/// (set once at init) so the SwiftUI content never drives a live window resize.
private final class MonitorPanel: NSPanel {
    init(width: CGFloat, height: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
}
