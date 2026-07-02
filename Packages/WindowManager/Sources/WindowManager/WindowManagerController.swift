import AppKit
import ApplicationServices

/// Drag-to-snap tiling manager. While a window is dragged into a corner (quadrant)
/// or a side-middle (half), it shows a preview overlay and snaps on release.
///
/// Driven on/off by the "Window Manager" toggle. Needs Accessibility (to read and
/// move other apps' windows), which the app already requires.
public final class WindowManagerController {
    public static let shared = WindowManagerController()

    private let overlay = SnapOverlay()
    private var monitor: Any?
    private var enabled = false

    // Per-drag gesture state.
    private var captured = false           // grabbed the dragged window yet?
    private var confirmed = false          // confirmed the window is actually moving?
    private var draggedWindow: AXUIElement?
    private var initialPosition: CGPoint?
    private var activeTarget: SnapTarget?

    private init() {}

    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        on ? startMonitoring() : stopMonitoring()
    }

    private func startMonitoring() {
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        overlay.hide()
        resetGesture()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:    resetGesture()
        case .leftMouseDragged: handleDrag()
        case .leftMouseUp:      handleUp()
        default:                break
        }
    }

    private func handleDrag() {
        if !captured {
            captureWindow()
            captured = true
        }
        guard let window = draggedWindow else { return }

        // Only engage once the window has actually moved — avoids snapping during
        // text selection or other in-window drags.
        if !confirmed, let initial = initialPosition, let now = AXWindow.position(of: window) {
            if hypot(now.x - initial.x, now.y - initial.y) > 6 { confirmed = true }
        }
        guard confirmed else { return }

        updateTarget()
    }

    private func captureWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AXWindow.focusedWindow(pid: app.processIdentifier) else { return }
        draggedWindow = window
        initialPosition = AXWindow.position(of: window)
    }

    private func updateTarget() {
        let mouse = NSEvent.mouseLocation
        guard let screen = screen(containing: mouse) else { return }
        let newTarget = SnapGeometry.target(at: mouse, in: screen.visibleFrame)

        guard newTarget != activeTarget else { return }
        activeTarget = newTarget

        if let newTarget {
            overlay.show(target: newTarget, visibleFrame: screen.visibleFrame)
        } else {
            overlay.hide()
        }
    }

    private func handleUp() {
        defer {
            overlay.hide()
            resetGesture()
        }
        guard confirmed,
              let target = activeTarget,
              let window = draggedWindow,
              let screen = screen(containing: NSEvent.mouseLocation) else { return }

        let cocoa = target.zone.cocoaFrame(in: screen.visibleFrame)
        AXWindow.setFrame(window, axRect: AXWindow.axRect(fromCocoa: cocoa))
    }

    private func resetGesture() {
        captured = false
        confirmed = false
        draggedWindow = nil
        initialPosition = nil
        activeTarget = nil
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}
