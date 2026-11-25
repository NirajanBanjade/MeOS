# Feature 08: Mission 3 — Database Storage

## Goal

Teach persistence, database connections, reads, writes, latency, capacity, and deterministic write contention through a small key/value database.

## Dependencies

- Features 01–07
- Uses the database rules and timings from Feature 03.

## Required Agent Skills

- Database read/write, connection, consistency, and capacity concepts
- Swift value modeling and validation
- SwiftUI form alternatives and feedback design
- SpriteKit event-driven data-flow animation

## Tech Stack

- Pure Swift in-memory educational database model
- SpriteKit for installation, connection, request flow, and database activity
- SwiftUI Database Terminal and result panels
- XCTest and XCUITest

## Requirements

- Activate an empty database slot only after Mission 2. The player installs one primary database and explicitly connects it to the server.
- Database capacity is five unique keys; reads take 300 ms and writes take 500 ms.
- The terminal accepts trimmed, non-empty key/value input and exposes Create/Update and Read actions without pretending to run SQL.
- Writing an existing key performs an upsert and does not consume a new slot.
- Reading an absent key returns “Record not found” without crashing or inventing a value.
- A disconnected request fails with a typed connection error and a matching explanation.
- Conflicting writes serialize by arrival time, then stable request ID; the later write becomes the stored value.
- The scripted path writes `status = online`, reads it back, then runs a mixed read/write workload through the connected server.
- Victory requires successful installation, connection, write, matching read, and completion of the connected workload.
- Completion unlocks Mission 4 and infrastructure slots.

## Architecture and Visual Rules

- Mission UI issues validated commands; the database model owns records and outcomes.
- Installation and cable animations reflect actual node and connection state.
- The terminal shows operation status, simulated latency, capacity usage, and errors using text and icons as well as color.
- Replaying earlier missions receives their clean baseline and cannot inherit these records.

## Edge Cases

- Reject empty or whitespace-only keys with helpful inline feedback.
- At five unique keys, reject a sixth insert but continue allowing upserts.
- A read while disconnected fails even if the key exists.
- Two same-time writes follow the stable ID tie breaker.
- Closing or resetting cancels uncommitted mission actions and restores the defined checkpoint.

## Test Requirements

- Unit test insert, read, upsert, missing key, validation, capacity, latency, connection failure, and conflicting write order.
- Assert five inserts fill capacity, a sixth unique insert fails, and an existing-key upsert succeeds.
- Integration test install, connect, write `status = online`, read the matching value, run workload, complete, and unlock Mission 4.
- Test that replaying Missions 1 or 2 does not expose Mission 3 database state.
- Assert database SpriteKit events and displayed operation counts match engine events.

## Complete When

- [x] The database can be installed and connected from the shared world.
  - Evidence: `DatabaseMissionPanel`, `AppModel.installDatabase` / `connectDatabase`, and `LaboratoryScene.updateDatabaseState` drive the shared slot, cable, status text, and accessible controls; the Mission 3 UI test passed on iPad Pro 13-inch (M5).
- [x] All validation, capacity, ordering, and connection rules are deterministic.
  - Evidence: `DatabaseMissionRun` validates trimmed key/value commands and commits only pure-engine results; `AppModelTests.databaseMissionEdges` plus `SimulationEngineTests` cover missing reads, five-key capacity, sixth insert rejection, upsert, disconnected requests, exact latency, and stable write ordering; all suites passed.
- [x] The scripted record survives the required mission sequence.
  - Evidence: `databaseMissionHappyPath` verifies `status = online` remains stored through the matching read and connected mixed workload, while replaying Mission 1 restores an empty database baseline.
- [x] Mission 4 unlocks exactly once.
  - Evidence: `databaseMissionHappyPath` verifies idempotent centralized completion and the UI test reaches “Mission 4 · Infrastructure Scaling.”
- [x] Database unit, integration, and UI tests pass.
  - Evidence: `swift test` passed 53/53; the Xcode 27.2 iPad unit/integration/performance run passed 56/56; the focused Mission 3 UI test passed; and the complete iPad UI suite passed 11/11.

