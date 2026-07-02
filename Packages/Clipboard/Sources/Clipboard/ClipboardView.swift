import SwiftUI
import AppKit
import OpenMenuCore

/// Searchable clipboard history panel. Text entries render as plain text; image
/// entries render a large preview of the actual image. Click (or Return on the
/// top match) to paste.
struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    var onPaste: (ClipboardItem) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// Max preview height for image entries — a starting point we can tune.
    private let maxImageHeight: CGFloat = 180

    private var results: [ClipboardItem] { store.search(query) }

    var body: some View {
        VStack(spacing: 8) {
            searchField
            list
        }
        .padding(14)
        .frame(width: 460)
        .environment(\.colorScheme, .dark)
        .onExitCommand(perform: onClose)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            TextField("Search clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit { if let first = results.first { onPaste(first) } }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(cardBackground)
        .liquidGlassBorder(cornerRadius: 12, lineWidth: 1.5)
        .onAppear { searchFocused = true }
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                if results.isEmpty {
                    Text(query.isEmpty ? "No clipboard history yet" : "No matches")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(results) { item in
                        Button { onPaste(item) } label: { row(item) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .frame(height: 460)
    }

    @ViewBuilder
    private func row(_ item: ClipboardItem) -> some View {
        if isImage(item) { imageRow(item) } else { textRow(item) }
    }

    private func textRow(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(preview(item))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .truncationMode(.tail)
            Text(subtitle(item))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .liquidGlassBorder(cornerRadius: 12, lineWidth: 1)
    }

    private func imageRow(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ClipboardImagePreview(item: item, store: store, maxHeight: maxImageHeight)
            Text(subtitle(item))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .liquidGlassBorder(cornerRadius: 12, lineWidth: 1)
    }

    private var cardBackground: some View {
        cardShape.fill(.ultraThinMaterial).overlay(cardShape.fill(LiquidGlass.cardFill))
    }

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private func isImage(_ item: ClipboardItem) -> Bool {
        if item.kind == .image { return true }
        if item.kind == .file, let path = item.filePaths?.first {
            let ext = (path as NSString).pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"].contains(ext)
        }
        return false
    }

    private func preview(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .text:  return item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .file:  return item.text ?? "Files"
        case .image: return "Image"
        }
    }

    private func subtitle(_ item: ClipboardItem) -> String {
        let app = item.appName ?? "Unknown"
        return "\(app) · \(Self.relative.localizedString(for: item.date, relativeTo: Date()))"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// Large preview of an image entry, generated via QuickLook and aspect-fit within
/// a max height so the whole image is visible.
private struct ClipboardImagePreview: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let maxHeight: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 100)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: item.id) { await load() }
    }

    private func load() async {
        let url: URL? = item.kind == .image
            ? store.imageBlobURL(for: item)
            : item.filePaths?.first.map { URL(fileURLWithPath: $0) }
        guard let url else { return }
        image = await ClipboardThumbnails.shared.thumbnail(url: url, maxPixel: 960)
    }
}
