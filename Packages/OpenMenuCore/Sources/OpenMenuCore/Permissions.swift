import ApplicationServices
import AppKit

/// Thin wrappers around the macOS TCC permissions OpenMenu relies on.
///
/// The window switcher needs **Accessibility** (to read other apps' windows and
/// raise them, and to install the global hotkey tap). Live thumbnails additionally
/// need **Screen Recording**, but the switcher degrades gracefully to app icons
/// when that is denied.
public enum Permissions {

    // MARK: Accessibility

    /// Whether this process is currently trusted for the Accessibility API.
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Checks Accessibility trust, optionally surfacing the system prompt that
    /// deep-links the user to System Settings ▸ Privacy & Security ▸ Accessibility.
    @discardableResult
    public static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility pane in System Settings directly.
    public static func openAccessibilitySettings() {
        open(settingsPane: "Privacy_Accessibility")
    }

    // MARK: Screen Recording (optional — for live thumbnails)

    /// Whether the app currently has Screen Recording permission.
    ///
    /// `CGPreflightScreenCaptureAccess` reports status without prompting.
    public static var isScreenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Requests Screen Recording access. Returns immediately; the first call
    /// surfaces the system prompt. Thumbnails fall back to app icons if denied.
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        open(settingsPane: "Privacy_ScreenCapture")
    }

    // MARK: Full Disk Access (for disk scanning)

    /// Best-effort probe for Full Disk Access. There is no public API, so we try to
    /// read a TCC-protected location (`~/Library/Safari`): it lists successfully only
    /// when the app holds Full Disk Access, and returns empty / throws otherwise.
    public static var isFullDiskAccessGranted: Bool {
        let probe = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Safari")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: probe) else {
            return false
        }
        return !contents.isEmpty
    }

    public static func openFullDiskAccessSettings() {
        open(settingsPane: "Privacy_AllFiles")
    }

    // MARK: - Helpers

    private static func open(settingsPane pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
