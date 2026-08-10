import AppKit
import CoreGraphics
import ApplicationServices

/// Builds the list of switchable windows across every Space: the active Space's
/// windows in front-to-back z-order, then windows on other Spaces (found via the
/// private CGS APIs, since neither AX nor the public on-screen CG list can see
/// them), then minimized and hidden-app windows, which only AX reports.
public enum WindowEnumerator {

    /// Windows smaller than this on either axis are helper surfaces (toolbars,
    /// hover strips, bubbles), never real documents.
    private static let minWindowSide: CGFloat = 80

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
        let regularPIDs = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map(\.processIdentifier)
        let axWindows = WindowTitles.axWindows(forApps: regularPIDs)

        var seen = Set<CGWindowID>()
        var active: [WindowInfo] = []
        var offSpace: [WindowInfo] = []
        var minimized: [WindowInfo] = []

        // 1) Visible windows on the active Space(s), front-to-back z-order.
        let onScreen = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for candidate in candidates(from: onScreen, ownPID: ownPID)
        where seen.insert(candidate.id).inserted {
            active.append(makeInfo(candidate, ax: axWindows[candidate.id]))
        }

        // 2) Windows on every other Space, including fullscreen Spaces.
        let spaces = Spaces.snapshot()
        for space in spaces.all where !spaces.active.contains(space) {
            let ids = Spaces.windowIDs(in: space).filter { !seen.contains($0) }
            for candidate in candidates(from: Spaces.windowDescriptions(ids), ownPID: ownPID) {
                guard seen.insert(candidate.id).inserted else { continue }
                let ax = axWindows[candidate.id]
                // AX sees the window but says it is not a standard document
                // window (a sheet, palette, ...): skip it. No AX element is the
                // normal case here; AX cannot see other Spaces.
                if let ax, !ax.isStandard { continue }
                let info = makeInfo(candidate, ax: ax)
                if info.isMinimized { minimized.append(info) } else { offSpace.append(info) }
            }
        }

        // 3) Whatever only AX can see: minimized windows on the active Space and
        //    windows of hidden apps.
        let leftovers = axWindows
            .filter { !seen.contains($0.key) && $0.value.isStandard }
            .sorted { $0.key < $1.key }
        for (id, ax) in leftovers {
            let size = ax.size ?? .zero
            guard size.width >= minWindowSide, size.height >= minWindowSide else { continue }
            seen.insert(id)
            let app = NSRunningApplication(processIdentifier: ax.pid)
            let info = WindowInfo(
                id: id,
                pid: ax.pid,
                appName: app?.localizedName ?? "Unknown",
                bundleID: app?.bundleIdentifier,
                title: ax.title,
                bounds: .zero,
                icon: app?.icon,
                isMinimized: ax.isMinimized
            )
            if ax.isMinimized { minimized.append(info) } else { offSpace.append(info) }
        }

        return active + offSpace + minimized
    }

    private static func makeInfo(_ candidate: Candidate, ax: WindowTitles.AXWindow?) -> WindowInfo {
        // Prefer the AX title (available without Screen Recording); the CG title
        // is the only source for windows on other Spaces.
        let axTitle = ax?.title ?? ""
        return WindowInfo(
            id: candidate.id,
            pid: candidate.pid,
            appName: candidate.appName,
            bundleID: candidate.app?.bundleIdentifier,
            title: axTitle.isEmpty ? candidate.cgTitle : axTitle,
            bounds: candidate.bounds,
            icon: candidate.app?.icon,
            isMinimized: ax?.isMinimized ?? false
        )
    }

    /// Filters raw CG window dictionaries (from `CGWindowListCopyWindowInfo` or
    /// `CGWindowListCreateDescriptionFromArray`, same keys) down to plausible
    /// document windows of regular apps.
    private static func candidates(from entries: [[String: Any]], ownPID: pid_t) -> [Candidate] {
        var result: [Candidate] = []
        for entry in entries {
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
            if bounds.width < minWindowSide || bounds.height < minWindowSide { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            if let app, app.activationPolicy != .regular { continue }

            result.append(
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
        return result
    }
}
