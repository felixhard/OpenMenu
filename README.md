# OpenMenu

An open-source, native macOS menu bar utility: window switcher, clipboard
history, system monitoring, window snapping, and small quality-of-life tools -
in one lightweight app. Free and MIT-licensed, inspired by the feature set of
apps like [OneMenu](https://coffeebreak.software/one-menu/).

OpenMenu is in pre-release development. Build it from source to try it.

## Features

- **Menu bar panel** - live CPU / memory / disk dials and feature toggles in a
  glass drop-down
- **Window Switcher** - ⌘ Tab (or ⌥ Tab) across *all* windows, including
  minimized and off-Space ones
- **Clipboard History** - searchable history for text, images, and files (⌘ ⇧ V).
  Skips items marked as concealed by the source app.
- **Window Manager** - drag a window to a screen edge or corner to snap it to
  halves or quadrants, with configurable padding between tiles
- **System Monitor** - per-process CPU, memory, and network with an app-grouped
  process list; disk usage with a built-in cache/junk cleaner
- **Keyboard Cleaning** - block keyboard input while you wipe the keys
- **Prevent Sleep** - one toggle to keep the Mac awake

Settings (⌘ ,) cover launch-at-login, tile padding, switcher shortcut,
clipboard retention, and more.

## Build from source

OpenMenu runs on macOS 15 (Sequoia) or later. To build it, install Xcode 26 and
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The commands below use
[Homebrew](https://brew.sh/) to install XcodeGen.

```sh
brew install xcodegen
git clone https://github.com/felixhard/OpenMenu.git
cd OpenMenu
xcodegen generate
xcodebuild -project OpenMenu.xcodeproj -scheme OpenMenu -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/OpenMenu.app
```

You can also open `OpenMenu.xcodeproj` and run the OpenMenu scheme in Xcode.
Local builds use ad-hoc signing, which works without an Apple Developer account.
macOS may ask you to grant Accessibility again after a rebuild. See the
[signing config](Config/Signing.xcconfig) to use your own signing identity.

OpenMenu appears in the menu bar. Grant **Accessibility** when prompted to use
the window switcher and window manager.

## Contributing

See the [contribution guide](CONTRIBUTING.md) for local tests and pull requests,
and the [roadmap](PLAN.md) for project direction. Use the
[issue tracker](https://github.com/felixhard/OpenMenu/issues) for bugs and ideas.
See the [security policy](SECURITY.md) for private vulnerability reporting.

## Project layout

```
App/                  app shell: status item, menu panel, settings, monitor popup
Packages/
  OpenMenuCore/       shared: permissions, glass styling, display utils
  WindowSwitcher/     ⌘ Tab switcher (event tap, enumeration, panel)
  WindowManager/      drag-to-snap tiling
  Clipboard/          history capture, store, panel
  SystemMonitor/      CPU / memory / disk / network sampling, disk cleaner
Config/               signing defaults
project.yml           XcodeGen spec
```

## License

[MIT](LICENSE)
