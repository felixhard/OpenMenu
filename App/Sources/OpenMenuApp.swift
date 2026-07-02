import SwiftUI

@main
struct OpenMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar UI is a custom status item + panel managed by AppDelegate.
        // This Settings scene provides the Settings window (⌘ ,).
        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
        }
    }
}
