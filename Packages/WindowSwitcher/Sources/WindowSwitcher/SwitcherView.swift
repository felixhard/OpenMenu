import SwiftUI
import OpenMenuCore

/// Shared geometry for the switcher, so the controller can size the panel to fit
/// the content deterministically (no reliance on async SwiftUI sizing).
enum SwitcherLayout {
    static let width: CGFloat = 460
    static let rowHeight: CGFloat = 66
    static let rowSpacing: CGFloat = 8
    static let maxListHeight: CGFloat = 560
    static let padding: CGFloat = 14
    static let radius: CGFloat = 14

    static func listHeight(windowCount: Int) -> CGFloat {
        let total = CGFloat(windowCount) * rowHeight + CGFloat(max(0, windowCount - 1)) * rowSpacing
        return min(total, maxListHeight)
    }

    static func panelSize(windowCount: Int) -> CGSize {
        CGSize(width: width + padding * 2,
               height: listHeight(windowCount: windowCount) + padding * 2)
    }
}

/// The Cmd-Tab switcher: a centered vertical list of app-icon rows
/// (title + window subtitle), with a blue-highlighted selection.
struct SwitcherView: View {
    @ObservedObject var model: WindowSwitcherController

    var body: some View {
        list
            .padding(SwitcherLayout.padding)
            .frame(width: SwitcherLayout.width)
            .environment(\.colorScheme, .dark)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SwitcherLayout.rowSpacing) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                        row(window, selected: index == model.selectedIndex)
                            .id(index)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .frame(height: SwitcherLayout.listHeight(windowCount: model.windows.count))
            .onChange(of: model.selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func row(_ window: WindowInfo, selected: Bool) -> some View {
        HStack(spacing: 12) {
            icon(window)
            VStack(alignment: .leading, spacing: 2) {
                Text(window.appName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if model.showsWindowTitles && !window.title.isEmpty {
                    Text(window.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: SwitcherLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(selected: selected))
    }

    @ViewBuilder
    private func icon(_ window: WindowInfo) -> some View {
        if let icon = window.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .opacity(window.isMinimized ? 0.55 : 1)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: "macwindow").foregroundStyle(.white.opacity(0.6)))
        }
    }

    private func rowBackground(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: SwitcherLayout.radius, style: .continuous)
        return ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(selected ? LiquidGlass.accent.opacity(0.38)
                                : LiquidGlass.cardFill)
            // Uniform hairline edge on every card.
            shape.strokeBorder(LiquidGlass.borderColor, lineWidth: 1.5)
            // Copper accent on top for the current selection.
            if selected {
                shape.strokeBorder(LiquidGlass.accentBright.opacity(0.9), lineWidth: 1.5)
            }
        }
        // No shadow: keeps each card standalone with no bleed onto neighbours.
    }
}
