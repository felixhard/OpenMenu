import Foundation
import Combine
import ServiceManagement
import Clipboard
import WindowManager
import WindowSwitcher

/// User-facing settings (menu bar panel toggles + Settings window), persisted
/// to `UserDefaults`. Each `didSet` pushes the value into the owning feature, so
/// changes apply live.
final class AppSettings: ObservableObject {

    /// The switcher is owned by `AppDelegate`; set once at launch so the
    /// shortcut/titles settings can reach it.
    weak var switcher: WindowSwitcherController?

    // MARK: Feature toggles (menu bar panel)

    @Published var windowManager: Bool {
        didSet {
            persist(windowManager, .windowManager)
            WindowManagerController.shared.setEnabled(windowManager)
        }
    }
    @Published var clipboard: Bool {
        didSet {
            persist(clipboard, .clipboard)
            ClipboardController.shared.setEnabled(clipboard)
        }
    }
    @Published var keyboardCleaning: Bool {
        didSet {
            persist(keyboardCleaning, .keyboardCleaning)
            KeyboardCleaning.shared.setActive(keyboardCleaning)
        }
    }
    @Published var preventSleep: Bool {
        didSet {
            persist(preventSleep, .preventSleep)
            PowerManager.shared.setPreventSleep(preventSleep)
        }
    }
    // MARK: General

    /// Registered with `SMAppService`, which is the source of truth — the value
    /// is read back from it at launch rather than from `UserDefaults`.
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert so the toggle reflects reality (e.g. denied by MDM).
                launchAtLogin = oldValue
            }
        }
    }

    // MARK: Window Manager (tiles)

    @Published var tileInnerGap: Double {
        didSet {
            persist(tileInnerGap, .tileInnerGap)
            SnapGeometry.innerGap = tileInnerGap
        }
    }
    /// Multiplier on the corner/edge drag-trigger hit areas.
    @Published var snapTriggerScale: Double {
        didSet {
            persist(snapTriggerScale, .snapTriggerScale)
            SnapGeometry.setTriggerScale(snapTriggerScale)
        }
    }

    // MARK: Switcher

    @Published var switcherModifier: WindowSwitcherController.HotKeyModifier {
        didSet {
            defaults.set(switcherModifier.rawValue, forKey: Key.switcherModifier.rawValue)
            switcher?.hotKeyModifier = switcherModifier
        }
    }
    @Published var switcherShowsTitles: Bool {
        didSet {
            persist(switcherShowsTitles, .switcherShowsTitles)
            switcher?.showsWindowTitles = switcherShowsTitles
        }
    }

    // MARK: Clipboard

    @Published var clipboardMaxItems: Int {
        didSet {
            defaults.set(clipboardMaxItems, forKey: Key.clipboardMaxItems.rawValue)
            ClipboardController.shared.store.maxItems = clipboardMaxItems
        }
    }
    /// Hours to keep clipboard items; `0` means forever.
    @Published var clipboardRetentionHours: Double {
        didSet {
            persist(clipboardRetentionHours, .clipboardRetentionHours)
            ClipboardController.shared.store.retention = Self.retentionInterval(hours: clipboardRetentionHours)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        windowManager = defaults.bool(forKey: Key.windowManager.rawValue, default: true)
        clipboard = defaults.bool(forKey: Key.clipboard.rawValue, default: true)
        // Never restore keyboard-cleaning as active on launch — that would block
        // input the moment the app starts.
        keyboardCleaning = false
        preventSleep = defaults.bool(forKey: Key.preventSleep.rawValue, default: false)

        launchAtLogin = SMAppService.mainApp.status == .enabled
        tileInnerGap = defaults.double(forKey: Key.tileInnerGap.rawValue, default: 8)
        snapTriggerScale = defaults.double(forKey: Key.snapTriggerScale.rawValue, default: 1)
        switcherModifier = WindowSwitcherController.HotKeyModifier(
            rawValue: defaults.string(forKey: Key.switcherModifier.rawValue) ?? "") ?? .command
        switcherShowsTitles = defaults.bool(forKey: Key.switcherShowsTitles.rawValue, default: true)
        clipboardMaxItems = defaults.integer(forKey: Key.clipboardMaxItems.rawValue, default: 200)
        clipboardRetentionHours = defaults.double(forKey: Key.clipboardRetentionHours.rawValue, default: 12)
    }

    /// Applies any side effects for the persisted state at launch.
    func applyInitialSideEffects() {
        PowerManager.shared.setPreventSleep(preventSleep)
        ClipboardController.shared.setEnabled(clipboard)
        WindowManagerController.shared.setEnabled(windowManager)

        SnapGeometry.innerGap = tileInnerGap
        SnapGeometry.setTriggerScale(snapTriggerScale)
        switcher?.hotKeyModifier = switcherModifier
        switcher?.showsWindowTitles = switcherShowsTitles
        ClipboardController.shared.store.maxItems = clipboardMaxItems
        ClipboardController.shared.store.retention = Self.retentionInterval(hours: clipboardRetentionHours)
    }

    private static func retentionInterval(hours: Double) -> TimeInterval? {
        hours <= 0 ? nil : hours * 60 * 60
    }

    private enum Key: String {
        case windowManager, clipboard, keyboardCleaning, preventSleep
        case tileInnerGap, snapTriggerScale
        case switcherModifier, switcherShowsTitles
        case clipboardMaxItems, clipboardRetentionHours
    }

    private func persist(_ value: Bool, _ key: Key) { defaults.set(value, forKey: key.rawValue) }
    private func persist(_ value: Double, _ key: Key) { defaults.set(value, forKey: key.rawValue) }
}

private extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
    func double(forKey key: String, default defaultValue: Double) -> Double {
        object(forKey: key) == nil ? defaultValue : double(forKey: key)
    }
    func integer(forKey key: String, default defaultValue: Int) -> Int {
        object(forKey: key) == nil ? defaultValue : integer(forKey: key)
    }
}
