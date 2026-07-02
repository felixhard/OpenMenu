import AppKit
import WindowSwitcher
import SystemMonitor

final class AppDelegate: NSObject, NSApplicationDelegate {
    let switcher = WindowSwitcherController()
    let stats = SystemStats()
    let settings = AppSettings()

    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.switcher = switcher
        settings.applyInitialSideEffects()
        // When the user clicks "Resume" in the cleaning overlay, flip the toggle off.
        KeyboardCleaning.shared.onResume = { [weak settings] in
            settings?.keyboardCleaning = false
        }
        stats.start()
        switcher.start()
        statusItemController = StatusItemController(stats: stats, settings: settings)
    }
}
