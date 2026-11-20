# Feature 10: Mission 5 — System Diagnostics

## Goal

Require the player to inspect evidence, identify a database bottleneck, choose an effective intervention, and verify the repaired system.

## Dependencies

- Features 01–09
- Uses the monitoring and visualization contracts in Feature 05.

## Required Agent Skills

- Performance diagnosis and bottleneck reasoning
- Mission evaluation from evidence and measured outcomes
- Accessible dashboard and feedback design
- Deterministic integration and UI testing

## Tech Stack

- Pure Swift diagnostic scenario and victory evaluator
- SpriteKit for alerts, workload activity, bottleneck state, and intervention effects
- SwiftUI Monitoring Terminal, intervention controls, and final summary
- SwiftUI Canvas charts and scheduling timelines

## Requirements

- Trigger a system alert after Mission 4 and direct the player to the Monitoring Terminal.
- Use a deterministic read-heavy workload where CPU utilization is low, worker queue pressure is not the limiting factor, and primary database latency is high.
- Display CPU utilization, worker queue, database load/latency, response time, failures, and current architecture from engine results.
- Require the player to inspect at least two distinct evidence panels before enabling the intervention decision.
- Offer increased workers, increased application-server capacity, read replica, and cache.
- Evaluate the combined current configuration, not merely the last selected action.
- A read replica or correctly functioning cache must reduce average latency to 1,000 ms or less and may win. Extra workers or server capacity alone must not win this scenario.
- Incorrect interventions run normally, show measured results, explain the remaining database bottleneck, and allow unlimited retries.
- Detect a missing database connection as a configuration fault distinct from a performance bottleneck.
- Victory requires a qualifying measured result, then presents the evidence chain, concepts learned, and title “MeOS System Architect.”
- Completion preserves all achievements and unlocks replay for all five missions without duplicating rewards.

## Edge Cases

- Multiple valid interventions are accepted when they meet the target.
- Multiple simultaneous changes are evaluated together and charged according to the active configuration.
- Repeated failed attempts have no penalty and return to a stable diagnostic checkpoint.
- Replaying the completed mission preserves the title and unlocks.
- Missing or inconsistent metrics fail evaluation safely rather than awarding victory.

## Test Requirements

- Assert the baseline evidence shows low CPU pressure and database latency above the success target.
- Assert workers-only and server-only interventions remain above 1,000 ms and receive the correct explanation.
- Assert replica and cache interventions each can meet 1,000 ms or less with deterministic events.
- Test missing connection diagnosis, combined configuration evaluation, repeated failures, unlimited retry, idempotent completion, and replay.
- UI test alert, two evidence inspections, wrong intervention, retry, valid repair, final explanation, title, and replay access.
- Assert monitoring charts, explanation IDs, and victory evaluation all derive from the same result.

## Complete When

- [ ] The player must investigate rather than guess immediately.
- [ ] Victory is based on measured improvement, not a specific button.
- [ ] Incorrect and combined interventions receive accurate outcomes.
- [ ] The title and replay unlock are awarded exactly once.
- [ ] Diagnostic, integration, persistence, and UI tests pass.

