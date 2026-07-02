import AppKit
import SwiftUI
import CoreGraphics
import ApplicationServices
import OpenMenuCore

/// "Keyboard Cleaning" mode: temporarily blocks all keyboard input (so you can
/// wipe the keys) while showing a full-screen overlay. The mouse stays active, so
/// the user can always click to resume.
final class KeyboardCleaning {
    static let shared = KeyboardCleaning()

    /// Invoked when cleaning ends, so the menu toggle can flip back off.
    var onResume: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlay: NSWindow?
    private(set) var isActive = false

    private init() {}

    func setActive(_ active: Bool) {
        active ? start() : stop()
    }

    private func start() {
        guard !isActive else { return }
        guard AXIsProcessTrusted() else {
            // Can't block input without Accessibility — bail and reset the toggle.
            onResume?()
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)

        // The callback swallows every keyboard event by returning nil. It captures
        // nothing, so it's usable as a C function pointer. If the system ever
        // disables the tap, the keyboard simply comes back — a safe failure.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, _, _ in nil },
            userInfo: nil
        ) else {
            onResume?()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source

        showOverlay()
        isActive = true
    }

    private func stop() {
        guard isActive else { return }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        overlay?.orderOut(nil)
        overlay = nil
        isActive = false
    }

    private func resumeFromOverlay() {
        if let onResume { onResume() } else { stop() }
    }

    private func showOverlay() {
        let frame = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: KeyboardCleaningOverlay { [weak self] in
            self?.resumeFromOverlay()
        })
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        overlay = window
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct KeyboardCleaningOverlay: View {
    var onResume: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "keyboard")
                    .font(.system(size: 60, weight: .light))
                Text("Keyboard Disabled")
                    .font(.system(size: 28, weight: .bold))
                Text("Wipe away — keyboard input is paused for cleaning.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                Button(action: onResume) {
                    Text("Click to Resume").padding(.horizontal, 10)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(LiquidGlass.accent)
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onResume)
    }
}
