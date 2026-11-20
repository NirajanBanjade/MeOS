
Product Requirements Document (PRD)

Version: 1.0 — Minimum Viable Product
Platform: iPadOS (landscape orientation)
Development: Xcode 27+, Swift 6, SwiftUI, SpriteKit
Connectivity: Fully offline
Target ZIP Size: Under 25 MB (500 MB maximum allowed)
Product Category: Educational 2D Adventure / Computer Science Simulation
MeOS is an interactive 2D educational adventure game that teaches computer science concepts through exploration, experimentation, and decision-making.

Players enter a fictional computer system as a junior system engineer responsible for restoring and improving an unreliable digital infrastructure.

Instead of reading explanations or answering traditional quizzes, players physically interact with a simulated computer environment, install components, manage resources, diagnose performance issues, and observe the consequences of their decisions.

Core Philosophy: Learn by doing, failing, debugging, and improving.
Traditional computer science education often presents operating systems, concurrency, databases, and distributed systems as separate theoretical subjects.

Students can understand their definitions without understanding how these components interact in practical systems.

MeOS addresses this gap by presenting an interconnected computing environment where each new concept builds upon previously acquired knowledge.
1. Teach fundamental computing concepts using a small, interactive 2D world.
2. Demonstrate real-world consequences of architectural decisions.
3. Connect CPU scheduling, concurrency, databases, and scalability.
4. Provide a meaningful learning experience within three minutes of launching the application.
5. Support replayability without requiring external data or network services.
6. Remain lightweight through shared assets and reusable simulation components.
- High school and college students beginning computer science.
- Students learning operating systems, databases, and system design.
- Self-taught programmers wanting an intuitive understanding of computing infrastructure.
No prior knowledge of operating systems is required.
The first release will contain:
- One explorable 2D computer laboratory.
- One controllable animated player character.
- One instructional NPC called the System Engineer.
- Five progressively unlocked missions.
- Reusable server, CPU, worker, database, and network components.
- An interactive request-processing simulation.
- A visual system architecture panel.
- Immediate feedback for user decisions.
- Local progress persistence.
- A final diagnostic challenge.
- A replay option for completed missions.
The following are not required:
- Real operating-system virtualization or emulation.
- Actual database servers or SQL query execution engines.
- Real network communication.
- Multiplayer functionality.
- Online leaderboards or authentication.
- Cloud storage or user accounts.
- Generative AI or downloaded ML models.
- Large open-world maps.
- Complex NPC pathfinding.
- Real multithreading as the mechanism for teaching concurrency.
- Full CPU instruction-set simulation.
The system will use deterministic educational models, rather than reproducing all behavior of production infrastructure.
The player arrives inside a malfunctioning computer laboratory called MeOS.

A system engineer approaches:

"Welcome to MeOS. Our applications are running slowly, the request queue keeps growing, and our infrastructure can't handle the workload. We need your help."

The player is assigned the role of Junior System Engineer.

Each successful mission restores or improves one part of MeOS.
Stage 1 — Understand the System
Learn how requests are processed.

Stage 2 — Improve Concurrency
Introduce additional worker threads.

Stage 3 — Store Data
Connect a database to the server.

Stage 4 — Scale Infrastructure
Choose between architectural improvements.

Stage 5 — Diagnose a Failure
Use acquired knowledge to troubleshoot an integrated system.

At completion, the player earns the title "MeOS System Architect."
The player controls a small 2D character inside a fixed, top-down laboratory.

The environment contains:
- Server workstation.
- CPU processing station.
- Database installation slots.
- Request generator.
- Monitoring terminal.
- System Engineer NPC.
Controls
- Tap a walkable location to move the character.
- Tap a nearby object to interact.
- Display a clear interaction indicator when an object is within range.
- Open SwiftUI overlays for configuration or educational challenges.
- Close the overlay to return to the same position in the world.
Movement will use simple grid or waypoint navigation, not advanced physics.
1. The player receives a mission.
2. The player explores the laboratory.
3. The player interacts with relevant components.
4. The player selects an action or system configuration.
5. The simulator processes the configuration.
6. An animated visualization shows the outcome.
7. The player receives performance metrics and explanations.
8. The player can retry or advance.
There must be a direct relationship between the player's action and the observed result.

For example:

Player action: Increase worker count from one to two.

Simulation: Two workers can process independent requests concurrently, subject to available resources.

Visual feedback: Two worker characters begin processing separate requests.

