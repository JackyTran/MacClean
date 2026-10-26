#!/bin/bash
# Integration test runner for the privileged helper (TASKS T5.5).
#
# Runs the end-to-end integration test of the helper's algorithm:
# helper-side SafetyRules re-validation → Trash-first deletion of real files
# (including verifying the file really lands in ~/.Trash) → XPC payload
# round trip. See Tests/MacCleanCoreTests/HelperIntegrationTests.swift.
#
# NOT covered here (verified manually in M7, when Developer ID signing exists):
#   - launchd/SMAppService daemon spawning + root privilege. On macOS 26 the
#     execution policy blocks launchd-spawned ad-hoc binaries (dyld hangs on
#     provenance validation), so the signed-daemon flow needs real signing.
#     Manual M7 steps:
#       1. Build + Developer ID sign + notarize MacClean.app
#       2. Copy to /Applications, launch, run one uninstall with a root-owned
#          leftover, press "Retry with privileged helper…" (admin prompt)
#       3. Verify the /Library leftover is gone and the uninstall log lists it

set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project MacClean.xcodeproj -scheme MacClean \
    -only-testing:MacCleanCoreTests/HelperIntegrationTests test | tail -8