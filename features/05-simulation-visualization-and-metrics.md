# Feature 05: Simulation Visualization and Metrics

## Goal

Turn simulation events into accurate, polished animations, charts, timelines, architecture views, and educational explanations without allowing rendering to alter results.

## Dependencies

- `01-visual-design-and-app-shell.md`
- `02-laboratory-world-and-interactions.md`
- `03-deterministic-simulation-engine.md`
- Consumed by Missions 1–5.

## Required Agent Skills

- SpriteKit animation orchestration
- SwiftUI Canvas chart and timeline drawing
- Event sourcing and state projection
- Performance, accessibility, and visual regression testing

## Tech Stack

- SpriteKit for requests, workers, process queues, CPU execution, database activity, cache/replica routes, and major system-state transitions
- SwiftUI Canvas for custom metric charts and scheduling timelines
- SwiftUI for controls, legends, architecture panels, explanations, and results
- XCTest, XCUITest, and snapshot or deterministic render-state tests where available

## Requirements

- Consume the ordered `SimulationEvent` stream as the only animation input. Never generate decorative request behavior that suggests events not present in the model.
- Provide play, pause, reset, and presentation-speed controls. Speed changes presentation duration only, not simulated timestamps or results.
- Render request identity consistently from queue through completion/failure, including out-of-order completion.
- Animate worker assignment, waiting, CPU acquisition/release, completion, rejection, database access, cache hit/miss, replica routing, and connection failure.
- Display concise live metrics and a results view containing outcome, before/after metrics where relevant, what happened, why it happened, and Retry/Continue.
- Calculate completed, failed, rejected, queue wait, makespan, average latency, database operations, and utilization in the engine; the visual layer only formats them.
- Draw scheduling timelines from phase events and system architecture from actual nodes and connections.
- Use reusable server, CPU, worker, database, cache, replica, router, request, and infrastructure-slot visuals.
- Maintain a cohesive 2D educational-game metaphor, consistent icons, polished typography, and smooth state transitions.
- Reduced Motion replaces travel animations with highlights, state changes, and concise announcements while preserving sequence and causality.
- Add text/icon labels for queued, running, waiting, completed, failed, stale, hit, and miss states.

## Architecture Rules

- Separate event projection, render state, and node/view creation.
- SpriteKit actions may acknowledge completion to the presenter but cannot complete requests or advance mission logic.
- Reset cancels outstanding presentation actions before projecting the baseline state.
- Pausing or backgrounding freezes presentation safely; engine state remains a stable snapshot.
- Avoid recreating textures or charts on every frame. Update only when projected data changes.
- Memory allocation and deadlock visualization are post-MVP. If later added, they must use the same engine/event approach and SpriteKit rather than random decoration.

## Edge Cases

- Lower FPS may skip interpolation frames but must end at the correct projected state.
- Rapid Run presses cannot create overlapping event presenters.
- Reset during playback removes stale nodes and restores all counters.
- An unknown event type uses a safe logged fallback and does not fabricate a visual.
- Empty event streams show a stable empty state.

## Test Requirements

- For each event type, assert the projected render state contains the correct request, worker, node, route, status, and timestamp.
- Compare every displayed metric and Canvas data point with the engine result.
- Test play, pause, speed change, background/resume, reset, rapid Run, empty events, and low-FPS completion.
- Verify Reduce Motion and VoiceOver expose the same state sequence and outcomes.
- Performance test the maximum MVP fixture without per-frame texture creation or background work while hidden.
- Integration test representative Mission 1 queueing, Mission 2 contention, Mission 3 database, Mission 4 cache/replica, and Mission 5 diagnostics.

## Complete When

- [x] Every visible system behavior maps to a real event or state.
  Evidence: `SimulationEventProjector`, `SimulationScene`, and
  `SimulationVisualizationTests.everyEventPayloadProjectsToVisibleState` cover
  every event payload, including a safe unknown-event fallback.
- [x] Charts, timelines, architecture, metrics, and explanations agree.
  Evidence: `VisualizationViews` consumes one projected run, while
  `SimulationMetricFormatter` formats the engine result without recomputation;
  representative-run and exact-metric tests pass.
- [x] Rendering cannot mutate simulation or mission outcomes.
  Evidence: visualization owns only projected presentation state, SpriteKit has
  no simulation/mission engine, and playback lifecycle/determinism tests pass.
- [x] Reduced Motion and non-color-only alternatives are complete.
  Evidence: travel becomes immediate highlights under Reduce Motion, statuses
  use text and icons, and the accessible event sequence and UI test pass.
- [x] Projection, integration, accessibility, and performance tests pass.
  Evidence: `swift test` passes 47 tests; Xcode unit tests pass 50 tests; the
  complete UI target passes 8 tests; the generic iPad simulator build succeeds.

