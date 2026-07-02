import Foundation
import Darwin
import AppKit

/// One row in the process list. A row is either a single process or an app group
/// that aggregates its helper processes (exposed as `children`).
public struct ProcessRow: Identifiable, Equatable {
    public let id: Int32                 // representative pid
    public let name: String
    public let bundleIdentifier: String?
    /// Path to the `.app` bundle, used by the UI to resolve an icon. Nil for
    /// system / command-line processes.
    public let bundlePath: String?
    public let isSystemGroup: Bool
    /// CPU share of total machine capacity, 0...1 (1.0 == every core saturated).
    public var cpu: Double
    public var memoryBytes: UInt64
    /// Combined in + out network throughput, bytes per second (from `nettop`).
    public var networkBytes: UInt64
    public var children: [ProcessRow]

    public var childCount: Int { children.count }

    public static func == (lhs: ProcessRow, rhs: ProcessRow) -> Bool {
        lhs.id == rhs.id && lhs.cpu == rhs.cpu && lhs.memoryBytes == rhs.memoryBytes
            && lhs.networkBytes == rhs.networkBytes && lhs.children.count == rhs.children.count
    }
}

/// Samples per-process CPU and resident memory via `libproc`, then groups helper
/// processes under their owning app (everything else under a single "System" row).
///
/// Per-process CPU is computed from the delta of each process's accumulated CPU
/// time between two samples, normalised to total machine capacity. Processes owned
/// by other users (most root daemons) can't be read without elevated privileges and
/// are simply skipped — so values reflect what this user's session can see.
public final class ProcessSampler: ObservableObject {

    @Published public private(set) var rows: [ProcessRow] = []

