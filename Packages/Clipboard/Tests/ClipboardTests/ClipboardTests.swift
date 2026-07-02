import Testing
import Foundation
import AppKit
@testable import Clipboard

@Test func textItemMatchesQuery() {
    let item = ClipboardItem(id: UUID(), kind: .text, text: "Hello World",
                             imageFileName: nil, filePaths: nil,
                             appName: "Safari", bundleID: nil, date: Date())
    #expect(item.matches("hello"))
    #expect(item.matches("safari"))
    #expect(!item.matches("zzz"))
}

@Test func contentKeyDistinguishesKinds() {
    let text = ClipboardItem(id: UUID(), kind: .text, text: "a", imageFileName: nil,
                             filePaths: nil, appName: nil, bundleID: nil, date: Date())
    let file = ClipboardItem(id: UUID(), kind: .file, text: "a", imageFileName: nil,
                             filePaths: ["/tmp/a"], appName: nil, bundleID: nil, date: Date())
    #expect(text.contentKey != file.contentKey)
}

@Test func concealedPasteboardContentIsSensitive() {
    let types: [NSPasteboard.PasteboardType] = [
        .string,
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
    ]
    #expect(ClipboardMonitor.isSensitive(types: types))
}

@Test func transientPasteboardContentIsSensitive() {
    let types = [NSPasteboard.PasteboardType("org.nspasteboard.TransientType")]
    #expect(ClipboardMonitor.isSensitive(types: types))
}

@Test func ordinaryPasteboardContentIsNotSensitive() {
    #expect(!ClipboardMonitor.isSensitive(types: [.string, .rtf, .png]))
    #expect(!ClipboardMonitor.isSensitive(types: nil))
}
