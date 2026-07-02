import AppKit
import QuickLookThumbnailing

/// Generates and caches thumbnails for clipboard items via QuickLook — real image
/// previews for image files and image copies, sensible previews for PDFs, etc.
final class ClipboardThumbnails {
    static let shared = ClipboardThumbnails()
    private let cache = NSCache<NSString, NSImage>()

    private init() {}

    func thumbnail(url: URL, maxPixel: CGFloat) async -> NSImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: maxPixel, height: maxPixel),
            scale: 1,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request) else { return nil }

        cache.setObject(representation.nsImage, forKey: key)
        return representation.nsImage
    }
}
