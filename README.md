# OpenMenu

An open-source, native macOS menu bar utility: window switcher, clipboard
history, system monitoring, window snapping, and small quality-of-life tools —
in one lightweight app. Free and MIT-licensed, inspired by the feature set of
apps like [OneMenu](https://coffeebreak.software/one-menu/).

> **Status:** pre-release, under active development.
> See [`PLAN.md`](PLAN.md) for the roadmap and architecture notes.

## Features

- **Menu bar panel** — live CPU / memory / disk dials, feature toggles, and a
  brightness slider in a warm glass drop-down
- **Window Switcher** — ⌘ Tab (or ⌥ Tab) across *all* windows, including
  minimized and off-Space ones
- **Clipboard History** — ⌘ ⇧ V searchable history for text, images, and files;
  honors password-manager concealed types, so secrets are never recorded
- **Window Manager** — drag a window to a screen edge or corner to snap it to
  halves or quadrants, with configurable padding between tiles
- **System Monitor** — per-process CPU, memory, and network with an app-grouped
  process list; disk usage with a built-in cache/junk cleaner
- **Keyboard Cleaning** — block keyboard input while you wipe the keys
- **Prevent Sleep** — one toggle to keep the Mac awake

Preferences (⌘ ,) cover launch-at-login, tile padding, switcher shortcut,
clipboard retention, and more.

## Requirements

- macOS 15 (Sequoia) or later
- Distributed outside the Mac App Store (the features need Accessibility and
  CGEvent taps, which the App Sandbox forbids)

## Building

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate
the Xcode project from `project.yml`.

```sh
brew install xcodegen        # if not already installed
xcodegen generate            # creates OpenMenu.xcodeproj
open OpenMenu.xcodeproj      # then build & run in Xcode

# or from the command line:
xcodebuild -project OpenMenu.xcodeproj -scheme OpenMenu -configuration Debug build
```

On first launch you'll be asked to grant **Accessibility** (required for the
window switcher and window manager).

## Project layout

```
App/                  app shell: status item, menu panel, preferences, monitor popup
Packages/
  OpenMenuCore/       shared: permissions, glass styling, display utils
  WindowSwitcher/     ⌘ Tab switcher (event tap, enumeration, panel)
  WindowManager/      drag-to-snap tiling
  Clipboard/          history capture, store, panel
  SystemMonitor/      CPU / memory / disk / network sampling, disk cleaner
project.yml           XcodeGen spec
```

## License

[MIT](LICENSE)
