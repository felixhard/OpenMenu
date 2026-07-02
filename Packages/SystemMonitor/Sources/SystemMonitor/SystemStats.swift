import Foundation
import Darwin

/// Lightweight system stats sampler for the menu bar gauges and the detail popup.
///
/// Reads CPU load (delta of host CPU ticks), memory usage (Mach VM statistics),
/// disk usage (volume capacity), and network throughput (interface byte counters)
/// on a timer. The ring gauges use the `0...1` fractions; the detail graphs use the
/// rolling `*History` buffers and the absolute byte values.
public final class SystemStats: ObservableObject {

    // Fractions in 0...1 for the menu-bar ring gauges.
    @Published public private(set) var cpu: Double = 0
    @Published public private(set) var memory: Double = 0
    @Published public private(set) var disk: Double = 0

    // Absolute values for the detail popup.
    @Published public private(set) var memoryUsedBytes: UInt64 = 0
    @Published public private(set) var memoryTotalBytes: UInt64 = 0
    @Published public private(set) var diskTotalBytes: Int64 = 0
    @Published public private(set) var diskUsedBytes: Int64 = 0
    @Published public private(set) var diskFreeBytes: Int64 = 0

    /// Combined in + out throughput, bytes per second.
    @Published public private(set) var networkBytesPerSec: Double = 0

    // Rolling history for the bar-chart graphs (oldest first, newest last).
    @Published public private(set) var cpuHistory: [Double] = []      // fractions 0...1
    @Published public private(set) var memoryHistory: [Double] = []   // used bytes
    @Published public private(set) var networkHistory: [Double] = []  // bytes / sec

    /// Number of samples retained for each history buffer.
    public let historyLength = 48

    private var timer: Timer?
    private var previousCPU: host_cpu_load_info?
    private var previousNet: (bytes: UInt64, time: Date)?

    public init() {
        memoryTotalBytes = ProcessInfo.processInfo.physicalMemory
    }

    /// Begins periodic sampling on the main run loop.
    public func start(interval: TimeInterval = 2) {
        update()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        if let cpu = Self.sampleCPU(previous: &previousCPU) {
            self.cpu = cpu
            push(cpu, into: &cpuHistory)
        }
        if let mem = Self.sampleMemory() {
            memoryUsedBytes = mem.used
            memoryTotalBytes = mem.total
            memory = mem.total > 0 ? Double(mem.used) / Double(mem.total) : 0
            push(Double(mem.used), into: &memoryHistory)
        }
        if let d = Self.sampleDisk() {
            diskTotalBytes = d.total
            diskFreeBytes = d.free
            diskUsedBytes = d.total - d.free
            disk = d.total > 0 ? Double(d.total - d.free) / Double(d.total) : 0
        }
        if let total = Self.sampleNetworkBytes() {
            let now = Date()
            if let prev = previousNet {
                let dt = now.timeIntervalSince(prev.time)
                // Interface counters are 32-bit and can wrap; ignore negative deltas.
                if dt > 0, total >= prev.bytes {
                    networkBytesPerSec = Double(total - prev.bytes) / dt
                }
            }
            previousNet = (total, now)
            push(networkBytesPerSec, into: &networkHistory)
        }
    }

    private func push(_ value: Double, into array: inout [Double]) {
        array.append(value)
        if array.count > historyLength {
            array.removeFirst(array.count - historyLength)
        }
    }

    // MARK: - CPU

    private static func sampleCPU(previous: inout host_cpu_load_info?) -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        defer { previous = info }
        guard let prev = previous else { return nil } // need a baseline first

        let user = Double(info.cpu_ticks.0) - Double(prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1) - Double(prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2) - Double(prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3) - Double(prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return clamp((user + system + nice) / total)
    }

    // MARK: - Memory

    private static func sampleMemory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count)
                    + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }
        return (min(used, total), total)
    }

    // MARK: - Disk

    private static func sampleDisk() -> (total: Int64, free: Int64)? {
        let url = URL(fileURLWithPath: "/")
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
            ]),
            let total = values.volumeTotalCapacity, total > 0
        else { return nil }

        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (Int64(total), available)
    }

    // MARK: - Network

    /// Sum of in + out byte counters across all non-loopback link interfaces.
    private static func sampleNetworkBytes() -> UInt64? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var total: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let addr = p.pointee
            if let sa = addr.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: addr.ifa_name)
                if !name.hasPrefix("lo"), let raw = addr.ifa_data {
                    let data = raw.assumingMemoryBound(to: if_data.self).pointee
                    total += UInt64(data.ifi_ibytes) + UInt64(data.ifi_obytes)
                }
            }
            ptr = addr.ifa_next
        }
        return total
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
