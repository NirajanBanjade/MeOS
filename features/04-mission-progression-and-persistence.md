# Feature 04: Mission Progression and Persistence

## Goal

Provide a centralized mission engine and reliable local progress so objectives, unlocks, retries, replay, and relaunch behavior remain consistent.

## Dependencies

- `03-deterministic-simulation-engine.md`
- Integrates with Features 01, 02, and 06–10.

## Required Agent Skills

- State machines and data-driven content
- Codable persistence, versioning, and migrations
- SwiftUI observable state without duplicated sources of truth
- Unit and lifecycle testing

## Tech Stack

- Pure Swift mission definitions and evaluators
- Codable with an atomic, versioned local file; UserDefaults only for small preferences such as sound
- Bundled JSON or Swift data for missions and dialogue
- XCTest and XCUITest

## Requirements

- Define five missions in order: sequential processing, worker concurrency, database storage, infrastructure scaling, and system diagnostics.
- Each `MissionDefinition` contains a stable ID, title, learning concepts, prerequisite, baseline state, workload, permitted actions, objectives, victory evaluator, result explanations, and unlock.
- Centralize lifecycle as ready, running, paused, completed, or failed. Only the mission engine may award completion or unlock the next mission.
- Completed missions remain accessible for replay. Replay uses a clean mission baseline and must not remove achievements or duplicate unlocks.
- Retry cancels the active run, discards mission-scoped experimental state, and restores the identical baseline workload and seed.
- Returning to an earlier mission isolates later database and infrastructure changes from that scripted baseline.
- Persist schema version, current mission, completed mission IDs, title award, player position/checkpoint, sound preference, and essential configured components.
- Do not persist a half-applied event. On backgrounding, pause safely and save a stable checkpoint; on termination, restore that checkpoint or restart the current mission baseline.
- Save atomically after completion, unlock, stable checkpoint changes, and settings changes.
- Invalid, corrupted, or future-version saves recover to safe defaults without crashing. Supported old versions migrate deterministically.
- Unlimited retries are always allowed and carry no punishment.

## Edge Cases

- Repeated completion commands award a mission once.
- Completed-mission replay cannot relock content or overwrite newer canonical progress.
- Reset during execution cancels the run before restoring baseline.
- Configuration changes during a run are rejected or explicitly queued for the next run.
- Backgrounding and reopening cannot leave lifecycle marked running without a valid active engine.
- A missing bundled mission definition fails safely with a developer-visible assertion and a user-facing unavailable state.

## Test Requirements

- Unit test prerequisite checks, objective updates, all unlock transitions, idempotent completion, unlimited retry, and replay isolation.
- Persistence round-trip every durable field and verify atomic replacement behavior.
- Test corrupt data, missing data, supported older schema migration, unsupported future schema fallback, and interrupted active runs.
- Integration test completing Missions 1–5, relaunching, and confirming completion, title, Continue behavior, and replay access.
- Verify retry produces the same baseline IDs, seed, events, and results.

## Complete When

- [ ] One mission engine owns objectives, completion, unlocks, retries, and replay.
- [ ] All five definitions are local and load without a network.
- [ ] Progress survives normal termination and relaunch.
- [ ] Replay and older missions are isolated from later experimental state.
- [ ] Mission and persistence tests pass.

