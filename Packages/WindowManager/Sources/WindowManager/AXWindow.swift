import AppKit
import ApplicationServices

/// Accessibility helpers for reading and moving the window being dragged.
enum AXWindow {

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        return (value as! AXUIElement)
    }

    static func position(of window: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    /// Moves/resizes a window. `axRect` is in Accessibility coordinates (top-left origin).
    static func setFrame(_ window: AXUIElement, axRect: CGRect) {
        var origin = axRect.origin
        var size = axRect.size
        // Position before and after size — some apps clamp size against the old frame.
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    /// Converts a Cocoa rect (bottom-left origin) to Accessibility coordinates
    /// (top-left origin, measured from the top of the primary display).
    static func axRect(fromCocoa cocoa: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height
            ?? cocoa.height
        return CGRect(x: cocoa.minX,
                      y: primaryHeight - cocoa.maxY,
                      width: cocoa.width,
                      height: cocoa.height)
    }
}
