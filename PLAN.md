# OpenMenu — Planning & Research

An open-source, native macOS menu bar app that replicates the feature set of
[OneMenu](https://coffeebreak.software/one-menu/) by Coffee Break Software.

> Status: **Research + planning.** No code yet. Architecture and roadmap below.

---

## 1. What we're cloning

OneMenu is a paid ($2/mo) all-in-one menu bar utility with ~10k daily users. It
bundles several tools that each have a strong standalone open-source equivalent.
Our goal is to build a single cohesive app that covers the same surface area,
fully native (Swift), free, and open-source.

### Feature set (from OneMenu)

| Feature | What it does | OneMenu tier |
|---|---|---|
| **Window Manager** | Snap windows to user-defined zones; custom layouts; per-display responsive layouts; keybinds with cycling; vertical-display support | Free (12 zones) / Pro (unlimited + auto-layout) |
| **Window Switcher** (Alt/Cmd-Tab) | Switch across all windows & tabs with search; thumbnails | Pro |
| **Clipboard History** | Searchable history (by content, file name, app, window title); single-key paste; per-app capture control; "Glass" UI; iCloud-only storage | Free (limited) / Pro (unlimited) |
| **System Monitoring** | CPU / RAM / storage / network; process tree with child aggregation; historical heavy-usage detection; menu bar widgets | Pro |
| **Disk Clean** | One-click cleanup; finds large files, app caches, junk; adaptive cache scanning | Pro |
| **Monitor Brightness** | Brightness slider for external displays | Pro |
| **Keyboard Cleaning** | Disable keyboard input for cleaning without powering off | Free |
| **iCloud Sync** | Sync settings/data across devices | Free |

---

## 2. Open-source reference implementations

Each pillar has a mature OSS project we can study (and learn the hard-won macOS
API lessons from). All are Swift/native.

| Our feature | Reference project | Notes |
|---|---|---|
| Window Manager | [Rectangle](https://github.com/rxhanson/Rectangle), [Loop](https://github.com/MrKai77/Loop), [Swindler](https://github.com/tmandry/Swindler) | Rectangle = de-facto snapping standard; Loop = radial zone UI; Swindler = typed cached AX model |
| Window Switcher | [AltTab](https://github.com/lwouis/alt-tab-macos) | CGEvent tap + non-activating NSPanel + ScreenCaptureKit thumbnails |
| Clipboard | [Maccy](https://github.com/p0deje/Maccy) | NSPasteboard `changeCount` polling (~0.5s); the canonical approach |
| System Monitor | [Stats](https://github.com/exelban/stats) | Mach/IOKit reads for CPU/mem/GPU/temp/network in the menu bar |
| Disk Clean | (no great OSS analog) | [Pearcleaner](https://github.com/alienator88/Pearcleaner) for app-uninstall patterns; otherwise build carefully |

---

## 3. Technical approach per feature

### 3.1 Window Manager
- **Move/resize other apps' windows** via the **Accessibility API** (`AXUIElement`):
  read/set `kAXPositionAttribute` + `kAXSizeAttribute`, enumerate via
  `kAXWindowsAttribute`. Requires **Accessibility permission** (`AXIsProcessTrustedWithOptions`).
- **Screen geometry**: `NSScreen.visibleFrame` (excludes menu bar/Dock), handle
  multi-display coordinate flips, per-display layouts, vertical displays.
- **Snap-on-drag**: global mouse monitor (`NSEvent.addGlobalMonitorForEvents` or a
  CGEvent tap) detects drag to edges → draws a translucent "footprint" overlay
  (`NSPanel`) → applies frame on mouse-up.
- **Zone editor**: SwiftUI canvas defining zones as fractional rects of the screen;
  presets (halves, thirds, quarters) + custom grid.
- **Hotkeys with cycling**: global hotkeys mapping one key to a list of zones that
  cycle on repeat press.
- *Gotcha:* AX reads/writes are synchronous IPC to the target app and can stall;
  Swindler's trick is a cached model. Some apps (Electron, Java) misreport frames.

### 3.2 Window Switcher (Cmd/Alt-Tab)
- **Intercept the hotkey** with a session-level **CGEvent tap** so the combo never
  reaches other apps; suppress the system switcher.
- **Enumerate windows**: `CGWindowListCopyWindowInfo` for the list + `AXUIElement`
  to raise/focus and to read window titles; map windows → apps.
- **Thumbnails**: **ScreenCaptureKit** (`SCShareableContent`) on macOS 14+;
  graceful fallback to **app icons** if Screen Recording permission is denied.
- **Overlay**: `NSPanel` with `.nonactivatingPanel` so it never steals focus;
  releasing the modifier activates the selected window. Tab/Shift-Tab/arrows + a
  search field to filter.
- *Permissions:* Accessibility (required), Screen Recording (optional, for thumbs).

### 3.3 Clipboard History
- **Capture**: poll `NSPasteboard.general.changeCount` on a timer (~0.5s) — macOS
  has **no clipboard-change notification**. On change, snapshot all types
  (string, RTF, PNG/TIFF, file URLs).
- **Metadata**: source app via `NSWorkspace.frontmostApplication`; window title via
  Accessibility; timestamp; type.
- **Storage**: SwiftData (or Core Data / GRDB) local DB; optional encryption at rest.
- **Paste**: write item back to pasteboard, restore prior frontmost app, synthesize
  Cmd-V via CGEvent. Offer "paste as plain text".
- **Privacy**: honor `org.nspasteboard.ConcealedType` / transient markers (password
  managers); per-app allow/deny list; configurable retention.
- **iCloud sync** (optional, later): `NSPersistentCloudKitContainer` — needs the
  iCloud container entitlement + a paid Developer ID. Non-trivial; defer.

### 3.4 System Monitoring
- **CPU**: `host_processor_info` / `host_statistics` (Mach). Per-process via `libproc`.
- **Memory**: `vm_statistics64` / `host_statistics64`; memory pressure.
- **Disk**: `statfs` / `URLResourceValues` for capacity; IOKit for throughput.
- **Network (system)**: `getifaddrs` / `sysctl` per interface.
- **Process tree**: `sysctl(KERN_PROC)` for ppid → build tree, aggregate child usage
  (matches OneMenu's "child processes grouped under parent").
- **Menu bar widgets**: custom `NSStatusItem` with live-drawn charts; SwiftUI dashboard.
- *Hard parts:* **per-process network** has no clean public API (OneMenu likely parses
  `nettop` or uses private interfaces); **temperature/GPU** needs SMC via IOKit
  (private keys) or `powermetrics` (root). Flag these as stretch.

### 3.5 Disk Clean
- **Scan targets**: `~/Library/Caches`, `/Library/Caches`, app-specific caches,
  Xcode DerivedData, `node_modules`, logs, Trash, large files in `~/Downloads`.
- **Large-file finder**: deep `FileManager` enumeration sorted by size.
- **Safe deletion**: always `trashItem(at:)` (recoverable) with explicit confirmation
  and clear per-category breakdown — never `rm`. Curated allowlist of safe paths.
- *Permissions:* **Full Disk Access** for many locations.
- *Caution:* this is the riskiest feature for data loss; conservative defaults, dry-run
  preview, and reversibility are mandatory.

### 3.6 Smaller features
- **Monitor brightness**: DDC/CI over I2C for external displays (see
  [MonitorControl](https://github.com/MonitorControl/MonitorControl)); Apple displays
  via private `DisplayServices`.
- **Keyboard cleaning**: CGEvent tap that swallows all key events until dismissed
  (overlay reminds the user how to exit).

---

## 4. Tech stack & architecture

- **Language/UI**: Swift, **SwiftUI-first** with **AppKit** where SwiftUI can't reach
  (status item, non-activating panels, event taps, overlays).
- **Menu bar**: `MenuBarExtra` (SwiftUI, macOS 13+) for simple items; `NSStatusItem`
  for live-drawn system-monitor widgets.
- **Agent app**: `LSUIElement = true` (no Dock icon).
- **Launch at login**: `SMAppService` (macOS 13+).
- **Global hotkeys**: [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts)
  (recordable shortcuts UI + storage).
- **Auto-update**: [Sparkle](https://github.com/sparkle-project/Sparkle) (since we
  distribute outside the App Store).
- **Persistence**: SwiftData (clipboard/history), UserDefaults (settings).
- **Modular layout**: one Swift Package per feature behind protocols, assembled by a
  thin app shell — keeps features independently testable and toggleable.

### Proposed project structure
```
OpenMenu/
├── OpenMenu.xcodeproj (or Package.swift workspace)
├── App/                       # app shell, menu bar, settings, onboarding/permissions
├── Packages/
│   ├── OpenMenuCore/          # shared: AX helpers, permissions, hotkeys, display utils
│   ├── WindowManager/
│   ├── WindowSwitcher/
│   ├── Clipboard/
│   ├── SystemMonitor/
│   └── DiskClean/
└── PLAN.md
```

---

## 5. Permissions & distribution (important constraint)

These features need capabilities that the **App Sandbox forbids**:
- Controlling other apps' windows (`AXUIElement`) → **Accessibility**
- Global hotkey interception → **CGEvent tap** (sandbox-incompatible)
- Window thumbnails → **Screen Recording**
- Disk Clean → **Full Disk Access**

**Consequence:** OpenMenu must ship **non-sandboxed**, which means **not via the Mac
App Store**. Distribute as a **Developer ID-signed, notarized DMG** with **Sparkle**
auto-updates (the same model as Rectangle, AltTab, Stats). A clear first-run
**permissions onboarding** flow is essential.

---

## 6. Phased roadmap

> Decided build order: **Switcher first, Window Manager last.**

**Phase 0 — Scaffold** ✅ *(done)*
- XcodeGen project, agent app (`LSUIElement`), modular SPM packages, MIT license, Settings window.

**Phase 0.5 — Menu bar panel** ✅ *(done — built against a local design reference; `Design/` is gitignored since it holds third-party screenshots)*
- Custom `NSStatusItem` + borderless transparent `NSPanel` hosting SwiftUI "glass" cards.
- Live CPU/MEM/DISK ring gauges (real data via `SystemMonitor` package).
- Feature toggles (Window Manager, Clipboard History, Keyboard Cleaning, Prevent Sleep — persisted),
  External Monitor Brightness slider, detached Preferences/Quit card.
- `Prevent Sleep` is functional (ProcessInfo power assertion); brightness slider is UI-only for now
  (DDC/CI hardware control is a later task); the other toggles persist and will gate features as built.

**Phase 1 — Window Switcher (first)** *(backend done; visual layer to be restyled to match the design language)*
- ✅ CGEvent-tap hotkey, window enumeration, non-activating panel, ⌘-Tab cycling, AX activation.
- ⏳ Restyle `SwitcherView` to the glass aesthetic, ScreenCaptureKit thumbnails, search, AX titles.

**Phase 2 — Clipboard History**
- Polling capture, storage, searchable panel, paste/plain-text paste, per-app rules, retention.

**Phase 3 — System Monitoring**
- CPU/mem/disk/network reads, process tree, menu bar widgets, dashboard. (Temp/GPU/per-proc network = stretch.)

**Phase 4 — Disk Clean**
- Conservative scanners, size-sorted large files, trash-based deletion with preview/confirmation.

**Phase 5 — Window Manager (flagship, last)**
- AX move/resize, presets, custom zones editor, drag-to-snap footprint, hotkeys + cycling, multi-display.

**Phase 6 — Polish & extras**
- Monitor brightness, keyboard cleaning, optional iCloud sync, theming to match reference images.

---

## 7. Decisions
- **App name:** OpenMenu
- **Minimum macOS:** 15 (Sequoia) — latest-only; newest APIs, simplest code
- **Build order:** Window Switcher first → Window Manager last (see roadmap)
- **License:** MIT
- **iCloud sync:** deferred (local-only first)

### Still open
- Reference images for the **Switcher UI** (user gathering) before building its visual layer.
- Project generation: raw `.xcodeproj` vs XcodeGen/Tuist vs SPM-only (decide at scaffold).

---

## 8. Preferences window plan ✅ *(implemented)*

> Goal: turn the placeholder Settings window into a real Preferences window.
> Native macOS look (grouped `Form`, like System Settings) — the glass aesthetic
> stays exclusive to the menu bar panel and switcher, matching OneMenu.

### 8.1 Architecture

- **Keep the SwiftUI `Settings` scene** in `OpenMenuApp` with a `TabView`
  (`SettingsView.swift` already scaffolds this). Grouped forms per tab.
- **Inject the live `AppSettings`**: `SettingsView()` currently has no model.
  Pass `appDelegate.settings` via `.environmentObject` from `OpenMenuApp`
  (the `@NSApplicationDelegateAdaptor` property exposes it).
- **Opening the window**: `MenuPanelView.openPreferences()` uses the private
  `showSettingsWindow:` selector, which is unreliable on macOS 14+. Replace with
  the `openSettings` environment action (macOS 14+) via a tiny bridge view or by
  routing through `AppDelegate`. Verify it opens from the panel.
- **Persistence pattern**: extend `AppSettings` with new `@Published` values +
  `didSet` side effects pushing into the package singletons — same pattern as
  `preventSleep`/`clipboard` today. Packages expose setters instead of constants.

### 8.2 Tabs & settings

**General**
- Launch at login — `SMAppService.mainApp.register()/unregister()`.
- Version + GitHub link (absorbs the current placeholder content).

**Window Manager** *(the headline tab)*
- Enable drag-to-snap (mirrors the panel toggle — same `AppSettings` value).
- **Tile padding** — a single *Padding between tiles* slider, 0–30 pt (default
  8) → `SnapGeometry.innerGap`. Tiles sit flush against the screen edges
  (`edgePadding = 0`); OneMenu documents no gap setting at all, and macOS's
  native tiling exposes just one margins control, so one slider it is. The
  geometry (`applyGap(to:in:edge:inner:)`) still supports an edge inset should
  we ever want it back. `SnapZone.cocoaFrame` and `SnapOverlay` read the same
  values so preview == result.
- **Live mini-preview**: small 2×2 tile diagram in the pane that redraws as the
  sliders move — instant feedback without dragging a real window.
- Advanced (collapsed `DisclosureGroup`): snap trigger sensitivity — one slider
  scaling `SnapGeometry.cornerSize` (100) and `edgeSize` (28) proportionally.

**Switcher**
- Shortcut: ⌘Tab (replaces the system switcher) vs ⌥Tab — segmented picker.
  `HotKeyTap` already reports raw flags; `WindowSwitcherController` gets a
  configurable modifier instead of hard-coded ⌘.
- Show window titles (on/off) — gates `WindowTitles` lookups.

**Clipboard**
- History size: 50 / 200 / 500 / 1000 items → `ClipboardStore.maxItems`.
- Retention: 1 h / 12 h / 24 h / 7 d / forever → `ClipboardStore.retention`.
  Both are `let` constants today — become vars configured through
  `ClipboardController.shared`.

### 8.3 Implementation order

1. Plumb `AppSettings` into the Settings scene; fix window opening.
2. `AppSettings` keys: `launchAtLogin`, `tileInnerGap`, `tileEdgePadding`,
   `snapSensitivity`, `switcherModifier`, `clipboardMaxItems`,
   `clipboardRetentionHours` (+ defaults matching current behaviour).
3. Make `SnapGeometry`/`ClipboardStore`/switcher accept configuration; update
   `WindowManagerTests` for the two-value gap math.
4. Build the four tabs + tile-gap live preview.
5. Build, relaunch, verify: snap with changed padding, ⌥Tab switching,
   launch-at-login round-trip.

---

## Sources
- [OneMenu](https://coffeebreak.software/one-menu/) · [Docs](https://coffeebreak.software/one-menu/docs)
- [Rectangle](https://github.com/rxhanson/Rectangle) · [Loop](https://github.com/MrKai77/Loop) · [Swindler](https://github.com/tmandry/Swindler)
- [AltTab](https://github.com/lwouis/alt-tab-macos) · [Maccy](https://github.com/p0deje/Maccy) · [Stats](https://github.com/exelban/stats)
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) · [Sparkle](https://github.com/sparkle-project/Sparkle) · [MonitorControl](https://github.com/MonitorControl/MonitorControl)
