# Feature 03: Deterministic Simulation Engine

## Goal

Build the pure Swift source of truth for requests, queues, workers, CPU limits, databases, routing, events, and calculated performance metrics.

## Dependencies

- None for model correctness.
- Publishes state and events for Features 02 and 05–10.

## Required Agent Skills

- Swift value types, protocols, Codable, and error modeling
- Discrete-event or fixed-tick simulation design
- Scheduling, queues, concurrency models, and performance metrics
- Deterministic unit and property-style testing

## Tech Stack

- Pure Swift 6 Foundation models
- No SpriteKit, SwiftUI, wall-clock timers, real threads, or device-performance measurements in correctness logic
- XCTest

## Public Models and Interfaces

- `GameState`: mission, player position, configured components, simulation lifecycle, and durable progress reference.
- `SystemNode`: stable ID, node type, capacity, connections, and active state.
- `Request`: stable ID, type, arrival time, ordered processing phases, and status.
- `Worker`: stable ID, assigned request, availability, and resource requirements.
- `DatabaseState`: records, capacity, service times, availability, and replica synchronization state.
- `SimulationConfiguration`: worker count, CPU capacity, queue capacity, nodes, connections, cache, replica, and stored seed.
- `SimulationEvent`: simulated timestamp, stable sequence number, request/node IDs, and typed event payload.
- `SimulationResult`: counts, queue wait, average latency, completion time, database operations, utilization, ordered events, and explanation IDs.
- `SimulationEngine.run(initialState:workload:configuration:)` returns a result or a typed validation error without mutating UI state.

## Requirements

- Use deterministic discrete events or fixed ticks. Identical initial state, workload, configuration, and seed must produce identical ordered events and metrics.
- Use simulated milliseconds represented by an integer type. Never derive correctness from animation time or frame rate.
- Sort simultaneous events by simulated time, event priority, then stable request or node ID.
- Default constants: queue capacity 10, worker range 0–4, CPU capacity 1, database capacity 5 records, database read 300 ms, write 500 ms, cache hit 50 ms, and replica lag 1,000 ms.
- The standard request fixture contains a 600 ms waiting phase followed by 400 ms of CPU work.
- A worker holds one request through its ordered phases. Waiting phases may overlap; CPU work is serialized by the modeled CPU capacity.
- Reject negative capacities, out-of-range workers, nonexistent routes, duplicate IDs, non-finite values, and overlapping runs before execution.
- Queue overflow deterministically rejects later arrivals after the ten queued positions are occupied.
- Worker count zero leaves accepted requests queued and returns a stable, non-hanging result explaining the lack of progress.
- Metrics come only from events and include completed, failed, rejected, queued, and running reconciliation.
- A request can complete or fail once only; a worker cannot exceed capacity; durations and capacities cannot be negative.
- Randomized future workloads must store and reuse their seed.
- Explanations are selected from actual event/result conditions, never from the chosen button alone.

## Database and Infrastructure Rules

- Keys are trimmed, non-empty strings. Writing an existing key is an upsert and does not consume another capacity slot.
- Conflicting writes serialize by arrival time, then request ID.
- Writes go to the primary. Replica-eligible reads may route to a replica; synchronization occurs exactly 1,000 simulated ms after the primary write.
- A cold cache miss reads the backing database and populates the cache. A write invalidates the matching cache entry before completion; stale values cannot be silently marked fresh.
- A second server receives no work until it has a valid routing/load-balancing connection.
- Unavailable dependencies fail affected requests with typed reasons unless a mission explicitly defines a modeled fallback.

## Test Requirements

- Assert byte-for-byte-equivalent event ordering and equal metrics across repeated identical runs.
- For five simultaneous standard requests and one worker, assert completions at 1,000, 2,000, 3,000, 4,000, and 5,000 ms; 5,000 ms makespan; and 3,000 ms average latency.
- For the same workload and two workers, assert 3,000 ms makespan and 1,960 ms average latency.
- Test FIFO ordering, simultaneous-event tie breaking, queue overflow, zero workers, worker limits, CPU contention, pause/reset snapshots, and invalid configuration.
- Test missing reads, upsert, full storage, conflicting writes, disconnected database, replica lag, stale replica reads, cache hit/miss/invalidation, unavailable database, and invalid routing.
- Assert submitted requests always reconcile with final statuses and metrics contain no negative or non-finite values.
- Run the same fixture while render FPS is varied or absent and assert unchanged results.

## Complete When

- [ ] All public models are value-oriented, stable-ID based, and testable without UI frameworks.
- [ ] Standard fixtures produce the specified metrics.
- [ ] Every invariant and database/infrastructure rule has a passing test.
- [ ] Events contain enough information to reproduce every required visual and explanation.
- [ ] No wall-clock, frame-rate, or device-performance dependency exists.

