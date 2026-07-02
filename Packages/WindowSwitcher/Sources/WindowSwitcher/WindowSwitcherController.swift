import AppKit
import SwiftUI
import OpenMenuCore

/// Orchestrates the window switcher: owns the hotkey tap and the floating panel,
/// runs the press/cycle/release state machine, and activates the chosen window.
///
/// All mutation happens on the main run loop (the event tap's run-loop source is
/// attached to the main run loop), so it is safe to drive SwiftUI directly.
public final class WindowSwitcherController: ObservableObject {

    /// The modifier held with Tab to invoke the switcher.
    public enum HotKeyModifier: String, CaseIterable {
        case command, option

        var flag: CGEventFlags {
            switch self {
            case .command: return .maskCommand
            case .option:  return .maskAlternate
            }
        }
    }

    @Published public private(set) var windows: [WindowInfo] = []
    @Published public private(set) var selectedIndex: Int = 0
    @Published public private(set) var isActive: Bool = false

    /// Which modifier triggers the switcher (⌘ replaces the system switcher).
    public var hotKeyModifier: HotKeyModifier = .command
    /// Whether rows show the window title beneath the app name.
    @Published public var showsWindowTitles: Bool = true

    private let tap = HotKeyTap()
    private var panel: SwitcherPanel?
    private var hosting: NSHostingController<SwitcherView>?
    private var accessibilityTimer: Timer?

    // Carbon virtual key codes.
    private let tabKey: Int64 = 48
    private let escapeKey: Int64 = 53

    public init() {}

    /// Wires up the hotkey handler and tries to install the tap. Safe to call
    /// before Accessibility is granted — installation simply no-ops until then.
    public func start() {
        tap.onEvent = { [weak self] type, keyCode, flags in
            self?.handle(type: type, keyCode: keyCode, flags: flags) ?? false
        }
        if !installTapIfPossible() {
            // Not trusted yet: prompt once, then poll so the shortcut activates
            // as soon as the user grants Accessibility — no relaunch required.
            Permissions.ensureAccessibility(prompt: true)
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if self.installTapIfPossible() { timer.invalidate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            accessibilityTimer = timer
        }
    }

    /// Installs the tap if Accessibility is granted. Returns whether it's active.
    @discardableResult
    public func installTapIfPossible() -> Bool {
        guard Permissions.isAccessibilityTrusted else { return false }
        return tap.install()
    }

    /// Whether the global shortcut is currently live.
    public var isHotKeyActive: Bool { tap.isInstalled }

    // MARK: - Event handling

    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        let modifier = flags.contains(hotKeyModifier.flag)
        let shift = flags.contains(.maskShift)

        switch type {
        case .keyDown where keyCode == tabKey && modifier:
            if !isActive { begin() }
            advance(by: shift ? -1 : 1)
            return true // swallow Tab so the system switcher never appears

        case .keyDown where keyCode == escapeKey && isActive:
            cancel()
            return true

        case .flagsChanged where isActive && !modifier:
            commit()
            return false

        default:
            return false
        }
    }

    // MARK: - State machine

    private func begin() {
        windows = WindowEnumerator.currentWindows()
        selectedIndex = 0
        isActive = true
        showPanel()
    }

    private func advance(by delta: Int) {
        guard !windows.isEmpty else { return }
        let count = windows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    private func commit() {
        defer {
            hidePanel()
            isActive = false
        }
        guard windows.indices.contains(selectedIndex) else { return }
        WindowActivator.activate(windows[selectedIndex])
    }

    private func cancel() {
        hidePanel()
        isActive = false
    }

    // MARK: - Panel

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel

        let size = SwitcherLayout.panelSize(windowCount: windows.count)
        panel.setContentSize(size)

        let screen = screenWithMouse()
        let frame = screen.frame
        let origin = CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        let hosting = NSHostingController(rootView: SwitcherView(model: self))
        hosting.sizingOptions = []
        panel.contentViewController = hosting
        self.hosting = hosting
        return panel
    }
}
