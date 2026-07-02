import SwiftUI
import AppKit
import SystemMonitor
import OpenMenuCore

/// The system-monitor detail popup opened by tapping a menu-bar gauge.
///
/// Four tabs (CPU / Memory / Network / Disk). CPU, Memory and Network show a live
/// history bar-graph, a process search field, and a grouped per-process list. Disk
/// shows a capacity ring plus a cache/log/trash cleanup scanner.
struct SystemMonitorView: View {
    @Binding var tab: MonitorTab
    @ObservedObject var stats: SystemStats
    @ObservedObject var processes: ProcessSampler
    @ObservedObject var cleaner: DiskCleaner

    @State private var search = ""
    @State private var expanded: Set<Int32> = []
    @State private var hoveredRow: Int32?
    @State private var confirmClean = false

    private enum Metric {
        static let width: CGFloat = 300
        static let cardRadius: CGFloat = 16
        static let hPad: CGFloat = 14
    }

    var body: some View {
        VStack(spacing: 8) {
            topCard

            if tab == .disk {
                scanCard
                    .background(GlassCard(cornerRadius: Metric.cardRadius))
                cleanupCard
                    .background(GlassCard(cornerRadius: Metric.cardRadius))
                Spacer(minLength: 0) // pin the (shorter) disk cards to the top
            } else {
                searchCard
                    .background(GlassCard(cornerRadius: Metric.cardRadius))
                processCard
            }
        }
        .padding(11)
        // Fill the host window's fixed size; the window — not the content — is
        // authoritative, so nothing measures-and-resizes in a layout feedback loop.
        .frame(width: Metric.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: tab) { _, newTab in
            confirmClean = false
            // Lazily scan the first time the user lands on the Disk tab.
            if newTab == .disk && cleaner.lastScan == nil { cleaner.scan() }
        }
        .onAppear {
            if tab == .disk && cleaner.lastScan == nil { cleaner.scan() }
        }
    }

    // MARK: Top card (tab bar + graph or disk summary)

    private var topCard: some View {
        VStack(spacing: 0) {
            tabBar
            topDetail
        }
        .background(GlassCard(cornerRadius: Metric.cardRadius))
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(MonitorTab.allCases) { t in
                let selected = t == tab
                Text(t.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(selected ? Color.accentBlue : Color.clear)
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) { tab = t }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
    }

    @ViewBuilder private var topDetail: some View {
        switch tab {
        case .cpu:
            MonitorGraph(samples: stats.cpuHistory, capacity: stats.historyLength,
                         axisLabel: MonitorFormat.percent)
                .padding(.horizontal, Metric.hPad)
                .padding(.bottom, 14)
                .padding(.top, 2)
        case .memory:
            MonitorGraph(samples: stats.memoryHistory, capacity: stats.historyLength,
                         axisLabel: MonitorFormat.axisBytes)
                .padding(.horizontal, Metric.hPad)
                .padding(.bottom, 14)
                .padding(.top, 2)
        case .network:
            MonitorGraph(samples: stats.networkHistory, capacity: stats.historyLength,
                         axisLabel: MonitorFormat.axisBytes)
                .padding(.horizontal, Metric.hPad)
                .padding(.bottom, 14)
                .padding(.top, 2)
        case .disk:
            diskSummary
        }
    }

    // MARK: Search + process list

    private var searchCard: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            TextField("Search process", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Metric.hPad)
        .padding(.vertical, 13)
    }

