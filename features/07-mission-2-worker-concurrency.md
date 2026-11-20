# Feature 07: Mission 2 — Worker Concurrency

## Goal

Teach how workers overlap waiting phases while modeled CPU capacity limits CPU-intensive work and causes diminishing returns.

## Dependencies

- Features 01–06
- Uses Feature 05 for comparison charts and timelines.

## Required Agent Skills

- Concurrency, worker scheduling, and CPU contention concepts
- Deterministic comparative simulation
- SwiftUI configuration and data visualization
- SpriteKit multi-actor animation

## Tech Stack

- Pure Swift simulation and mission evaluation
- SpriteKit for workers, queue assignment, wait phases, and CPU contention
- SwiftUI Worker Manager and before/after results
- SwiftUI Canvas comparison timeline and charts

## Requirements

- Begin with the saved one-worker baseline using the same five request IDs, arrivals, phases, and seed as Mission 1.
- Worker Manager accepts integer counts from 0 through 4. Each worker costs one resource unit; the mission victory budget is two units.
- The player runs the one-worker baseline, selects two workers, and reruns the identical workload.
- Two workers may overlap 600 ms waiting phases but share CPU capacity one for 400 ms CPU phases.
- Victory requires worker count two, no more than two resource units, all requests complete, and makespan at or below 3,200 ms.
- Allow experiments with 0, 3, and 4 workers. Runs above the victory budget remain observable but cannot satisfy the budget objective.
- Results compare worker count, makespan, average latency, queue waiting, and CPU utilization against baseline.
- When configurations tie or improve only slightly, explain the modeled limiting resource instead of promising that every worker improves performance.
- Completion unlocks Mission 3 and database installation.

## Edge Cases

- Zero workers leaves accepted requests queued, terminates evaluation safely, and explains why no progress occurs.
- Counts below zero or above four are rejected.
- Rapid changes during a run are rejected and offered for the next reset.
- Out-of-order completion remains associated with correct request IDs.
- Retry restores the exact baseline fixture for a fair comparison.

## Test Requirements

- Assert one-worker baseline is 5,000 ms makespan and 3,000 ms average latency.
- Assert two-worker run is 3,000 ms makespan and 1,960 ms average latency and therefore meets victory.
- Test zero, one, two, three, and four workers for invariants, deterministic events, resource accounting, and diminishing-return explanations.
- UI test baseline run, Worker Manager change, comparison, victory, retry, and Mission 3 unlock.
- Assert both Canvas timelines and SpriteKit workers match assignments and timestamps from the event log.

## Complete When

- [ ] Baseline and comparison always use identical workload inputs.
- [ ] Two workers meet the stated target within budget.
- [ ] Invalid and non-useful configurations produce accurate feedback.
- [ ] Mission 3 unlocks exactly once.
- [ ] Simulation, comparison, and UI tests pass.