    private var timer: Timer?
    private var previousCPUTime: [Int32: UInt64] = [:]   // pid -> accumulated cpu nanos
    private var previousSampleTime: Date?
    private let coreCount = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))

    // Per-process network throughput, sampled out-of-band via `nettop` (deltas of
    // its cumulative byte counters). Populated one tick behind the CPU/memory scan.
    private let netQueue = DispatchQueue(label: "com.openmenu.nettop")
    private var netBusy = false
    private var previousNet: [Int32: UInt64] = [:]       // pid -> cumulative in+out bytes
    private var previousNetTime: Date?
    private var netRateByPid: [Int32: UInt64] = [:]      // pid -> bytes / sec

    public init() {}

    /// Starts sampling. Driven on demand (only while the detail popup is open) to
    /// avoid the per-process scan cost when nothing is watching. Idempotent: calling
    /// it again while already running (e.g. on every tab switch) is a no-op, so the
    /// CPU baseline isn't reset and timers don't stack.
    public func start(interval: TimeInterval = 2) {
        guard timer == nil else { return }
        update()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Force-quits every process represented by `row` — an app together with its
    /// helper processes. Real apps are asked to `forceTerminate`; anything else gets
    /// SIGKILL. The aggregated "System" bucket is never terminated as a unit (it's
    /// hundreds of unrelated daemons), so callers should not offer it.
    @discardableResult
    public func forceQuit(_ row: ProcessRow) -> Bool {
        guard !row.isSystemGroup else { return false }
        let pids = row.children.isEmpty ? [row.id] : row.children.map(\.id)
        for pid in pids where pid > 0 {
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.forceTerminate()
            } else {
                kill(pid, SIGKILL)
            }
        }
        // Re-sample shortly so the killed row drops out of the list promptly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.update()
        }
        return true
    }

    // MARK: - Sampling

    private func update() {
        let pids = Self.allPIDs()
        let now = Date()
        let elapsed = previousSampleTime.map { now.timeIntervalSince($0) } ?? 0

        // App bundle path -> (display name, bundle id) for the running GUI apps,
        // so helpers living inside an .app get a friendly name and icon.
        var appByBundlePath: [String: (name: String, bundleID: String?)] = [:]
        var appPidByBundlePath: [String: Int32] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let path = app.bundleURL?.path else { continue }
            appByBundlePath[path] = (app.localizedName ?? (path as NSString).lastPathComponent, app.bundleIdentifier)
            appPidByBundlePath[path] = app.processIdentifier
        }

        var groups: [String: GroupAccumulator] = [:]
        var freshCPUTime: [Int32: UInt64] = [:]

        for pid in pids where pid > 0 {
            guard let info = Self.taskInfo(pid) else { continue }
            freshCPUTime[pid] = info.cpuNanos

            // Per-process CPU as a fraction of total machine capacity.
            var cpuFraction = 0.0
            if elapsed > 0, let prev = previousCPUTime[pid], info.cpuNanos >= prev {
                cpuFraction = Double(info.cpuNanos - prev) / (elapsed * 1_000_000_000.0 * coreCount)
            }
            cpuFraction = min(max(cpuFraction, 0), 1)

            let path = Self.executablePath(pid)
            let (key, display, bundleID, bundlePath, isSystem) =
                Self.classify(pid: pid, path: path,
                              appByBundlePath: appByBundlePath,
                              appPidByBundlePath: appPidByBundlePath)

            let leafName = Self.processName(pid, fallbackPath: path)
            let leaf = ProcessRow(id: pid, name: leafName, bundleIdentifier: bundleID,
                                  bundlePath: bundlePath, isSystemGroup: false,
                                  cpu: cpuFraction, memoryBytes: info.residentBytes,
                                  networkBytes: netRateByPid[pid] ?? 0, children: [])

            groups[key, default: GroupAccumulator(name: display, bundleID: bundleID,
                                                  bundlePath: bundlePath, isSystem: isSystem)]
                .add(leaf)
        }

        previousCPUTime = freshCPUTime
        previousSampleTime = now
        rows = groups.values.map { $0.row() }

        refreshNetworkRates()
    }

    // MARK: - Network (nettop)

    /// Spawns `nettop` on a background queue, deltas its cumulative per-process byte
    /// counters against the previous sample, and stores the resulting bytes/sec. The
    /// next `update()` picks these up — so network values trail CPU/memory by a tick.
    private func refreshNetworkRates() {
        guard !netBusy else { return }
        netBusy = true
        netQueue.async { [weak self] in
            let cumulative = Self.runNettop()
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.netBusy = false }
                let now = Date()
                defer { self.previousNet = cumulative; self.previousNetTime = now }
                guard let prevTime = self.previousNetTime else { return }
                let dt = now.timeIntervalSince(prevTime)
                guard dt > 0 else { return }
                var rates: [Int32: UInt64] = [:]
                for (pid, bytes) in cumulative {
                    if let prev = self.previousNet[pid], bytes >= prev {
                        rates[pid] = UInt64(Double(bytes - prev) / dt)
                    }
                }
                self.netRateByPid = rates
            }
        }
    }

    /// One-shot `nettop` sample → cumulative in+out bytes per pid. Lines look like
    /// `Wispr Flow.73506,27683,19532,` — the pid is the trailing dotted segment.
    private static func runNettop() -> [Int32: UInt64] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-x", "-L", "1", "-n", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [:] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int32: UInt64] = [:]
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let ident = cols[0]
            guard let dot = ident.lastIndex(of: "."),
                  let pid = Int32(ident[ident.index(after: dot)...]) else { continue }
            let inBytes = UInt64(cols[1]) ?? 0
            let outBytes = UInt64(cols[2]) ?? 0
            result[pid, default: 0] += inBytes + outBytes
        }
        return result
    }

    /// Accumulates leaf processes into a single displayed group.
    private struct GroupAccumulator {
        let name: String
        let bundleID: String?
        let bundlePath: String?
        let isSystem: Bool
        var cpu: Double = 0
        var memory: UInt64 = 0
        var network: UInt64 = 0
        var leaves: [ProcessRow] = []

        mutating func add(_ leaf: ProcessRow) {
            cpu += leaf.cpu
            memory += leaf.memoryBytes
            network += leaf.networkBytes
            leaves.append(leaf)
        }

        func row() -> ProcessRow {
            let sortedLeaves = leaves.sorted { $0.memoryBytes > $1.memoryBytes }
            // Single-process groups collapse to a plain row (no disclosure / children).
            let children = sortedLeaves.count > 1 ? sortedLeaves : []
            let id = sortedLeaves.first?.id ?? 0
            return ProcessRow(id: id, name: name, bundleIdentifier: bundleID,
                              bundlePath: bundlePath, isSystemGroup: isSystem,
                              cpu: cpu, memoryBytes: memory, networkBytes: network, children: children)
        }
    }

    /// Decides which group a process belongs to.
    /// Returns the group key plus the display metadata for that group.
    private static func classify(
        pid: Int32, path: String?,
        appByBundlePath: [String: (name: String, bundleID: String?)],
        appPidByBundlePath: [String: Int32]
    ) -> (key: String, name: String, bundleID: String?, bundlePath: String?, isSystem: Bool) {
        // Helpers (and the main app) live inside "…/<App>.app/…".
        if let path, let r = path.range(of: ".app/") {
            let bundlePath = String(path[path.startIndex..<r.lowerBound]) + ".app"
            if let info = appByBundlePath[bundlePath] {
                return (bundlePath, info.name, info.bundleID, bundlePath, false)
            }
            let name = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
            return (bundlePath, name, nil, bundlePath, false)
        }
        // A running GUI app whose main executable isn't inside an .app (rare).
        if let entry = appByBundlePath.first(where: { appPidByBundlePath[$0.key] == pid }) {
            return (entry.key, entry.value.name, entry.value.bundleID, entry.key, false)
        }
        // Everything else: daemons, agents, command-line tools.
        return ("__system__", "System", nil, nil, true)
    }

    // MARK: - libproc wrappers

    private static func allPIDs() -> [Int32] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        let capacity = Int(needed) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: capacity)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, needed)
        guard got > 0 else { return [] }
        let count = Int(got) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(count))
    }

    private static func taskInfo(_ pid: Int32) -> (residentBytes: UInt64, cpuNanos: UInt64)? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return (info.pti_resident_size, info.pti_total_user + info.pti_total_system)
    }

    private static func executablePath(_ pid: Int32) -> String? {
        let maxSize = 4 * 1024 // PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN)
        var buffer = [CChar](repeating: 0, count: maxSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func processName(_ pid: Int32, fallbackPath: String?) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let name = String(cString: buffer)
            if !name.isEmpty { return name }
        }
        if let path = fallbackPath {
            return (path as NSString).lastPathComponent
        }
        return "pid \(pid)"
    }
}
