import AppKit
import SwiftUI
import QuartzCore

/// Non-interactive overlay that previews the active tiling layout, highlighting
/// the tile the window will snap into.
final class SnapOverlay {
    private var window: NSWindow?
    private var hosting: NSHostingController<SnapOverlayView>?

    func show(target: SnapTarget, visibleFrame: CGRect) {
        let window = window ?? makeWindow()
        self.window = window
        window.setFrame(visibleFrame, display: true)
        hosting?.rootView = SnapOverlayView(target: target)

        // First appearance fades the whole overlay in; moving between zones keeps it
        // visible and lets the SwiftUI cross-fade handle the change.
        if !window.isVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak window] in
            // Don't order out if a new show() restarted the fade-in meanwhile.
            if window?.alphaValue == 0 { window?.orderOut(nil) }
        })
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hosting = NSHostingController(rootView: SnapOverlayView(target: SnapTarget(layout: .twoTile, zone: .left)))
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentViewController = hosting
        self.hosting = hosting
        return window
    }
}

private struct SnapOverlayView: View {
    let target: SnapTarget

    var body: some View {
        GeometryReader { geo in
            // Only preview the zone the window will snap into — no outlines for the
            // other tiles in the layout. Use the *same* gap geometry as the real
            // snap so the preview matches the window's final size exactly.
            let container = CGRect(origin: .zero, size: geo.size)
            let unit = target.zone.unitRect
            let base = CGRect(x: unit.minX * geo.size.width,
                              y: unit.minY * geo.size.height,
                              width: unit.width * geo.size.width,
                              height: unit.height * geo.size.height)
            let frame = SnapGeometry.applyGap(to: base, in: container)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                )
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                // Give each zone its own identity so switching zones cross-fades the
                // preview in at the proposed position instead of sliding it there
                // from wherever it was last shown.
                .id(target.zone)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .animation(.easeInOut(duration: 0.16), value: target.zone)
    }
}
