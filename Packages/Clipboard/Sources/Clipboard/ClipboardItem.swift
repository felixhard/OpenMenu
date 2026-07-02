import Foundation

/// A single entry in the clipboard history.
public struct ClipboardItem: Identifiable, Codable, Equatable {
    public enum Kind: String, Codable { case text, image, file }

    public let id: UUID
    public let kind: Kind
    public let text: String?          // text content, or a display name for files
    public let imageFileName: String? // PNG blob filename for image items
    public let filePaths: [String]?   // file paths for file items
    public let appName: String?
    public let bundleID: String?
    public let date: Date

    /// Identity used to de-duplicate repeated copies of the same content.
    var contentKey: String {
        switch kind {
        case .text:  return "t:" + (text ?? "")
        case .file:  return "f:" + (filePaths?.joined(separator: "|") ?? "")
        case .image: return "i:" + (imageFileName ?? id.uuidString)
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        if let text, text.lowercased().contains(q) { return true }
        if let appName, appName.lowercased().contains(q) { return true }
        if let filePaths, filePaths.contains(where: { $0.lowercased().contains(q) }) { return true }
        return false
    }
}
