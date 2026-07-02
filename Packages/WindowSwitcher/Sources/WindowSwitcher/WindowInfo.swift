import AppKit
import CoreGraphics

/// A single switchable on-screen window.
public struct WindowInfo: Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let bundleID: String?
    public let title: String
    public let bounds: CGRect
    public let icon: NSImage?
    public let isMinimized: Bool

    /// Window title, falling back to the app name when the title is unavailable
    /// (many apps don't expose `kCGWindowName` without extra entitlements).
    public var displayTitle: String {
        title.isEmpty ? appName : title
    }
}
