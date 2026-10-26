# MacClean

[![CI](https://github.com/OWNER/MacClean/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/MacClean/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A free, open-source, native macOS uninstaller. MacClean removes applications
together with their leftover files — preferences, caches, application
support, containers, logs, and more — instead of leaving them to clutter your
disk. It ships as a single Universal binary that runs natively on both Intel
and Apple Silicon Macs.

- 100% offline — no telemetry, no network calls
- Trash-first deletion — everything is recoverable by default
- Full transparency — review and toggle every file before anything is deleted

## Features

- **App discovery** — searchable list of installed apps with name, version,
  size, and last-modified date. Apple system apps are marked and protected.
- **Leftover scanning** — finds files tied to the selected app across the
  standard `~/Library` and `/Library` locations, plus LaunchAgents/Daemons.
- **Review before deletion** — per-item selection with live recoverable-space
  totals; caches and logs are pre-selected, application support is not.
- **Trash-first uninstall** — the app bundle and selected leftovers move to
  the Trash; an optional secure-delete mode erases permanently with extra
  confirmation.
- **Privileged helper** — root-owned leftovers in system-wide locations are
  removed via a signed helper; no terminal, no `sudo`.
- **Undo log** — every deletion is recorded to a JSON log in
  `~/Library/Logs/MacClean/`.
- **Homebrew aware** — detects cask/formula installs and recommends the
  `brew uninstall` flow.

## Safety

MacClean is built to be trusted with your files:

- Deletion never bypasses the Trash unless you explicitly enable secure delete.
- Hard-coded exclusion rules refuse to touch `/System`, `/usr`, `/bin`,
  `/sbin`, `/private`, or MacClean itself.
- All deletion paths are covered by unit tests on the safety-rules module.
- The core logic is a UI-free framework (`MacCleanCore`) with full unit tests
  and CI on both architectures.

## Requirements

- macOS 13 Ventura or later
- Intel (x86_64) or Apple Silicon (arm64)

## Building from source

The Xcode project is generated from `project.yml` with
[xcodegen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open MacClean.xcodeproj
```

Build & test from the command line:

```sh
xcodebuild -project MacClean.xcodeproj -scheme MacClean -configuration Debug build
xcodebuild -project MacClean.xcodeproj -scheme MacClean test
```

Every build produces a universal binary (x86_64 + arm64) — verify with:

```sh
lipo -info "$(xcodebuild -project MacClean.xcodeproj -scheme MacClean -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_PATH/{print $3}')/MacClean.app/Contents/MacOS/MacClean"
```

### App icon

The icon is drawn from scratch with CoreGraphics — no binary asset in the repo.
Regenerate the whole set (all ten macOS sizes plus `Contents.json`) with:

```sh
swift scripts/make-icon.swift --iconset Resources/Assets.xcassets/AppIcon.appiconset
```

Pass a file path instead of `--iconset` to write a single 1024px master PNG.
Every size is rendered natively from the vector artwork, so small icons stay
crisp rather than being downscaled.

## Project layout

- `Sources/MacCleanApp` — SwiftUI application target
- `Sources/MacCleanCore` — core logic framework (scanner, matcher, safety
  rules, deleter) — UI-free and fully unit-tested
- `Sources/MacCleanHelper` — privileged helper (root) for deleting
  system-wide leftovers
- `Tests/MacCleanCoreTests` — unit tests for the core framework

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
ground rules (especially around deletion safety), and the PR process.

## License

Released under the [MIT License](LICENSE).