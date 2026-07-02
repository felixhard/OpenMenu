import AppKit
import CoreGraphics
import ApplicationServices

/// Builds the list of switchable windows: visible windows in z-order from Core
/// Graphics, followed by minimized / off-Space windows discovered via Accessibility.
public enum WindowEnumerator {

    private struct Candidate {
        let id: CGWindowID
        let pid: pid_t
        let appName: String
        let cgTitle: String
        let bounds: CGRect
        let app: NSRunningApplication?
    }

    public static func currentWindows() -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var infos: [WindowInfo] = []
        var seen = Set<CGWindowID>()

        // 1) Visible, on-screen windows in front-to-back z-order.
        let candidates = onScreenCandidates(ownPID: ownPID)
        let titles = WindowTitles.titlesByWindowID(pids: Set(candidates.map(\.pid)))
        for candidate in candidates where !seen.contains(candidate.id) {
            infos.append(
                WindowInfo(
                    id: candidate.id,
                    pid: candidate.pid,
                    appName: candidate.appName,
                    bundleID: candidate.app?.bundleIdentifier,
                    title: titles[candidate.id] ?? candidate.cgTitle,
                    bounds: candidate.bounds,
                    icon: candidate.app?.icon,
                    isMinimized: false
                )
            )
            seen.insert(candidate.id)
        }

        // 2) Minimized / off-Space standard windows via Accessibility.
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
        }
        for app in regularApps {
            for window in WindowTitles.windowList(forApp: app.processIdentifier) {
                guard
                    let id = WindowTitles.windowID(of: window),
                    !seen.contains(id),
                    WindowTitles.isStandardWindow(window)
                else { continue }

                infos.append(
                    WindowInfo(
                        id: id,
                        pid: app.processIdentifier,
                        appName: app.localizedName ?? "Unknown",
                        bundleID: app.bundleIdentifier,
                        title: WindowTitles.stringValue(window, kAXTitleAttribute as String) ?? "",
                        bounds: .zero,
                        icon: app.icon,
                        isMinimized: WindowTitles.boolValue(window, kAXMinimizedAttribute as String)
                    )
                )
                seen.insert(id)
            }
        }

        return infos
    }

    private static func onScreenCandidates(ownPID: pid_t) -> [Candidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var candidates: [Candidate] = []
        for entry in raw {
            guard
                let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                let windowNumber = entry[kCGWindowNumber as String] as? CGWindowID,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                pid != ownPID
            else { continue }

            var bounds = CGRect.zero
            if let b = entry[kCGWindowBounds as String] as? [String: CGFloat] {
                bounds = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                                width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            }
            if bounds.width < 80 || bounds.height < 80 { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            if let app, app.activationPolicy != .regular { continue }

            candidates.append(
                Candidate(
                    id: windowNumber,
                    pid: pid,
                    appName: entry[kCGWindowOwnerName as String] as? String ?? app?.localizedName ?? "Unknown",
                    cgTitle: entry[kCGWindowName as String] as? String ?? "",
                    bounds: bounds,
                    app: app
                )
            )
        }
        return candidates
    }
}
