import Foundation

/// A removable-files category shown in the Disk tab. Cleaning a category deletes the
/// *contents* of its `roots` — never the root directories themselves.
public struct CleanupCategory: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let systemImage: String
    public let roots: [URL]
    public var sizeBytes: Int64
    public var fileCount: Int
    public var selected: Bool
}

/// Scans a curated set of user-level cache/log/trash/developer directories for
/// safely-removable files and (on request) permanently deletes them.
///
/// Everything here lives under the user's home directory, so no Full Disk Access is
/// required. Scanning and deletion run on a background queue; results publish on the
/// main thread.
public final class DiskCleaner: ObservableObject {

    @Published public private(set) var categories: [CleanupCategory]
    @Published public private(set) var isScanning = false
    @Published public private(set) var lastScan: Date?

    private let queue = DispatchQueue(label: "com.openmenu.diskcleaner", qos: .utility)

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func path(_ p: String) -> URL { home.appendingPathComponent(p) }

        categories = [
            CleanupCategory(id: "caches", name: "User Caches", systemImage: "shippingbox.fill",
                            roots: [path("Library/Caches")],
                            sizeBytes: 0, fileCount: 0, selected: true),
            CleanupCategory(id: "logs", name: "Logs", systemImage: "doc.text.fill",
                            roots: [path("Library/Logs")],
                            sizeBytes: 0, fileCount: 0, selected: true),
            CleanupCategory(id: "trash", name: "Trash", systemImage: "trash.fill",
                            roots: [path(".Trash")],
                            sizeBytes: 0, fileCount: 0, selected: true),
            CleanupCategory(id: "xcode", name: "Xcode Junk", systemImage: "hammer.fill",
                            roots: [path("Library/Developer/Xcode/DerivedData"),
                                    path("Library/Developer/Xcode/Archives"),
                                    path("Library/Developer/Xcode/iOS DeviceSupport"),
                                    path("Library/Developer/CoreSimulator/Caches")],
                            sizeBytes: 0, fileCount: 0, selected: true),
        ]
    }

    public var totalSelectedBytes: Int64 {
        categories.filter(\.selected).reduce(0) { $0 + $1.sizeBytes }
    }

    public func toggle(_ id: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].selected.toggle()
    }

    /// Measures every category's size in the background.
    public func scan() {
        guard !isScanning else { return }
        isScanning = true
        let roots = categories.map { ($0.id, $0.roots) }

        queue.async { [weak self] in
            var measured: [String: (Int64, Int)] = [:]
            for (id, urls) in roots { measured[id] = Self.measure(urls) }
            DispatchQueue.main.async {
                guard let self else { return }
                for index in self.categories.indices {
                    if let m = measured[self.categories[index].id] {
                        self.categories[index].sizeBytes = m.0
                        self.categories[index].fileCount = m.1
                    }
                }
                self.lastScan = Date()
                self.isScanning = false
            }
        }
    }

    /// Permanently deletes the contents of every selected category, then rescans.
    /// `completion` receives the estimated bytes freed (the pre-clean selected total).
    public func cleanSelected(completion: @escaping (Int64) -> Void) {
        let targets = categories.filter(\.selected)
        let estimate = targets.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let fm = FileManager.default

        queue.async { [weak self] in
            for category in targets {
                for root in category.roots {
                    guard let items = try? fm.contentsOfDirectory(
                        at: root, includingPropertiesForKeys: nil) else { continue }
                    for item in items {
                        try? fm.removeItem(at: item) // skip locked / in-use files
                    }
                }
            }
            DispatchQueue.main.async {
                completion(estimate)
                self?.scan()
            }
        }
    }

    /// Total allocated size and regular-file count under the given roots.
    private static func measure(_ roots: [URL]) -> (Int64, Int) {
        let fm = FileManager.default
        var total: Int64 = 0
        var count = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]

        for root in roots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { continue }
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [], errorHandler: { _, _ in true }) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? 0)
                count += 1
            }
        }
        return (total, count)
    }
}
