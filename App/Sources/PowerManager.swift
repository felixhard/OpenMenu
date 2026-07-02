import Foundation

/// Keeps the system awake while "Prevent Sleep" is on, using a `ProcessInfo`
/// activity assertion (no special entitlements required).
final class PowerManager {
    static let shared = PowerManager()
    private var token: NSObjectProtocol?

    private init() {}

    func setPreventSleep(_ enabled: Bool) {
        if enabled {
            guard token == nil else { return }
            token = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "OpenMenu: Prevent Sleep"
            )
        } else if let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
}
