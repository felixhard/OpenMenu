import AppKit
import Foundation

/// Holds the clipboard history, persists it to Application Support (text/files as
/// JSON, images as PNG blobs), and provides search + pasteboard helpers.
public final class ClipboardStore: ObservableObject {
    @Published public private(set) var items: [ClipboardItem] = []

    /// Cap on the number of stored items; lowering it trims immediately.
    public var maxItems = 200 { didSet { trimToLimit() } }

    /// Items older than this are pruned, to keep the on-disk cache bounded.
    /// `nil` keeps items forever.
    public var retention: TimeInterval? = 12 * 60 * 60 { didSet { pruneExpired() } }

    private let fm = FileManager.default
    private let dir: URL
    private let blobsDir: URL
    private let indexURL: URL
    private var pruneTimer: Timer?

    public init() {
        let base = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("OpenMenu", isDirectory: true)
        dir = base
        blobsDir = base.appendingPathComponent("ClipboardImages", isDirectory: true)
        indexURL = base.appendingPathComponent("clipboard.json")
        try? fm.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        load()
        pruneExpired()
        startPruneTimer()
    }

    // MARK: - Retention

    /// Drops items (and their image blobs) older than the retention window.
    private func pruneExpired() {
        guard let retention else { return }
        let cutoff = Date().addingTimeInterval(-retention)
        let expired = items.filter { $0.date < cutoff }
        guard !expired.isEmpty else { return }
        expired.forEach(deleteBlob)
        items.removeAll { $0.date < cutoff }
        save()
    }

    private func startPruneTimer() {
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.pruneExpired()
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    // MARK: - Capture

    func addText(_ text: String, app: NSRunningApplication?) {
        insert(ClipboardItem(id: UUID(), kind: .text, text: text, imageFileName: nil,
                             filePaths: nil, appName: app?.localizedName,
                             bundleID: app?.bundleIdentifier, date: Date()))
    }

    func addFiles(_ paths: [String], app: NSRunningApplication?) {
        let name = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        insert(ClipboardItem(id: UUID(), kind: .file, text: name, imageFileName: nil,
                             filePaths: paths, appName: app?.localizedName,
                             bundleID: app?.bundleIdentifier, date: Date()))
    }

    func addImage(_ pngData: Data, app: NSRunningApplication?) {
        let fileName = UUID().uuidString + ".png"
        try? pngData.write(to: blobsDir.appendingPathComponent(fileName))
        insert(ClipboardItem(id: UUID(), kind: .image, text: nil, imageFileName: fileName,
                             filePaths: nil, appName: app?.localizedName,
                             bundleID: app?.bundleIdentifier, date: Date()))
    }

    private func insert(_ item: ClipboardItem) {
        items.removeAll { existing in
            guard existing.contentKey == item.contentKey else { return false }
            deleteBlob(existing)
            return true
        }
        items.insert(item, at: 0)
        trimToLimit(save: false)
        save()
    }

    /// Drops the oldest items (and their blobs) beyond `maxItems`.
    private func trimToLimit(save shouldSave: Bool = true) {
        guard items.count > maxItems else { return }
        for removed in items[maxItems...] { deleteBlob(removed) }
        items = Array(items.prefix(maxItems))
        if shouldSave { save() }
    }

    /// Moves an existing item to the top (used when it's pasted again).
    func promote(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let moved = items.remove(at: index)
        items.insert(moved, at: 0)
        save()
    }

    public func clear() {
        items.forEach(deleteBlob)
        items = []
        save()
    }

    func search(_ query: String) -> [ClipboardItem] {
        query.isEmpty ? items : items.filter { $0.matches(query) }
    }

    // MARK: - Pasteboard

    func writeToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            if let text = item.text { pb.setString(text, forType: .string) }
        case .file:
            if let paths = item.filePaths {
                pb.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
            }
        case .image:
            if let image = image(for: item) { pb.writeObjects([image]) }
        }
    }

    // MARK: - Display helpers

    func image(for item: ClipboardItem) -> NSImage? {
        guard let url = imageBlobURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// On-disk URL of an image item's PNG blob, for thumbnail generation.
    func imageBlobURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return blobsDir.appendingPathComponent(name)
    }

    // MARK: - Persistence

    private func deleteBlob(_ item: ClipboardItem) {
        guard let name = item.imageFileName else { return }
        try? fm.removeItem(at: blobsDir.appendingPathComponent(name))
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded.filter { item in
            guard let name = item.imageFileName else { return true }
            return fm.fileExists(atPath: blobsDir.appendingPathComponent(name).path)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL)
    }
}
