import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

// Private window-server (SkyLight/CGS) APIs, the same set AltTab is built on.
// They are not in any linkable SDK, so they are resolved at runtime with dlsym;
// every call degrades gracefully (empty list / false) if a symbol ever vanishes.

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

private enum SkyLight {
    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }

    typealias MainConnectionID = @convention(c) () -> CGSConnectionID
    typealias CopyManagedDisplaySpaces = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>
    typealias CopyWindowsWithOptionsAndTags = @convention(c) (
        CGSConnectionID, UInt32, CFArray, UInt32,
        UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>
    typealias GetWindowOwner = @convention(c) (
        CGSConnectionID, CGWindowID, UnsafeMutablePointer<CGSConnectionID>
    ) -> CGError
    typealias GetConnectionPSN = @convention(c) (
        CGSConnectionID, UnsafeMutablePointer<ProcessSerialNumber>
    ) -> CGError
    typealias SetFrontProcessWithOptions = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32
    ) -> CGError
    typealias PostEventRecordTo = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
    ) -> CGError

    static let mainConnectionID = symbol("CGSMainConnectionID", as: MainConnectionID.self)
    static let copyManagedDisplaySpaces = symbol("CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpaces.self)
    static let copyWindowsWithOptionsAndTags = symbol("CGSCopyWindowsWithOptionsAndTags", as: CopyWindowsWithOptionsAndTags.self)
    static let getWindowOwner = symbol("CGSGetWindowOwner", as: GetWindowOwner.self)
    static let getConnectionPSN = symbol("CGSGetConnectionPSN", as: GetConnectionPSN.self)
    static let setFrontProcessWithOptions = symbol("_SLPSSetFrontProcessWithOptions", as: SetFrontProcessWithOptions.self)
    static let postEventRecordTo = symbol("SLPSPostEventRecordTo", as: PostEventRecordTo.self)
}

/// Enumerates Mission Control Spaces and the windows on them. This is the only
/// route to windows on non-active Spaces: the Accessibility API returns only the
/// active Space's windows (plus minimized/hidden ones), and the public CG list
/// with `.optionOnScreenOnly` is likewise limited to the active Space.
enum Spaces {

    struct Snapshot {
        /// Every Space on every display, including fullscreen Spaces.
        let all: [CGSSpaceID]
        /// The Space currently shown on each display.
        let active: Set<CGSSpaceID>
    }

    static func snapshot() -> Snapshot {
        guard
            let mainConnectionID = SkyLight.mainConnectionID,
            let copySpaces = SkyLight.copyManagedDisplaySpaces,
            let displays = copySpaces(mainConnectionID()).takeRetainedValue() as? [[String: Any]]
        else { return Snapshot(all: [], active: []) }

        var all: [CGSSpaceID] = []
        var active: Set<CGSSpaceID> = []
        for display in displays {
            if let current = (display["Current Space"] as? [String: Any])?["id64"] as? CGSSpaceID {
                active.insert(current)
            }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                if let id = space["id64"] as? CGSSpaceID { all.append(id) }
            }
        }
        return Snapshot(all: all, active: active)
    }

    static func windowIDs(in space: CGSSpaceID) -> [CGWindowID] {
        guard
            let mainConnectionID = SkyLight.mainConnectionID,
            let copyWindows = SkyLight.copyWindowsWithOptionsAndTags
        else { return [] }
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        // 0x7 includes invisible and minimized windows, not just visible ones.
        let ids = copyWindows(
            mainConnectionID(), 0, [NSNumber(value: space)] as CFArray, 0x7, &setTags, &clearTags
        ).takeRetainedValue() as? [NSNumber] ?? []
        return ids.map { CGWindowID($0.uint32Value) }
    }

    /// Info dictionaries (same keys as `CGWindowListCopyWindowInfo`) for specific
    /// window ids. `CGWindowListCreateDescriptionFromArray` wants the raw ids as
    /// the array elements themselves, not boxed in CFNumbers.
    static func windowDescriptions(_ ids: [CGWindowID]) -> [[String: Any]] {
        guard !ids.isEmpty else { return [] }
        let pointers = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: ids.count)
        defer { pointers.deallocate() }
        for (index, id) in ids.enumerated() {
            pointers[index] = UnsafeRawPointer(bitPattern: UInt(id))
        }
        guard let array = CFArrayCreate(nil, pointers, ids.count, nil) else { return [] }
        return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
    }
}

/// Focuses a window at the window-server level: makes its process frontmost keyed
/// to that exact window, then posts the synthesized pair of activation events that
/// make the window key (the AltTab technique). Unlike an AX raise, this works for
/// windows on other Spaces; macOS switches to the window's Space automatically.
enum WindowServerFocus {

    /// kCPSUserGenerated: treat the switch as user-initiated.
    private static let userGenerated: UInt32 = 0x200

    @discardableResult
    static func focus(_ windowID: CGWindowID) -> Bool {
        guard
            let mainConnectionID = SkyLight.mainConnectionID,
            let getWindowOwner = SkyLight.getWindowOwner,
            let getConnectionPSN = SkyLight.getConnectionPSN,
            let setFrontProcess = SkyLight.setFrontProcessWithOptions,
            let postEvent = SkyLight.postEventRecordTo
        else { return false }

        var owner = CGSConnectionID(0)
        guard getWindowOwner(mainConnectionID(), windowID, &owner) == .success else { return false }
        var psn = ProcessSerialNumber()
        guard getConnectionPSN(owner, &psn) == .success else { return false }
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }
        postActivationEvent(postEvent, &psn, windowID, kind: 0x01)
        postActivationEvent(postEvent, &psn, windowID, kind: 0x02)
        return true
    }

    /// Undocumented window-server event record: [0x04] = record length,
    /// [0x08] = event kind, [0x3a] = 0x10 marks a window event,
    /// [0x3c...0x3f] = window id, [0x20...0x2f] = 0xff padding.
    private static func postActivationEvent(
        _ postEvent: SkyLight.PostEventRecordTo,
        _ psn: inout ProcessSerialNumber,
        _ windowID: CGWindowID,
        kind: UInt8
    ) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x08] = kind
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: UInt32(windowID)) { source in
            for offset in 0..<4 { bytes[0x3c + offset] = source[offset] }
        }
        for offset in 0..<0x10 { bytes[0x20 + offset] = 0xff }
        _ = postEvent(&psn, &bytes)
    }
}
