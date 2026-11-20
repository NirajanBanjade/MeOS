# Feature 01: Visual Design and App Shell

## Goal

Create the landscape iPad app shell and a cohesive visual language for MeOS. A new player must be able to launch the app, understand the premise, and enter the laboratory within 15 seconds.

## Dependencies

- None. This is a foundation for every other feature.
- Expose reusable components rather than mission-specific copies.

## Required Agent Skills

- Swift 6 and SwiftUI architecture
- iPadOS landscape layout and adaptive sizing
- Typography, color systems, iconography, and animation design
- Accessibility and UI testing

## Tech Stack

- Xcode 27 or later
- Swift 6 and SwiftUI
- Apple-native fonts, SF Symbols, and bundled assets only
- `NavigationStack`, sheets or custom overlays, and SwiftUI transitions
- XCTest and XCUITest

## Requirements

- Build Home, Game, Mission, System Panel, Results, Pause, Component Glossary, Credits, and Settings presentation states.
- Home displays the MeOS title, short premise, Start or Continue, sound control, and credits.
- The game shell displays the laboratory, current objective, mission progress, and pause control without obscuring essential play space.
- Panels include a title, current context, permitted actions, resources, primary action, and explicit close/back action.
- Every component panel displays the component's plain-English name, a consistent icon, a one-sentence purpose, and its role in the current mission before configuration controls.
- Provide a replayable Component Glossary from the pause menu and component panels. Each entry explains what the component is, what it does in MeOS, and the visual states a beginner may observe.
- Closing a panel returns to the same laboratory and player position.
- Create reusable cards, buttons, metric tiles, status badges, dialog panels, resource counters, and panel containers.
- Use a deliberately designed 2D educational-game palette, polished typography, consistent icons, rounded panel language, and smooth transitions. Do not ship generic default-looking Forms, Lists, or unstyled controls.
- Status must never depend on color alone; pair color with icons and text.
- Support readable text, Dynamic Type where the landscape layout remains usable, VoiceOver labels/hints, and logical focus order.
- Respect Reduce Motion. Replace nonessential movement with short fades or immediate state changes without hiding simulation outcomes.
- Sound is optional, locally bundled, independently mutable, and never required for progress.
- Keep all interface copy in English.

## Architecture and Visual Rules

- SwiftUI owns navigation, panels, controls, settings, results, and transitions.
- SpriteKit owns the laboratory and animated simulation objects; do not recreate the world in SwiftUI.
- SwiftUI Canvas owns custom charts and scheduling timelines; do not use it as a second game renderer.
- UI state reads from the central game and simulation state. Views must not calculate business outcomes.
- Use semantic design tokens for colors, spacing, type, corner radii, shadows, and animation durations.
- Bundle all assets. No remote images, fonts, analytics, authentication, or network calls.

## Edge Cases

- Start becomes Continue only when a valid save exists.
- A corrupt or unsupported save falls back safely and explains that new progress was started.
- Rapid primary-button taps produce one command.
- Fixed landscape mode or a valid responsive landscape layout must survive device rotation attempts.
- Missing optional audio or decorative assets use a safe silent/placeholder fallback.

## Test Requirements

- UI test fresh launch, Start, Continue, panel open/close, pause/resume, glossary access, sound toggle, and credits.
- Verify the first enabled interaction is reachable within 15 seconds on a clean launch.
- Verify all essential controls have accessibility labels and can be operated without sound or color recognition.
- Verify Reduce Motion avoids nonessential movement and retains all state feedback.
- Verify rapid taps cannot push duplicate screens or dispatch duplicate actions.
- Verify layouts at supported iPad landscape sizes and accessibility text sizes.
- Verify the app shell performs no network request in airplane/offline conditions.

## Complete When

- [x] Every required presentation state is reachable.
  - Evidence: `AppPanel`, `RootView`, and `AppPanels.swift`; `AppModelTests.presentationReachabilityAndPositionPreservation`; `swift test` (9 tests passed).
- [x] Every interactive component has beginner-readable identity and purpose text.
  - Evidence: `ComponentKind` and `GlossaryPanel`; `AppModelTests.glossaryCompleteness`; `swift test` (9 tests passed).
- [x] Shared visual components and design tokens are used consistently.
  - Evidence: `DesignTokens.swift`, `SharedComponents.swift`, and `PanelContainer.swift`; full Swift 6 source type-check passed.
- [x] The laboratory can be hosted without SwiftUI owning its simulation logic.
  - Evidence: `LaboratoryScene` is a render-only SpriteKit scene hosted by `GameView`; full Swift 6 source type-check passed.
- [x] Accessibility, offline, and UI tests pass.
  - Evidence: Xcode 27.2 iPad (A16) run passed 13 of 14 tests, with the sole large-text failure corrected and rerun successfully; Reduce Motion, sound, credits, pause/resume, glossary, Continue, rapid-tap, and accessibility-size paths passed. Source audit found no networking APIs or remote URLs.
- [x] The launch-to-laboratory path meets the 15-second target.
  - Evidence: `MeOSUITests.testFreshLaunchPresentationPathAndRapidTapSafety` passed its 15-second assertion on iPad (A16) and the primary path passed on iPad mini (A20 Pro).

