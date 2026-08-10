import AppKit
import SwiftUI

/// Shows the first-launch onboarding window and records completion, so the
/// flow appears on every launch until the user finishes it once.
@MainActor
final class OnboardingController {

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }
    private static let completedKey = "onboardingCompleted"

    private var window: NSWindow?
    private var onFinish: (() -> Void)?

    func show(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish

        let hosting = NSHostingController(rootView: OnboardingView { [weak self] in
            self?.complete()
        })
        // Transparent host so only the glass card shows.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        let window = OnboardingWindow(contentViewController: hosting)
        // Size first, then center: the window is zero-sized until the SwiftUI
        // content is measured, and centering a zero-sized window puts its
        // bottom-left corner at midscreen (window ends up top-right).
        let size = hosting.view.fittingSize
        window.setContentSize(size)
        if let screen = NSScreen.main?.visibleFrame {
            // Biased a bit above true center, like the system-monitor popup.
            window.setFrameOrigin(CGPoint(
                x: screen.midX - size.width / 2,
                y: screen.midY - size.height / 2 + 60))
        } else {
            window.center()
        }
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.animator().alphaValue = 1
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // NSAnimationContext completion handlers run on the main thread.
            MainActor.assumeIsolated {
                window.orderOut(nil)
                self?.window = nil
                self?.onFinish?()
            }
        })
    }
}

/// Borderless transparent window for the centered onboarding card. Fixed size
/// (driven by the SwiftUI content's fixed frame), draggable by its background.
private final class OnboardingWindow: NSWindow {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc hides the window without marking onboarding complete, so the flow
    /// simply returns on the next launch.
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
