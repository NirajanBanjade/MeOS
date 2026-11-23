# Feature 06: Mission 1 — Sequential Request Processing

## Goal

Teach that a single worker processes one request at a time and later requests wait in a queue.

## Dependencies

- Features 01–04
- Uses the visualization contract in `05-simulation-visualization-and-metrics.md`.

## Required Agent Skills

- Client/server and FIFO queue concepts
- SwiftUI educational interaction design
- SpriteKit event-driven animation
- Deterministic integration testing

## Tech Stack

- Pure Swift simulation engine for outcomes
- SpriteKit for request cards, queue, worker, and CPU execution
- SwiftUI for mission briefing, Start Server, identification prompt, and result panel
- SwiftUI Canvas for the scheduling timeline

## Requirements

- The System Engineer directs the player to the server and supplies five uniquely identified request cards at simulated time zero.
- Configure one worker, CPU capacity one, queue capacity ten, and the standard 600 ms wait plus 400 ms CPU fixture.
- Start Server is disabled when no requests exist and while a run is active.
- Animate every request from arrival through queue, worker phases, CPU execution, and completion using engine events.
- Display completed count, current queue, queue waiting time, total completion time, and average latency.
- After all five complete, ask the player to identify why requests waited. Present “the request queue grew while the only worker was busy” as the technically correct cause.
- Victory requires all five requests to complete and the queue bottleneck to be identified.
- The result explains sequential processing and connects visible waiting to the calculated event history.
- Completion unlocks Mission 2 and Worker Manager.

## Edge Cases

- No requests shows “Queue empty” and cannot run.
- Repeated Start taps dispatch one run and never duplicate cards.
- Closing the panel pauses the presentation while preserving the engine state; returning resumes from the same simulated event position.
- More than ten waiting requests follow deterministic queued/rejected behavior, even though the scripted mission submits five.
- Negative request counts are rejected before a run.

## Test Requirements

- Assert five completions, no failures/rejections, 5,000 ms makespan, and 3,000 ms average latency for the mission fixture.
- Assert request identity and FIFO completion order are preserved.
- UI test walk to server, receive cards, start, observe metrics, answer the cause prompt, complete, and unlock Mission 2.
- Test empty queue, repeated Start, close/reopen, pause/resume, reset, queue overflow, and invalid request count.
- Assert displayed metrics and timeline values exactly match the result event log.

## Complete When

- [x] The full mission is playable from briefing to results.
  - Evidence: `SequentialMissionPanel`, `AppModel`, and `SequentialMissionRun`; the iPad UI path from Server inspection through Mission 2 unlock passed.
- [x] Every visual transition is traceable to an engine event.
  - Evidence: Mission 1 renders `SimulationPresentationSession.renderState` through `SimulationScene` and `SchedulingTimelineView`; `sequentialMissionEdges` verifies the full timeline against phase events.
- [x] Victory requires both execution and understanding.
  - Evidence: `SequentialMissionRun.answer` rejects distractors, and `MissionVictoryRule.sequentialQueueUnderstood` requires five completions plus the queue fact; focused unit and UI tests passed.
- [x] Mission 2 unlocks exactly once.
  - Evidence: `sequentialMissionHappyPath` verifies one completion/unlock despite repeated Start and answer commands; centralized `MissionEngine.complete` remains idempotent.
- [x] All fixture, edge-case, and UI tests pass.
  - Evidence: `swift test` passed 49/49; Xcode iPad unit/integration/performance passed 52/52; the full nine-test UI target passed on an iPad Pro 13-inch (M5), including the new Mission 1 end-to-end path; generic iPad simulator build succeeded.

