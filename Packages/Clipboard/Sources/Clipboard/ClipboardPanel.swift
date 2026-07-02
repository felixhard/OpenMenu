import AppKit

/// Borderless glass panel for the clipboard history. Becomes key so the search
/// field can take text, and auto-hides when focus leaves it.
final class ClipboardPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 488, height: 540),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .modalPanel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
}
