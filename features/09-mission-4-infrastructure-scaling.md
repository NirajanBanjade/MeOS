# Feature 09: Mission 4 — Infrastructure Scaling

## Goal

Teach read replicas, caches, application servers, routing, budgets, and architectural tradeoffs using measurable outcomes.

## Dependencies

- Features 01–08
- Uses Feature 05 for architecture and before/after visualization.

## Required Agent Skills

- Caching, replication, load balancing, and bottleneck analysis
- Deterministic distributed-system modeling
- SwiftUI architecture diagrams and comparative metrics
- SpriteKit infrastructure animation

## Tech Stack

- Pure Swift infrastructure and routing model
- SpriteKit for slots, request routes, cache/database access, and component state
- SwiftUI configuration, budget, explanation, and result panels
- SwiftUI Canvas architecture connections and metric charts

## Requirements

- Use a fixed read-heavy workload of ten requests for the preloaded `catalog` key, all arriving at time zero.
- Baseline routes all reads through one primary database, serialized at 300 ms each. Expected completion timestamps are 300 through 3,000 ms and average latency is 1,650 ms.
- Provide three upgrades: read replica costing 3, cache costing 2, and second application server costing 2. A load-balancing/routing connection costs 1. Mission budget is 3.
- Replica distributes eligible reads deterministically between primary and replica. Writes remain primary-only and synchronize after 1,000 ms.
- A cold cache performs one 300 ms database read, then serves the remaining matching reads at 50 ms each. Expected average latency for the fixed sequential cache fixture is 525 ms.
- A second server without the routing connection receives no traffic. With routing it increases server capacity but does not remove the fixed workload’s database bottleneck.
- Victory requires staying within budget and reducing average request latency to 1,000 ms or less. The replica and cache paths are valid; server-only is not.
- Disable unaffordable additions with visible cost and reason. Permit reset and retry after any less-effective choice.
- Show before/after average latency, completion time, database operations, cache hits/misses, replica reads, and resource cost.
- Completion unlocks Mission 5 and the Monitoring Terminal alert.

## Edge Cases

- Reading from a replica before its 1,000 ms synchronization may return an explicitly labeled stale value.
- A database outage fails dependent cache misses and writes; existing fresh cached reads may succeed only when the model marks them valid.
- A write invalidates the matching cache entry immediately.
- A second server cannot receive traffic through a nonexistent connection.
- No predefined mission state may make every allowed configuration fail the target.

## Test Requirements

- Assert baseline average latency is 1,650 ms.
- Assert the fixed cache path has one miss, nine hits, and 525 ms average latency.
- Assert the replica path is deterministic and meets the 1,000 ms target.
- Assert server-only does not meet the target and server plus routing costs exactly 3 without falsely removing database contention.
- Unit test replication lag, stale read labeling, cache population/invalidation, unavailable database, budgets, and invalid routes.
- UI test baseline, each upgrade path, reset, valid victory, explanation, and Mission 5 unlock.

## Complete When

- [x] At least replica and cache are valid measured solutions.
  - Evidence: `InfrastructureMissionRun` and `AppModelTests.infrastructureMeasuredSolutions`; `swift test` passes with exact 525 ms cache and 900 ms replica averages.
- [x] Every upgrade’s behavior and cost match its actual configured graph.
  - Evidence: `InfrastructureMissionRun.configuration(for:)` plus `AppModelTests.infrastructureEdgesAndServerTradeoff`; `swift test` verifies costs, nodes, routes, and destinations.
- [x] Less-effective choices remain playable and accurately explained.
  - Evidence: server-only and server-plus-routing results remain resettable and explain unused capacity versus primary-database contention in `InfrastructureMissionRun`; tests pass.
- [x] Mission 5 unlocks exactly once.
  - Evidence: `AppModelTests.infrastructureUnlock` verifies the completion set, current mission, Monitoring Terminal availability, and duplicate-call guard.
- [x] Infrastructure, metric, and UI tests pass.
  - Evidence: `AppModelTests.infrastructureMeasuredSolutions`, `AppModelTests.infrastructureEdgesAndServerTradeoff`, and both Mission 4 XCUITests; `swift test` passed 61 tests and the two focused iPad Pro 13-inch UI tests passed.