Educational feedback: Parallel request handling can improve throughput, although resource contention and shared data introduce additional complexity.
Concepts: Client/server, requests, queues, sequential processing.

Scenario: The MeOS application server processes requests one at a time.

Objective: Understand why incoming requests must wait when the server is busy.

Gameplay:
1. Player walks to the server.
2. Receives five request cards.
3. Presses "Start Server."
4. Watches the single worker process requests sequentially.
5. Observes waiting time and completed requests.
Victory Condition: All five requests finish successfully, and the player identifies the queue as the source of waiting.

Expected Learning: A sequential server processes one request at a time. Additional arriving requests wait for the available worker.

Edge Cases:
- No requests: show "Queue empty" and disable execution.
- Repeated Start presses: do not duplicate requests.
- Player exits the panel: preserve or intentionally pause simulation state.
- Requests exceed available queue capacity: show queued/rejected behavior according to a stated limit.
- Invalid configuration: prevent negative request counts.
Unlock: Worker configuration.
Concepts: Concurrency, workers, thread scheduling, resource limitations.

Scenario: More users are accessing MeOS, causing a backlog.

Objective: Improve request handling by increasing worker count.

Gameplay:
1. Player observes a baseline run with one worker.
2. Opens Worker Manager.
3. Changes worker count to two.
4. Runs the same request workload.
5. Compares completion time and waiting time.
6. Experiments with a larger worker count.
Victory Condition: Find a configuration that meets the specified response-time target without exceeding the resource budget.

Important Model Assumption: Each worker represents a thread capable of handling an independent request. Workloads contain simulated waiting and CPU phases. Extra workers can overlap waiting phases, but CPU-intensive work is limited by the modeled CPU capacity.

Edge Cases:
- Zero workers: requests remain queued; explain why.
- Worker count exceeds permitted limit: reject invalid configuration.
- Adding workers beyond useful capacity: show diminishing returns or resource contention.
- Same completion times for different configurations: explain resource limitations instead of claiming every extra thread increases performance.
- Requests finish in a different order: preserve correct request identities and display results consistently.
- Retry: reset the entire workload and use identical initial conditions for fair comparison.
Unlock: Database installation.
Concepts: Persistent data, read/write operations, database connections, resource contention.

Scenario: MeOS needs to save information instead of producing temporary responses.

Objective: Connect a database and successfully perform read and write operations.

Gameplay:
1. Player approaches an empty database slot.
2. Installs a database.
3. Connects the server to the database using an interaction button.
4. Opens a simple Database Terminal.
5. Creates a sample record.
6. Reads the saved record.
7. Runs a request workload that accesses the database.
Victory Condition: Successfully store and retrieve a record, with the server connected to the database.

Database Model:
- Records represented as simple key/value objects.
- Simulated database latency.
- Separate read and write request types.
- One primary database.
- Serialized conflicting writes.
Edge Cases:
- Read missing record: show "Record not found."
- Write existing key: apply a clearly defined update/upsert rule.
- Database disconnected: request fails with connection error.
- Invalid or empty key: reject with helpful feedback.
- Two conflicting writes: process using a deterministic ordering rule.
- Storage capacity reached: prevent additional inserts and show a full-storage error.
- Player returns to previous level: prevent unwanted database state from altering the earlier scripted scenario.
Unlock: Infrastructure expansion.
Concepts: Read replicas, caching, load balancing, scalability, architectural tradeoffs.

Scenario: MeOS is experiencing increased read traffic, and database access has become a bottleneck.

Objective: Select a valid architecture improvement and measure its effects.

Gameplay:
1. Player observes baseline workload metrics.
2. Two or more infrastructure slots become available.
3. Player selects one available upgrade.
4. Available upgrades:
   - Add a read replica.
   - Add a cache.
   - Add another application server.
5. The simulated system runs again.
6. Player compares results and evaluates tradeoffs.
Victory Condition: Meet the mission's performance target while staying within the available budget.

