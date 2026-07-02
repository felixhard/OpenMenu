import ApplicationServices
import CoreGraphics

// Private CoreGraphics/AX bridge used by most macOS window switchers (e.g. AltTab)
// to map an Accessibility window element to its CGWindowID. Stable for years.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Resolves window titles via the Accessibility API, keyed by CGWindowID.
///
/// `CGWindowListCopyWindowInfo` titles are redacted without Screen Recording, but
/// AX titles only need Accessibility (which the switcher already requires), so this
/// gives us real subtitles and precise window matching.
enum WindowTitles {

    /// The CGWindowID backing an AX window element, if available.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var wid = CGWindowID(0)
        return _AXUIElementGetWindow(element, &wid) == .success && wid != 0 ? wid : nil
    }

    /// All AX window elements for a process (includes minimized / off-Space windows).
    static func windowList(forApp pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// Whether the element is a normal document/app window (not a sheet, palette, etc.).
    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        stringValue(element, kAXSubroleAttribute as String) == (kAXStandardWindowSubrole as String)
    }

    /// Best-effort `CGWindowID -> title` map for the given process ids.
    static func titlesByWindowID(pids: Set<pid_t>) -> [CGWindowID: String] {
        var result: [CGWindowID: String] = [:]
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            var windowsValue: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                let windows = windowsValue as? [AXUIElement]
            else { continue }

            for window in windows {
                guard let wid = windowID(of: window) else { continue }
                var titleValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                   let title = titleValue as? String, !title.isEmpty {
                    result[wid] = title
                }
            }
        }
        return result
    }
}
