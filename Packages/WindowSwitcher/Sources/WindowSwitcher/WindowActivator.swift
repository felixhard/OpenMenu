import AppKit
import ApplicationServices

/// Brings a chosen window to the front: activates its app, then raises and
/// focuses the specific window via the Accessibility API.
public enum WindowActivator {

    public static func activate(_ window: WindowInfo) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        app?.activate(options: [.activateAllWindows])

        let axApp = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
            let axWindows = value as? [AXUIElement]
        else { return }

        let target = axWindows.first { WindowTitles.windowID(of: $0) == window.id }
            ?? bestMatch(in: axWindows, for: window)
            ?? axWindows.first
        if let target {
            // Restore a minimized window before raising it.
            AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// Falls back to matching an AX window by title when the precise window-id
    /// match isn't available.
    private static func bestMatch(in axWindows: [AXUIElement], for window: WindowInfo) -> AXUIElement? {
        guard !window.title.isEmpty else { return nil }
        for ax in axWindows {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(ax, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String, title == window.title {
                return ax
            }
        }
        return nil
    }
}
