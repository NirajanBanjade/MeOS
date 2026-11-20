# Feature 02: Laboratory World and Interactions

## Goal

Deliver one reusable, top-down SpriteKit laboratory in which the player can move, meet the System Engineer, and interact with every mission component.

## Dependencies

- `01-visual-design-and-app-shell.md`
- Integrates later with `03-deterministic-simulation-engine.md` and `04-mission-progression-and-persistence.md`.

## Required Agent Skills

- SpriteKit scene construction, nodes, actions, texture atlases, and camera layout
- Touch-to-move controls and simple grid or waypoint navigation
- SwiftUI and SpriteKit state bridging
- Accessible alternatives for spatial interaction

## Tech Stack

- SpriteKit for the scene, characters, machines, interaction indicators, and world animation
- SwiftUI for dialogue and component panels
- Bundled texture atlases and short local audio clips
- XCTest and XCUITest

## Requirements

- Create one fixed laboratory scene containing the player, System Engineer NPC, server workstation, CPU station, database slots, infrastructure slots, request generator, and monitoring terminal.
- Tap a walkable point to move there using a grid or waypoint route. Advanced physics and complex NPC pathfinding are out of scope.
- Prevent movement through walls, machines, and blocked tiles. Reject inaccessible destinations without moving to an invalid position.
- Give every interactive component a persistent or proximity-visible nameplate with a consistent icon and plain-English name, such as “Server,” “CPU Station,” “Database Slot,” “Request Generator,” and “Monitoring Terminal.”
- Show a clear, state-driven proximity prompt in the form “Component Name — Tap to inspect” when the player is in range of an enabled object.
- On first discovery, present a short teaching card that states what the component is, what it does in MeOS, and why the current mission asks the player to interact with it. The card must be dismissible and replayable from the Component Glossary.
- Tapping a nearby object opens its SwiftUI panel. Tapping a distant object may move toward it but must not interact until the range rule is satisfied.
- Provide a direct accessible interaction list or equivalent route when an object cannot be reached through spatial controls. The list must expose the same component name, purpose, availability, and action as the spatial prompt.
- Introduce the System Engineer on first entry and connect NPC dialogue to the active mission.
- Use NPC dialogue and objective highlighting to point out a newly required component before expecting the beginner to find it independently.
- Preserve player position and scene state while a SwiftUI overlay is open.
- Mission state controls which machines, slots, and interactions are enabled; use the same scene for all missions.
- Target 60 FPS on supported iPads and remain playable at lower frame rates.

## Architecture and Visual Rules

- `GameScene` renders state; `PlayerController` handles movement; `InteractionManager` resolves range and permitted actions.
- Do not put mission rules, metrics, or simulation correctness in SpriteKit actions or collision callbacks.
- Use SpriteKit actions only to interpolate between confirmed model states.
- Avoid per-frame texture creation and unnecessary physics bodies.
- Pause world and background animation while not visible.
- Use playful but technically recognizable machines and consistent interaction icons from the shared visual system.

## Edge Cases

- Stop at the nearest valid point when a path reaches a wall.
- Reject blocked or unreachable destinations gracefully.
- Ignore a second movement command only when it would corrupt the current route; otherwise replace the destination deterministically.
- Serialize repeated interaction taps so only one panel opens.
- Backgrounding pauses movement and restores a stable position.
- Missing decorative textures use bundled placeholders and do not block interaction.

## Test Requirements

- Unit test walkable-tile validation, route selection, interaction distance, enabled-object filtering, and first-discovery state.
- Integration test movement to every required workstation and opening its corresponding panel.
- Verify every interactive object has a unique nameplate, matching icon, proximity prompt, first-discovery teaching card, glossary entry, and accessible action.
- UI test meeting the NPC and interacting with the server during onboarding.
- Test walls, inaccessible targets, blocked objects, rapid taps, overlay close, background/resume, and direct accessible interaction.
- Profile a representative scene for frame stability and confirm simulation outcomes remain unchanged at reduced FPS.

## Complete When

- [x] The player can navigate the complete room without crossing obstacles.
  - Evidence: `LaboratoryWorld.swift`, `LaboratoryScene.swift`, and `LaboratoryWorldTests.routesReachEveryObject` / `blockedAndInvalidDestinations`; `swift test` passed 18 tests.
- [x] Every required object has spatial and accessible interaction routes.
  - Evidence: the shared world defines nine uniquely named objects and interaction tiles; `AccessibleInteractionsPanel` exposes matching purpose, availability, and direct actions; every-workstation integration and Feature 02 UI tests passed.
- [x] A beginner can identify every component and understand its purpose before using its controls.
  - Evidence: persistent scene nameplates/status text, first-entry System Engineer guidance, proximity prompts, first-discovery teaching cards, and replay links in `GlossaryPanel`; onboarding UI test passed on iPad Pro 13-inch (M5).
- [x] Overlay presentation preserves the world and player position.
  - Evidence: the retained `LaboratoryScene`, confirmed-tile checkpointing, panel pause bridge, and application-bridge persistence tests; iPad unit/integration suite passed.
- [x] One scene supports every mission state.
  - Evidence: `LaboratoryScene.updateMission(_:)` updates availability for Missions 1–5 without replacing the scene; mission filtering and every-workstation tests passed.
- [x] Interaction, UI, accessibility, and performance tests pass.
  - Evidence: `swift test` passed 18/18; Xcode 27.2 iPad unit/integration/performance run passed 20/20 and collected routing performance metrics; all seven UI tests passed individually on iPad Pro 13-inch (M5), including the two Feature 02 paths.