Simulation Rules:
- A read replica can serve eligible read requests.
- Writes always go to the primary database.
- Replica updates are delayed by a configurable simulated replication lag.
- A cache serves matching cached reads more quickly.
- Cache misses access the underlying database.
- An additional application server increases request-handling capacity but does not automatically eliminate database bottlenecks.
Edge Cases:
- Reading immediately after writing to a replica: stale data may be returned; explain replication lag.
- Database unavailable: dependent reads/writes must fail unless an explicitly modeled fallback applies.
- Cache miss: fetch from database and populate cache.
- Cache invalidation: updated data must not be silently treated as fresh.
- Adding a second server without a load balancer or routing mechanism: additional server receives no traffic until properly connected.
- Insufficient budget: disable unaffordable upgrades and explain the cost.
- Player chooses a less effective option: show actual consequences and permit retry.
- No single configuration meets the target: ensure this is not possible for the predefined mission.
Unlock: Final diagnostic challenge.
Concepts: Bottleneck diagnosis, performance troubleshooting, tradeoff evaluation.

Scenario: MeOS becomes slow during a sudden increase in traffic.

The player must investigate the system rather than simply choose an upgrade.

Objective: Diagnose the actual bottleneck and restore acceptable performance.

Gameplay:
1. Player receives a system alert.
2. Opens Monitoring Terminal.
3. Reviews CPU utilization, worker queue, database load, and response time.
4. Examines at least two possible causes.
5. Selects an intervention.
6. Runs a verification workload.
7. Receives a final explanation of the observed behavior.
Initial MVP Scenario: CPU utilization is low, but database latency is high because a read-heavy workload is bottlenecked on the primary database.

Possible Interventions:
- Increase workers.
- Increase application-server capacity.
- Add a read replica.
- Add a cache.
Victory Condition: Select and implement an improvement that reduces the modeled bottleneck and meets the defined response-time target.

Edge Cases:
- Incorrect intervention: no automatic victory; show measured result and explanation.
- Multiple valid interventions: accept any that meet the outcome requirements.
- Repeated failures: permit unlimited retries without punishment.
- Missing database connection: detect configuration problem separately.
- Player makes multiple changes: evaluate the combined configuration, not just the most recent action.
- Completed mission replayed: preserve achievement without duplicating unlocks.
Ending: MeOS becomes operational. Player receives a final summary of concepts learned and unlocks the ability to replay all missions.
The application shall display one 2D laboratory containing a player, NPC, workstations, component slots, and interactive objects.
The player shall navigate between accessible positions without moving through walls or obstacles.
Interactive objects shall open corresponding learning panels when selected or approached.
A centralized mission system shall manage mission status, progression, objectives, completion, and replay.
A shared deterministic simulation engine shall model requests, queues, workers, resource constraints, database operations, and performance outcomes.
Players shall be able to modify permitted system components according to the current mission.
The game shall animate request movement, processing, completion, and major system-state transitions.
The game shall display simulated metrics including:
- Completed requests.
- Failed requests.
- Queue waiting time.
- Total workload completion time.
- Average request latency.
- Database operations.
- Resource utilization.
Metrics must be calculated from simulation events rather than invented solely for visual presentation.
Every completed action or simulation run shall provide a brief explanation connecting the decision to the observed result.
The application shall save completed missions and essential progress locally.
Previously completed missions shall remain accessible.
All application functionality shall work without internet access.
The application shall support accessible labels for essential controls, readable text, reduced-motion alternatives, and non-color-only status indicators.
Optional sound effects shall be locally bundled and independently mutable. Muted audio shall not prevent mission completion.
MeOS shall separate the simulation model from its visual presentation.

Game World: SpriteKit renders the player, environment, and machines.

User Interface: SwiftUI renders menus, choices, objectives, configuration tools, and results.

Simulation Engine: Pure Swift processes workloads and generates simulation events.

Mission Engine: Determines active scenarios, permitted actions, objectives, and progression.

Persistence Layer: Saves local progress using Codable and a versioned local file or UserDefaults.
GameState
- Current mission.
- Completed missions.
- Player position.
- Configured components.
- Active simulation status.
SystemNode
- Unique identifier.
- Node type.
- Capacity.
- Connections.
- Active state.
Request
- Unique identifier.
- Request type.
- Arrival time.
- Processing requirements.
- Current status.
Worker
- Unique identifier.
- Assigned request.
- Availability.
- Resource requirements.
Database
- Records.
- Capacity.
- Read/write service times.
- Replica synchronization state.
SimulationResult
- Completed count.
- Failed count.
- Average latency.
- Workload completion time.
- Resource utilization.
- Educational explanation identifiers.
The MVP shall use a deterministic, discrete-event or fixed-tick simulation.

It shall not depend on actual CPU scheduling or device performance.

Given identical initial state, workload, and configuration, the simulation shall produce identical results.

