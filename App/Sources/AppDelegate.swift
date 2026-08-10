import AppKit
import WindowSwitcher
import SystemMonitor

final class AppDelegate: NSObject, NSApplicationDelegate {
    let switcher = WindowSwitcherController()
    let stats = SystemStats()
    let settings = AppSettings()

    private var statusItemController: StatusItemController?
    private var onboarding: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.switcher = switcher
        settings.applyInitialSideEffects()
        // When the user clicks "Resume" in the cleaning overlay, flip the toggle off.
        KeyboardCleaning.shared.onResume = { [weak settings] in
            settings?.keyboardCleaning = false
        }
        stats.start()

        // On first launch the onboarding flow owns the Accessibility prompt;
        // suppress the switcher's so the user isn't asked twice at once.
        let needsOnboarding = !OnboardingController.isCompleted
        switcher.start(promptForAccessibilityIfNeeded: !needsOnboarding)
        statusItemController = StatusItemController(stats: stats, settings: settings)

        if needsOnboarding {
            let controller = OnboardingController()
            onboarding = controller
            controller.show { [weak self] in self?.onboarding = nil }
        }
    }
}
