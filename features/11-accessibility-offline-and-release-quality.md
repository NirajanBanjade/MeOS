# Feature 11: Accessibility, Offline, and Release Quality

## Goal

Make the complete MVP understandable, resilient, accessible, fully offline, performant, and ready to package from Xcode 27 or later.

## Dependencies

- Features 01–10

## Required Agent Skills

- iPadOS accessibility and UI testing
- Performance and lifecycle profiling
- Offline dependency and asset auditing
- Xcode build, archive, attribution, and release validation

## Tech Stack

- Apple-native frameworks only: Swift 6, SwiftUI, SpriteKit, Foundation, XCTest, and XCUITest
- Bundled asset catalogs, texture atlases, local JSON, and compressed short audio
- Xcode Instruments and standard Xcode build/archive tooling

## Requirements

- All gameplay, missions, content, saves, assets, sounds, and credits work with no internet connection.
- Use no third-party runtime packages, remote resources, accounts, cloud storage, analytics, downloaded models, or real network communication.
- Provide accessibility labels, values, hints, logical focus, readable text, Reduce Motion behavior, and non-color-only status for every essential path.
- Muted or missing optional sound never blocks a mission. Expose an independent sound setting.
- Pause safely on background, cancel hidden simulation presentation work, and restore a stable checkpoint on return or relaunch.
- Maintain deterministic results when rendering falls below 60 FPS.
- Avoid unnecessary SpriteKit physics and per-frame texture creation.
- Use shared texture atlases and reusable assets; do not bundle large videos, virtual machines, language models, or unused resources.
- Credit all external assets and open-source contributions. Prefer fully original or Apple-provided assets.
- All user-facing text, tutorials, dialogue, documentation, accessibility labels, and learning content are in English.
- Prefer a submission ZIP under 25 MB; the hard maximum is 500 MB.
- The complete Xcode project, tests, local mission/dialogue data, assets, sounds, and credits must be included.

## End-to-End Acceptance Path

1. Launch clean and enter the laboratory.
2. Meet the System Engineer and interact with the server.
3. Complete Mission 1 and unlock Mission 2.
4. Compare workers and complete Mission 2.
5. Install/connect the database and complete Mission 3.
6. Add a valid infrastructure component and complete Mission 4.
7. Diagnose and repair the final scenario.
8. Receive “MeOS System Architect” and confirm all mission replay options.
9. Close and reopen the app and confirm completion and replay availability.

## Test Requirements

- Build and run using Xcode 27 or later on supported iPad simulators and at least one representative device configuration when available.
- Execute the end-to-end path offline and verify no feature waits for or attempts network access.
- Complete the primary educational demonstration in approximately three minutes, with first interaction under 15 seconds and first learning outcome under 60 seconds.
- Run VoiceOver-oriented UI tests, Reduce Motion tests, large-text layout checks, mute tests, and non-color status checks.
- Test backgrounding, termination, relaunch, corrupt saves, older saves, rapid controls, repeated Run, reset during execution, invalid configurations, low FPS, and missing optional assets.
- Run the full unit, integration, UI, deterministic replay, and performance suite with no known reproducible crash.
- Archive the project and inspect the ZIP contents and size. Fail release if it exceeds 500 MB, lacks required resources, or depends on downloaded content.

## Complete When

- [x] All five missions and replay work offline from a clean install.
  - Evidence: `AppModelTests.cleanOfflineMissionJourneyAndReplay` completes Missions 1–5, restores the completed save, and starts a clean replay of each mission; source/package audit found no networking APIs or remote runtime packages; `swift test` passed 64 tests.
- [x] Accessibility alternatives preserve every completion path.
  - Evidence: `AccessibleInteractionsPanel` provides direct actions, and the UI suite covers accessible interaction plus Missions 1–5; Xcode 27.2 iPad UI tests passed 14/14.
- [x] Progress survives relaunch and lifecycle edge cases.
  - Evidence: `AppModelTests.backgroundingAndRestore` and `cleanOfflineMissionJourneyAndReplay`, plus `ShellStoreTests` migration/corruption coverage; Xcode unit tests passed 64 tests.
- [x] Determinism is unchanged by FPS, animation speed, or device performance.
  - Evidence: deterministic simulation and playback tests compare identical outcomes across frame rates and presentation speeds; Xcode performance tests passed 3/3.
- [x] The three-minute demonstration and timing targets are met.
  - Evidence: `MeOSUITests.testCleanInstallAllMissionsAndThreeMinuteLearningPath` asserts first learning within 60 seconds and the full clean-install Mission 1–5 path within 180 seconds; it passed in 86.7 seconds on iPad Pro 13-inch (M5). `testFreshLaunchPresentationPathAndRapidTapSafety` passed the 15-second first-interaction target.
- [x] All tests pass with no known reproducible crash.
  - Evidence: `swift test` passed 64/64; Xcode 27.2 unit tests passed 64/64, performance tests 3/3, and iPad UI tests 14/14.
- [x] Credits and every required local resource are packaged.
  - Evidence: the Release archive contains `Credits.txt`, compiled `Assets.car`, the app executable, and bundled app icons; mission and dialogue content are local Swift definitions.
- [x] The archive is preferably under 25 MB and never above 500 MB.
  - Evidence: Xcode Release archive measured 9.3 MB; inspected ZIP measured 4.0 MB, below both limits.
