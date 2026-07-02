import SwiftUI
import WindowManager
import WindowSwitcher
import Clipboard

/// The Preferences window: native grouped-form tabs (the glass aesthetic stays
/// exclusive to the menu bar panel and switcher).
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            WindowManagerSettingsView()
                .tabItem { Label("Window Manager", systemImage: "rectangle.split.2x2") }
            SwitcherSettingsView()
                .tabItem { Label("Switcher", systemImage: "square.on.square") }
            ClipboardSettingsView()
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            Section {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                Text("OpenMenu — an open-source menu bar utility.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Window Manager

private struct WindowManagerSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Snap windows dragged to screen edges and corners",
                       isOn: $settings.windowManager)
            }
            Section {
                paddingSlider("Padding between tiles", value: $settings.tileInnerGap)
                TilePreview(innerGap: settings.tileInnerGap)
            }
            Section {
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Snap trigger area") {
                            Slider(value: $settings.snapTriggerScale, in: 0.5...2) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("Small")
                            } maximumValueLabel: {
                                Text("Large")
                            }
                            .controlSize(.small)
                            .frame(width: 240)
                        }
                        Text("How close to a corner or edge you must drag before a tile is offered.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func paddingSlider(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: 0...30, step: 1)
                    .controlSize(.small)
                    .frame(width: 200)
                Text("\(Int(value.wrappedValue)) pt")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

/// Miniature 2×2 screen mock that redraws as the padding slider moves. Uses the
/// exact `SnapGeometry.applyGap` math (scaled down) so the preview is truthful.
private struct TilePreview: View {
    let innerGap: Double

    private static let quadrants = [
        CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
        CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
        CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
        CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
    ]

    var body: some View {
        HStack {
            Spacer()
            screen
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var screen: some View {
        // Preview at ~1/6.3 of a 14" MacBook Pro screen (1512×982 pt).
        let size = CGSize(width: 240, height: 156)
        let scale = size.width / 1512
        let container = CGRect(origin: .zero, size: size)

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)

            ForEach(Array(Self.quadrants.enumerated()), id: \.offset) { _, unit in
                let base = CGRect(x: unit.minX * size.width, y: unit.minY * size.height,
                                  width: unit.width * size.width, height: unit.height * size.height)
                let frame = SnapGeometry.applyGap(to: base, in: container,
                                                  edge: 0,
                                                  inner: innerGap * scale)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1)
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.12), value: innerGap)
    }
}

// MARK: - Switcher

private struct SwitcherSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Shortcut", selection: $settings.switcherModifier) {
                    Text("⌘ Tab").tag(WindowSwitcherController.HotKeyModifier.command)
                    Text("⌥ Tab").tag(WindowSwitcherController.HotKeyModifier.option)
                }
                .pickerStyle(.segmented)
                Text(shortcutCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show window titles", isOn: $settings.switcherShowsTitles)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutCaption: String {
        switch settings.switcherModifier {
        case .command:
            return "⌘ Tab replaces the system app switcher. Hold ⌘ and tap Tab to cycle "
                 + "(⇧ goes backwards); release ⌘ to switch, Esc to cancel."
        case .option:
            return "⌥ Tab leaves the system ⌘ Tab switcher untouched. Hold ⌥ and tap Tab "
                 + "to cycle (⇧ goes backwards); release ⌥ to switch, Esc to cancel."
        }
    }
}

// MARK: - Clipboard

private struct ClipboardSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingClearConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("History size", selection: $settings.clipboardMaxItems) {
                    ForEach([50, 200, 500, 1000], id: \.self) { count in
                        Text("\(count) items").tag(count)
                    }
                }
                Picker("Keep items for", selection: $settings.clipboardRetentionHours) {
                    Text("1 hour").tag(1.0)
                    Text("12 hours").tag(12.0)
                    Text("24 hours").tag(24.0)
                    Text("7 days").tag(24.0 * 7)
                    Text("Forever").tag(0.0)
                }
            }
            Section {
                LabeledContent("Shortcut", value: "⌘ ⇧ V")
                Button("Clear History…", role: .destructive) {
                    showingClearConfirmation = true
                }
                .confirmationDialog("Clear all clipboard history?",
                                    isPresented: $showingClearConfirmation) {
                    Button("Clear History", role: .destructive) {
                        ClipboardController.shared.store.clear()
                    }
                } message: {
                    Text("This removes every stored item, including images. It can't be undone.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }
}
