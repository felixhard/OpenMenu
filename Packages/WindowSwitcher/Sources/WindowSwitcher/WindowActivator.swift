import AppKit
import ApplicationServices

/// Brings a chosen window to the front. Primary path is a window-server-level
/// focus (see `WindowServerFocus`), which keys the exact window and follows it
/// to other Spaces; an AX raise on top handles unminimizing and main-window
/// state when AX has an element for the window.
public enum WindowActivator {

    public static func activate(_ window: WindowInfo) {
        let target = axWindow(for: window)

        // Restore a minimized window before focusing it.
        if let target, window.isMinimized {
            AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        let focused = WindowServerFocus.focus(window.id)
        if !focused {
            // Private API failed; fall back to plain app activation.
            NSRunningApplication(processIdentifier: window.pid)?
                .activate(options: target == nil ? [.activateAllWindows] : [])
        }

        if let target {
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// The AX element backing the window, if AX can see it (active Space,
    /// minimized, or hidden app). Windows on other Spaces have none; for those
    /// the window-server focus does all the work.
    private static func axWindow(for window: WindowInfo) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
            let axWindows = value as? [AXUIElement]
        else { return nil }

        if let match = axWindows.first(where: { WindowTitles.windowID(of: $0) == window.id }) {
            return match
        }
        // Fall back to a title match when the window-id bridge is unavailable.
        guard !window.title.isEmpty else { return nil }
        return axWindows.first {
            WindowTitles.stringValue($0, kAXTitleAttribute as String) == window.title
        }
    }
}