Randomized workloads must use a stored seed to support reproducibility.
The following invariants shall be enforced:
1. Every request has one unique identity.
2. A request cannot be completed twice.
3. A worker cannot execute more than its permitted concurrent workload.
4. Completed, failed, queued, and running requests must reconcile with total submitted requests.
5. Database reads must follow defined consistency rules.
6. System resources cannot have negative capacity.
7. Components cannot route requests through nonexistent connections.
8. Metrics cannot contain negative durations or non-finite values.
9. Simulation state must remain independent of frame rate.
10. Educational explanations must match the actual simulated outcome.
Display:
- MeOS title.
- Start / Continue button.
- Short premise.
- Sound setting.
- Credits.
Display:
- Main 2D environment.
- Player character.
- Current objective.
- Interactive objects.
- Mission progress.
- Pause/menu control.
Display:
- Selected component.
- Permitted configuration actions.
- Available resources.
- Clear confirmation/control buttons.
- Back/close control.
Display:
- Current request queue.
- Active workers.
- Connected infrastructure.
- Start/Pause/Reset controls.
- Concise live metrics.
Display:
- Mission outcome.
- Before/after metrics where relevant.
- What happened.
- Why it happened.
- Retry / Continue controls.
Scenario	Required Behavior
App closes during a mission	Restore a stable checkpoint or restart the current mission
App goes to background	Pause simulation safely
User rapidly taps controls	Ignore or serialize duplicate commands
User presses Run repeatedly	Prevent overlapping simulation runs
User resets during execution	Cancel active run and restore baseline
User changes configuration during a run	Require pause/reset or queue changes for next run
Saved state is corrupted	Recover defaults without crashing
App updates with older save data	Use versioned migration or safe fallback
Character reaches a wall	Stop at valid walkable position
Destination is inaccessible	Reject movement gracefully
Interactive object is blocked	Offer an accessible direct interaction route
Device rotates	Use fixed landscape experience or valid responsive layout
System sound is muted	Continue gameplay normally
Reduced Motion is enabled	Replace nonessential animations with state changes
Player never completes a mission	Allow unlimited retries
Device runs slowly	Keep simulation deterministic despite reduced FPS
Negative or invalid configuration	Reject before starting
Missing local assets	Use placeholder visuals or safe fallback
App has no internet	All features remain functional
- Target 60 FPS on supported iPads under normal conditions.
- Remain playable at lower frame rates.
- Avoid unnecessary SpriteKit physics calculations.
- Avoid recreating textures during every frame.
- Keep background simulations paused when not visible.
- No known reproducible crashes in the supported simulator and test device configurations.
- No progress loss after normal application termination.
- Deterministic mission results.
- Safe handling of all invalid simulation configurations.
- The first interaction shall occur within approximately 15 seconds.
- Basic gameplay shall be understandable without external instructions.
- First meaningful learning outcome should occur within one minute.
- The primary experience must be demonstrable within three minutes.
- Every objective must be discoverable without guesswork.
- Prefer a submission ZIP below 25 MB.
- Use texture atlases and reusable pixel-art assets.
- Use compressed short audio clips.
- Do not bundle large videos, language models, or virtual machines.
- No dependency on downloaded resources.
All interface labels, tutorials, dialogues, documentation, and learning content shall be in English.
- Xcode 27 or later.
- Swift.
- SwiftUI.
- SpriteKit.
- iPadOS application target.
```
MeOS/
├── MeOSApp.swift
├── Models/
│   ├── GameState.swift
│   ├── SystemNode.swift
│   ├── Request.swift
│   ├── Worker.swift
│   └── SimulationResult.swift
├── Engine/
│   ├── SimulationEngine.swift
│   ├── RequestScheduler.swift
│   ├── DatabaseSimulator.swift
│   ├── MissionEngine.swift
│   └── PerformanceCalculator.swift
├── Game/
│   ├── GameScene.swift
│   ├── PlayerController.swift
│   ├── InteractionManager.swift
│   └── AnimationManager.swift
├── Views/
│   ├── HomeView.swift
│   ├── GameView.swift
│   ├── MissionView.swift
│   ├── SystemPanelView.swift
│   └── ResultsView.swift
├── Persistence/
│   └── ProgressStore.swift
├── Resources/
│   ├── Assets.xcassets/
│   ├── Missions.json
│   ├── Dialogues.json
│   └── Sounds/
└── Tests/
    ├── SimulationTests.swift
    ├── MissionTests.swift
    └── PersistenceTests.swift
```
- Use one reusable SpriteKit scene for the laboratory.
- Create reusable component views for servers, databases, and infrastructure slots.
- Keep mission-specific configuration in local data structures.
- Do not duplicate complete scenes for each level.
- Use one central source of truth for simulation state.
- Use a consistent game-state lifecycle: ready, running, paused, completed, failed.
- Do not place business logic inside animation callbacks.
- Do not use real-time timers as the source of truth for simulation correctness.
The implementation must test:
- Request queue ordering.
- Worker capacity limits.
- Correct request completion accounting.
- Zero-worker behavior.
- Performance metrics.
- Read and write correctness.
- Replica lag behavior.
- Cache hit/miss behavior.
- Invalid system configuration.
- Mission unlocking.
- Saved progress restoration.
Test:
1. Launch the app and enter the world.
2. Interact with a server.
3. Complete Level 1.
4. Unlock Level 2.
5. Modify workers and execute the simulation.
6. Install the database.
7. Add an infrastructure component.
8. Complete the final mission.
9. Close and reopen the app.
10. Verify completed levels and replay availability.
The MVP is accepted as ready when:
- All five missions are playable.
- No internet connection is required.
- All core assets are bundled.
- The project builds using the required Xcode version.
- The app launches in a clean environment.
- The complete three-minute demonstration path works.
- Major interaction and simulation edge cases are tested.
- All external assets and open-source contributions are credited.
- The ZIP contains the complete Xcode project and required resources.
- The ZIP is at most 500 MB.
- All user-facing content is in English.
Implement a playable room, animated character, movement, interaction detection, and NPC dialogue.

