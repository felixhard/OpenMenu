import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Orchestrates clipboard history: owns the store, the pasteboard monitor, the
/// global hotkey (⌘⇧V), and the history panel. Driven on/off by the menu toggle.
public final class ClipboardController {
    public static let shared = ClipboardController()
    public let store = ClipboardStore()

    private let monitor = ClipboardMonitor()
    private let hotKey = GlobalHotKey()
    private var panel: ClipboardPanel?
    private var hosting: NSHostingController<ClipboardView>?
    private var previousApp: NSRunningApplication?
    private var enabled = false

    private init() {}

    /// Enables/disables capture and the hotkey (bound to the "Clipboard History" toggle).
    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            monitor.onText = { [weak self] in self?.store.addText($0, app: $1) }
            monitor.onImage = { [weak self] in self?.store.addImage($0, app: $1) }
            monitor.onFiles = { [weak self] in self?.store.addFiles($0, app: $1) }
            monitor.start()
            hotKey.onFire = { [weak self] in self?.togglePanel() }
            hotKey.register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
        } else {
            monitor.stop()
            hotKey.unregister()
            hidePanel()
        }
    }

    private func togglePanel() {
        panel?.isVisible == true ? hidePanel() : showPanel()
    }

    private func showPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        let size = CGSize(width: 488, height: 540)
        panel.setContentSize(size)
        let screen = screenWithMouse()
        panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2,
                                     y: screen.frame.midY - size.height / 2))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hidePanel() { panel?.orderOut(nil) }

    private func makePanel() -> ClipboardPanel {
        let panel = ClipboardPanel()
        let view = ClipboardView(
            store: store,
            onPaste: { [weak self] in self?.paste($0) },
            onClose: { [weak self] in self?.hidePanel() }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        panel.contentViewController = hosting
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.hosting = hosting
        return panel
    }

    private func paste(_ item: ClipboardItem) {
        hidePanel()
        monitor.ignoreNextChange()
        store.promote(item)
        store.writeToPasteboard(item)
        _ = previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.postCommandV()
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