    private var processCard: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedRows) { row in
                    processRow(row)
                    if expanded.contains(row.id) {
                        ForEach(row.children) { child in
                            childRow(child)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        // Fill the remaining height of the fixed-size detail window. Safe because the
        // window size is authoritative (no `.preferredContentSize` measuring the
        // ScrollView), so there's no measure-and-resize loop to fall into.
        .frame(maxHeight: .infinity)
        .background(GlassCard(cornerRadius: Metric.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
    }

    private var displayedRows: [ProcessRow] {
        let rows = search.isEmpty
            ? processes.rows
            : processes.rows.filter { $0.name.localizedCaseInsensitiveContains(search) }
        switch tab {
        case .cpu:
            return rows.sorted { $0.cpu > $1.cpu }
        case .memory:
            return rows.sorted { $0.memoryBytes > $1.memoryBytes }
        case .network:
            return rows.sorted { $0.networkBytes > $1.networkBytes }
        case .disk:
            return []
        }
    }

    private func processRow(_ row: ProcessRow) -> some View {
        HStack(spacing: 10) {
            if row.childCount > 0 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .rotationEffect(.degrees(expanded.contains(row.id) ? 90 : 0))
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10, height: 1)
            }

            processIcon(row).frame(width: 22, height: 22)

            Text(row.name)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1)

            if row.childCount > 0 {
                Text("+ \(row.childCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.10)))
            }

            Spacer(minLength: 8)

            // On hover, an app row's value swaps for a force-quit button.
            if hoveredRow == row.id && !row.isSystemGroup {
                quitButton(row)
            } else {
                Text(valueText(for: row))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Metric.hPad)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { hoveredRow = row.id }
            else if hoveredRow == row.id { hoveredRow = nil }
        }
        .onTapGesture {
            guard row.childCount > 0 else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                if expanded.contains(row.id) { expanded.remove(row.id) }
                else { expanded.insert(row.id) }
            }
        }
    }

    private func quitButton(_ row: ProcessRow) -> some View {
        Button {
            processes.forceQuit(row)
            hoveredRow = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Quit")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.98, green: 0.45, blue: 0.45))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(red: 0.98, green: 0.32, blue: 0.32).opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help("Force quit \(row.name)")
    }

    private func childRow(_ child: ProcessRow) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 10 + 22 + 10, height: 1) // align under parent name
            Text(child.name)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(valueText(for: child))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
        }
        .padding(.horizontal, Metric.hPad)
        .padding(.vertical, 5)
    }

    @ViewBuilder private func processIcon(_ row: ProcessRow) -> some View {
        if row.isSystemGroup {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.10)))
        } else if let path = row.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22, height: 22)
        }
    }

    private func valueText(for row: ProcessRow) -> String {
        switch tab {
        case .cpu:     return MonitorFormat.percent(row.cpu)
        case .memory:  return MonitorFormat.memoryBytes(row.memoryBytes)
        case .network: return MonitorFormat.networkRate(row.networkBytes)
        case .disk:    return ""
        }
    }

    // MARK: Disk

    private var diskSummary: some View {
        HStack(spacing: 20) {
            diskRing
            VStack(alignment: .leading, spacing: 11) {
                diskStat("Total Capacity", stats.diskTotalBytes)
                diskStat("Used Space", stats.diskUsedBytes)
                diskStat("Free Space", stats.diskFreeBytes)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var diskRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.001, min(stats.disk, 1)))
                .stroke(Color.diskGreen, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: stats.disk)
            Text("\(Int((stats.disk * 100).rounded()))%")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 112, height: 112)
    }

    private func diskStat(_ title: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Text(MonitorFormat.memoryBytes(UInt64(max(0, bytes))))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var scanCard: some View {
        HStack(spacing: 9) {
            if cleaner.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Text("Scanning…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(lastScanText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            Button(action: { cleaner.scan() }) {
                Text(cleaner.lastScan == nil ? "Scan" : "Rescan")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentBlue.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .disabled(cleaner.isScanning)
        }
        .padding(.horizontal, Metric.hPad)
        .padding(.vertical, 11)
    }

    private var cleanupCard: some View {
        VStack(spacing: 0) {
            ForEach(cleaner.categories) { category in
                categoryRow(category)
                if category.id != cleaner.categories.last?.id {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, Metric.hPad)
                }
            }
            cleanButton
        }
        .padding(.vertical, 6)
    }

    private func categoryRow(_ category: CleanupCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                Text(cleaner.isScanning ? "Scanning…" : "\(category.fileCount) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            Text(sizeText(category.sizeBytes))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
            Image(systemName: category.selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(category.selected ? Color.accentBlue : Color.white.opacity(0.3))
        }
        .padding(.horizontal, Metric.hPad)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { cleaner.toggle(category.id) }
    }

    @ViewBuilder private var cleanButton: some View {
        if confirmClean {
            // Inline confirm — kept inside the panel so it doesn't steal key focus
            // (a popover/sheet would, and the panel auto-closes on focus loss).
            HStack(spacing: 8) {
                Button(action: { confirmClean = false }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                Button(action: { confirmClean = false; cleaner.cleanSelected { _ in } }) {
                    Text("Delete \(sizeText(cleaner.totalSelectedBytes))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color(red: 0.9, green: 0.27, blue: 0.27)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Metric.hPad)
            .padding(.top, 8)
            .padding(.bottom, 4)
        } else {
            Button(action: { confirmClean = true }) {
                Text(cleanButtonLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(cleanEnabled ? Color.accentBlue : Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(!cleanEnabled)
            .padding(.horizontal, Metric.hPad)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private var cleanEnabled: Bool { !cleaner.isScanning && cleaner.totalSelectedBytes > 0 }

    private var cleanButtonLabel: String {
        if cleaner.isScanning { return "Calculating…" }
        let total = cleaner.totalSelectedBytes
        return total > 0 ? "Clean Up \(sizeText(total)) permanently" : "Nothing to clean"
    }

    private var lastScanText: String {
        guard let date = cleaner.lastScan else { return "Last scan: never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last scan: " + formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sizeText(_ bytes: Int64) -> String {
        bytes <= 0 ? "—" : MonitorFormat.memoryBytes(UInt64(bytes))
    }
}

// MARK: - History bar graph

private struct MonitorGraph: View {
    let samples: [Double]
    let capacity: Int
    let axisLabel: (Double) -> String
    var height: CGFloat = 150

    /// Headroom above the top (100%) gridline so its label pill isn't clipped.
    private let topInset: CGFloat = 11

    var body: some View {
        // Scale so the tallest bar reaches 75% of the height, leaving headroom and
        // matching the reference design's axis labelling (peak / 0.75 at the top).
        let peak = samples.max() ?? 0
        let niceMax = max(peak / 0.75, 0.0001)

        Canvas { context, size in
            // Order matters: gridlines behind, then bars, then axis pills on top so
            // the labels stay readable even when bars fill the full width.
            drawGridLines(&context, size)
            drawBars(&context, size, niceMax: niceMax)
            drawAxisLabels(&context, size, niceMax: niceMax)
        }
        .frame(height: height)
    }

    /// Y position of a 0...1 axis fraction, measured within the usable area below
    /// the top headroom (bars sit on the bottom edge).
    private func yPosition(_ fraction: CGFloat, _ size: CGSize) -> CGFloat {
        topInset + (size.height - topInset) * (1 - fraction)
    }

    private func drawGridLines(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for f in [0.25, 0.5, 0.75, 1.0] {
            let y = yPosition(CGFloat(f), size)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.white.opacity(0.10)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func drawAxisLabels(_ ctx: inout GraphicsContext, _ size: CGSize, niceMax: Double) {
        let inset: CGFloat = 6
        for f in [0.25, 0.5, 0.75, 1.0] {
            let y = yPosition(CGFloat(f), size)
            let resolved = ctx.resolve(
                Text(axisLabel(niceMax * f))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            )
            let textSize = resolved.measure(in: size)
            let padH: CGFloat = 7, padV: CGFloat = 3
            let pillRect = CGRect(x: inset, y: y - textSize.height / 2 - padV,
                                  width: textSize.width + padH * 2,
                                  height: textSize.height + padV * 2)
            let pill = Path(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
            // Opaque-ish dark backing so the label reads over the graph bars.
            ctx.fill(pill, with: .color(Color(red: 0.16, green: 0.13, blue: 0.10).opacity(0.92)))
            ctx.stroke(pill, with: .color(.white.opacity(0.16)), lineWidth: 1)
            ctx.draw(resolved, at: CGPoint(x: inset + padH, y: y), anchor: .leading)
        }
    }

    private func drawBars(_ ctx: inout GraphicsContext, _ size: CGSize, niceMax: Double) {
        guard !samples.isEmpty else { return }
        let usableHeight = size.height - topInset
        let slotW = size.width / CGFloat(capacity)
        let barW = max(2, slotW * 0.55)
        let count = samples.count

        for k in 0..<count {
            let slotIndex = capacity - 1 - k
            guard slotIndex >= 0 else { break }
            let value = samples[count - 1 - k]
            let h = CGFloat(value / niceMax) * usableHeight
            guard h > 0.5 else { continue }
            let x = CGFloat(slotIndex) * slotW + (slotW - barW) / 2
            let rect = CGRect(x: x, y: size.height - h, width: barW, height: h)
            let bar = Path(roundedRect: rect, cornerRadius: barW / 2)
            ctx.fill(
                bar,
                with: .linearGradient(
                    Gradient(colors: [Color.graphBlue.opacity(0.95), Color.graphBlue]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )
        }
    }
}

// MARK: - Formatting

enum MonitorFormat {
    private static func number(_ value: Double, frac: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = frac
        f.maximumFractionDigits = frac
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.\(frac)f", value)
    }

    /// `fraction` is 0...1; rendered as a locale-aware percent with two decimals.
    static func percent(_ fraction: Double) -> String {
        number(fraction * 100, frac: 2) + " %"
    }

    static func memoryBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        let gb = 1_073_741_824.0, mb = 1_048_576.0, kb = 1_024.0
        if b >= gb { return number(b / gb, frac: 2) + " GB" }
        if b >= mb { return number(b / mb, frac: 1) + " MB" }
        if b >= kb { return number(b / kb, frac: 0) + " KB" }
        return "\(bytes) B"
    }

    static func axisBytes(_ bytes: Double) -> String {
        let gb = 1_073_741_824.0, mb = 1_048_576.0, kb = 1_024.0
        if bytes >= gb { return number(bytes / gb, frac: 2) + " GB" }
        if bytes >= mb { return number(bytes / mb, frac: 1) + " MB" }
        if bytes >= kb { return number(bytes / kb, frac: 1) + " KB" }
        return number(bytes, frac: 0) + " B"
    }

    /// Per-process throughput. Idle processes read "Zero KB" (matching the design);
    /// active ones show a localized rate like "24,5 KB/s".
    static func networkRate(_ bytesPerSec: UInt64) -> String {
        guard bytesPerSec > 0 else { return "Zero KB" }
        return axisBytes(Double(bytesPerSec)) + "/s"
    }
}

private extension Color {
    static let accentBlue = LiquidGlass.accent
    static let graphBlue = LiquidGlass.accent
    static let diskGreen = LiquidGlass.accent
}