Deliverable: Player can walk to and interact with a server.
Implement requests, workers, queuing, deterministic event processing, and performance calculations.

Deliverable: A functional single-worker and multiworker simulation.
Connect the simulation engine to the SpriteKit world and SwiftUI challenge panels.

Deliverable: Complete onboarding and two playable missions.
Implement a small in-memory database model, replica/cache behavior, infrastructure slots, and architecture decisions.

Deliverable: Levels 3 and 4.
Implement a diagnostic scenario, monitoring panel, evaluation rules, and completion sequence.

Deliverable: Full story experience.
Add save/load, sound controls, accessibility support, testing, credits, offline validation, and packaging.

Deliverable: Submission-ready ZIP.
The default experience must demonstrate the project's educational value quickly.

0:00–0:20 — Introduction

Player enters MeOS, meets the System Engineer, and learns that the server is overloaded.

0:20–0:55 — First Simulation

Player runs the single-worker server and sees requests queue up.

0:55–1:35 — First Improvement

Player adds another worker and compares performance.

1:35–2:15 — Database Discovery

Player installs a database and sees read/write requests.

2:15–3:00 — Scaling Decision

Player chooses a system upgrade, observes the resulting metrics, and receives an explanation.

The full game may take longer, but the first three minutes must deliver a satisfying and understandable educational experience.
Metric	MVP Target
Time to first interaction	Under 15 seconds
Time to first learning outcome	Under 60 seconds
Playable missions	5
Reusable 2D world	1
Main controllable character	1
Core simulation engine	1
Offline functionality	100%
Reproducible simulation results	100% for identical inputs
Progress restoration	Works after relaunch
Critical crashes	0 known
Preferred ZIP size	Under 25 MB
Submission ZIP size	At most 500 MB
These are product targets, not claims of tested performance.
After the MVP, MeOS could introduce:
- Operating-system memory allocation and paging.
- Scheduling algorithms such as Round Robin and Shortest Job First.
- Thread synchronization, mutexes, and deadlocks.
- Indexes, transactions, and isolation levels.
- Database sharding and consistency tradeoffs.
- Load balancing and distributed systems.
- Network routing and packet delivery.
- Procedurally generated troubleshooting challenges.
- Free-build Architect Mode.
All future features should integrate into the shared simulation engine and existing world instead of requiring entirely separate games.
MeOS is not a virtual machine, real server infrastructure, or a database administration tool.

It is a small, interactive 2D world that models computing concepts through meaningful decisions and observable consequences.

The MVP succeeds when a beginner can enter the game, experience a system bottleneck, make an architectural change, observe its effect, understand why it worked or failed, and leave with a clearer mental model of how computing systems operate.

Product tagline:

MeOS - Don't just learn how computers work. Step inside one.
