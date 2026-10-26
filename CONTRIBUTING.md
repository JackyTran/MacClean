# Contributing to MacClean

Thanks for your interest in contributing! This document covers everything you
need to get started.

## Code of conduct

Be respectful and constructive. We're all here to build a good uninstaller.

## Ways to contribute

- **Bug reports** — open an issue with your macOS version, chip architecture
  (Intel/Apple Silicon), steps to reproduce, and any relevant log output from
  `~/Library/Logs/MacClean/`.
- **Feature ideas** — open an issue describing the use case.
- **Pull requests** — bug fixes and well-scoped features are welcome.

## Getting set up

You'll need:

- macOS 13+
- Xcode 16+ with Swift 5.10+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```sh
git clone <repository-url>
cd MacClean
xcodegen generate
open MacClean.xcodeproj
```

Build and run the full test suite before submitting:

```sh
xcodebuild -project MacClean.xcodeproj -scheme MacClean -configuration Debug build
xcodebuild -project MacClean.xcodeproj -scheme MacClean test
```

CI (GitHub Actions) must pass on both architectures before a PR is merged.

## Ground rules

1. **Core logic goes in `MacCleanCore`.** The core framework must stay UI-free
   and fully unit-testable. If your change touches scanning, matching, safety
   rules, or deletion, it belongs in `Sources/MacCleanCore` with tests in
   `Tests/MacCleanCoreTests`.
2. **Safety first.** MacClean deletes files from users' machines. Changes to
   deletion behavior must:
   - preserve the Trash-first default,
   - keep the built-in exclusion rules intact (nothing under `/System`,
     `/usr`, `/bin`, `/sbin`, `/private`),
   - add or update unit tests for the safety rule(s) involved.
3. **Match the existing style.** Keep the surrounding code's naming,
   formatting (Swift standard style), and comment density.
4. **Tests required** for any change to `MacCleanCore`; UI changes should at
   minimum describe a manual test scenario in the PR description.
5. **No telemetry or network calls.** The app is fully offline and must stay
   that way.

## Pull request process

1. Fork the repository and create a feature branch from `main`
   (`git checkout -b fix/short-description`).
2. Make your change, including tests and doc updates where relevant.
3. Ensure `xcodebuild test` passes locally.
4. Open a PR describing **what** changed and **why**, linking any related
   issues.
5. Keep PRs small and focused — split unrelated changes into separate PRs.

## Commit messages

Use a short imperative summary line (e.g. `Skip permission-denied folders
during orphan scan`), followed by an optional body explaining the reasoning.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).