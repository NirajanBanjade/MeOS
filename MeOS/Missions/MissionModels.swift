import Foundation

enum MissionID: Int, CaseIterable, Codable, Comparable, Hashable, Identifiable, Sendable {
    case sequentialProcessing = 1
    case workerConcurrency
    case databaseStorage
    case infrastructureScaling
    case systemDiagnostics

    var id: Int { rawValue }

    static func < (lhs: MissionID, rhs: MissionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MissionObjective: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let text: String
}

enum MissionAction: String, Codable, CaseIterable, Sendable {
    case inspect, run, identifyBottleneck, configureWorkers, installDatabase, connectDatabase
    case writeRecord, readRecord, addReplica, addCache, addServer, connectRouter, inspectEvidence
}

struct MissionExplanation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let text: String
}

struct MissionEvaluationContext: Equatable, Sendable {
    var result: SimulationResult?
    var achievedObjectiveIDs: Set<String>
    var facts: Set<String>
    var workerCount: Int
    var resourceCost: Int
    var inspectedEvidenceCount: Int

    init(
        result: SimulationResult? = nil,
        achievedObjectiveIDs: Set<String> = [],
        facts: Set<String> = [],
        workerCount: Int = 0,
        resourceCost: Int = 0,
        inspectedEvidenceCount: Int = 0
    ) {
        self.result = result
        self.achievedObjectiveIDs = achievedObjectiveIDs
        self.facts = facts
        self.workerCount = workerCount
        self.resourceCost = resourceCost
        self.inspectedEvidenceCount = inspectedEvidenceCount
    }
}

enum SequentialMissionStage: String, Equatable, Sendable {
    case empty, ready, running, identifyCause, completed
}

enum SequentialWaitCause: String, CaseIterable, Equatable, Identifiable, Sendable {
    case queueWhileWorkerBusy
    case cpuWasMissing
    case requestsWereBroken

    var id: String { rawValue }

    var text: String {
        switch self {
        case .queueWhileWorkerBusy: "The request queue grew while the only worker was busy."
        case .cpuWasMissing: "The server did not have a CPU."
        case .requestsWereBroken: "The later requests were broken."
        }
    }
}

enum SequentialMissionError: Error, Equatable, Sendable {
    case negativeRequestCount(Int)
    case emptyQueue
    case runAlreadyStarted
    case runNotFinished
}

/// Mission 1's transient, event-driven presentation state. The simulator owns
/// outcomes; this value only guards the scripted interaction and projects its
/// immutable event log so closing a panel cannot restart or duplicate a run.
struct SequentialMissionRun: Equatable, Sendable {
    private(set) var stage: SequentialMissionStage = .empty
    private(set) var workload: [Request] = []
    private(set) var run: VisualizationRun?
    private(set) var presentation: SimulationPresentationSession?
    private(set) var startCount = 0
    private(set) var feedback = "Queue empty"

    var canStart: Bool { stage == .ready && !workload.isEmpty && run == nil }
    var isStartDisabled: Bool { !canStart }
    var renderState: SimulationRenderState? { presentation?.renderState }

    mutating func receiveCards(count: Int, definition: MissionDefinition) throws {
        guard count >= 0 else { throw SequentialMissionError.negativeRequestCount(count) }
        guard run == nil else { throw SequentialMissionError.runAlreadyStarted }
        if count == definition.workload.count {
            workload = definition.workload
        } else if count == 0 {
            workload = []
        } else {
            workload = (1...count).map { Request(id: RequestID(rawValue: String(format: "request-%02d", $0))) }
        }
        stage = workload.isEmpty ? .empty : .ready
        feedback = workload.isEmpty ? "Queue empty" : "\(workload.count) uniquely identified request cards ready."
    }

    @discardableResult
    mutating func start(definition: MissionDefinition, engine: SimulationEngine = SimulationEngine()) throws -> Bool {
        guard !workload.isEmpty else {
            feedback = "Queue empty"
            throw SequentialMissionError.emptyQueue
        }
        guard canStart else { return false }
        let result = try engine.run(
            initialState: definition.baselineState,
            workload: workload,
            configuration: definition.configuration
        )
        let visualization = VisualizationRun(
            workload: workload,
            configuration: definition.configuration,
            result: result,
            baselineResult: nil
        )
        run = visualization
        presentation = SimulationPresentationSession(
            events: result.orderedEvents,
            workload: workload,
            configuration: definition.configuration
        )
        startCount += 1
        stage = .running
        feedback = "Server running. Follow each request through the event log."
        return true
    }

    @discardableResult
    mutating func play() -> Bool {
        guard stage == .running, var presentation else { return false }
        let started = presentation.play()
        self.presentation = presentation
        return started
    }

    mutating func pause() {
        guard var presentation else { return }
        presentation.pause()
        self.presentation = presentation
    }

    mutating func setSpeed(_ speed: PresentationSpeed) {
        guard var presentation else { return }
        presentation.setSpeed(speed)
        self.presentation = presentation
    }

    @discardableResult
    mutating func presentNextEvent() -> SimulationEvent? {
        guard var presentation else { return nil }
        let event = presentation.presentNext()
        if presentation.lifecycle == .completed {
            stage = .identifyCause
            feedback = "All requests completed. Identify why later requests waited."
        }
        self.presentation = presentation
        return event
    }

    mutating func finishPresentation() {
        guard var presentation else { return }
        if presentation.lifecycle == .ready { _ = presentation.play() }
        presentation.finishWithoutInterpolation()
        self.presentation = presentation
        if presentation.lifecycle == .completed {
            stage = .identifyCause
            feedback = "All requests completed. Identify why later requests waited."
        }
    }

    @discardableResult
    mutating func answer(_ cause: SequentialWaitCause) throws -> Bool {
        guard stage == .identifyCause else { throw SequentialMissionError.runNotFinished }
        guard cause == .queueWhileWorkerBusy else {
            feedback = "Not quite. The event history shows later requests queued while the single worker was occupied."
            return false
        }
        stage = .completed
        feedback = "Correct. A sequential server handles one request at a time, so later arrivals wait in its queue."
        return true
    }

    mutating func reset() {
        run = nil
        presentation = nil
        stage = workload.isEmpty ? .empty : .ready
        feedback = workload.isEmpty ? "Queue empty" : "Same request cards restored for a deterministic retry."
    }
}

enum WorkerMissionStage: String, Equatable, Sendable {
    case baselineReady, running, configure, completed
}

enum WorkerMissionError: Error, Equatable, Sendable {
    case workerCountOutOfRange(Int)
    case baselineRequired
    case runInProgress
}

/// Mission 2 keeps the baseline immutable and changes only worker count for
/// comparisons. Outcomes remain owned by the deterministic simulator.
struct WorkerMissionRun: Equatable, Sendable {
    private(set) var stage: WorkerMissionStage = .baselineReady
    private(set) var selectedWorkerCount = 1
    private(set) var baselineRun: VisualizationRun?
    private(set) var comparisonRun: VisualizationRun?
    private(set) var presentation: SimulationPresentationSession?
    private(set) var feedback = "Run the saved one-worker workload before changing workers."

    var currentRun: VisualizationRun? { comparisonRun ?? baselineRun }
    var renderState: SimulationRenderState? { presentation?.renderState }
    var resourceCost: Int { selectedWorkerCount }
    var canConfigure: Bool { stage == .configure }
    var canRun: Bool { stage == .baselineReady || stage == .configure }

    mutating func selectWorkerCount(_ count: Int) throws {
        guard (0...4).contains(count) else { throw WorkerMissionError.workerCountOutOfRange(count) }
        guard stage != .running else {
            feedback = "This run is active. Finish it, then choose workers for the next reset."
            throw WorkerMissionError.runInProgress
        }
        guard baselineRun != nil else {
            feedback = "Run the one-worker baseline first so the comparison stays fair."
            throw WorkerMissionError.baselineRequired
        }
        selectedWorkerCount = count
        comparisonRun = nil
        presentation = nil
        feedback = count > 2
            ? "\(count) workers cost \(count) units, above the two-unit victory budget; the run remains observable."
            : "\(count) worker\(count == 1 ? "" : "s") selected for the identical workload."
    }

    @discardableResult
    mutating func start(
        definition: MissionDefinition,
        engine: SimulationEngine = SimulationEngine()
    ) throws -> Bool {
        guard canRun else { return false }
        if baselineRun == nil, selectedWorkerCount != 1 { throw WorkerMissionError.baselineRequired }

        var configuration = definition.configuration
        configuration.workerCount = selectedWorkerCount
        let result = try engine.run(
            initialState: definition.baselineState,
            workload: definition.workload,
            configuration: configuration
        )
        let run = VisualizationRun(
            workload: definition.workload,
            configuration: configuration,
            result: result,
            baselineResult: baselineRun?.result
        )
        if baselineRun == nil { baselineRun = run }
        else { comparisonRun = run }
        presentation = SimulationPresentationSession(
            events: result.orderedEvents,
            workload: definition.workload,
            configuration: configuration
        )
        stage = .running
        feedback = "Running \(selectedWorkerCount) worker\(selectedWorkerCount == 1 ? "" : "s") from the same request IDs, phases, arrivals, and seed."
        return true
    }

    @discardableResult
    mutating func play() -> Bool {
        guard var presentation else { return false }
        let started = presentation.play()
        self.presentation = presentation
        return started
    }

    mutating func pause() {
        guard var presentation else { return }
        presentation.pause()
        self.presentation = presentation
    }

    @discardableResult
    mutating func presentNextEvent() -> SimulationEvent? {
        guard var presentation else { return nil }
        let event = presentation.presentNext()
        self.presentation = presentation
        if presentation.lifecycle == .completed { evaluateFinishedRun() }
        return event
    }

    @discardableResult
    mutating func finishPresentation() -> Bool {
        guard var presentation else { return false }
        if presentation.lifecycle == .ready { _ = presentation.play() }
        presentation.finishWithoutInterpolation()
        self.presentation = presentation
        guard presentation.lifecycle == .completed else { return false }
        evaluateFinishedRun()
        return stage == .completed
    }

    mutating func reset() {
        stage = .baselineReady
        selectedWorkerCount = 1
        baselineRun = nil
        comparisonRun = nil
        presentation = nil
        feedback = "Exact Mission 1 request IDs, arrivals, phases, and seed restored for a fair retry."
    }

    private mutating func evaluateFinishedRun() {
        guard let run = currentRun else { return }
        if comparisonRun == nil {
            stage = .configure
            feedback = "Baseline saved: 1 worker, 5,000 ms makespan, and 3,000 ms average latency. Now compare another worker count."
            return
        }

        let metrics = run.result.metrics
        if selectedWorkerCount == 2,
           resourceCost <= 2,
           metrics.completed == 5,
           metrics.completionTimeMilliseconds <= 3_200 {
            stage = .completed
            feedback = "Target met. Two workers overlap waiting, while one modeled CPU serializes CPU phases."
        } else {
            stage = .configure
            switch selectedWorkerCount {
            case 0:
                feedback = "No workers are available, so all accepted requests remain queued and no progress occurs."
            case 1:
                feedback = "One worker reproduces the baseline; there is no added concurrency."
            case 3...4:
                feedback = "More workers show diminishing returns because one modeled CPU serializes CPU work; \(selectedWorkerCount) resource units also exceed the two-unit budget."
            default:
                feedback = "This configuration did not meet every measured target."
            }
        }
    }
}

enum DatabaseMissionError: Error, Equatable, Sendable {
    case databaseNotInstalled
    case emptyKey
    case emptyValue
}

enum DatabaseOperationKind: String, Equatable, Sendable {
    case write = "Write"
    case read = "Read"
    case workload = "Mixed workload"
}

struct DatabaseOperationFeedback: Equatable, Sendable {
    let kind: DatabaseOperationKind
    let message: String
    let icon: String
    let latencyMilliseconds: SimulationTime
    let succeeded: Bool
}

/// Mission 3's transient checkpoint. Each terminal command runs through the
/// deterministic engine and commits its returned database value atomically.
struct DatabaseMissionRun: Equatable, Sendable {
    private(set) var isInstalled = false
    private(set) var isConnected = false
    private(set) var database: DatabaseState
    private(set) var didWriteScriptedRecord = false
    private(set) var didReadScriptedRecord = false
    private(set) var workloadRun: VisualizationRun?
    private(set) var lastOperationRun: VisualizationRun?
    private(set) var feedback: DatabaseOperationFeedback?
    private(set) var operationSequence = 0

    init(database: DatabaseState? = nil) {
        var baseline = database ?? .standard
        baseline.isConnected = false
        self.database = baseline
    }

    var capacityUsed: Int { database.records.count }
    var capacity: Int { database.capacity }
    var isComplete: Bool {
        isInstalled && isConnected && didWriteScriptedRecord && didReadScriptedRecord
            && workloadRun?.result.metrics.completed == workloadRun?.workload.count
    }

    mutating func install() {
        guard !isInstalled else { return }
        isInstalled = true
        feedback = DatabaseOperationFeedback(
            kind: .write,
            message: "Primary database installed. Connect the Server before sending requests.",
            icon: "externaldrive.badge.checkmark",
            latencyMilliseconds: 0,
            succeeded: true
        )
    }

    mutating func connect() throws {
        guard isInstalled else { throw DatabaseMissionError.databaseNotInstalled }
        guard !isConnected else { return }
        isConnected = true
        database.isConnected = true
        feedback = DatabaseOperationFeedback(
            kind: .write,
            message: "Server connected to the primary database.",
            icon: "cable.connector",
            latencyMilliseconds: 0,
            succeeded: true
        )
    }

    @discardableResult
    mutating func write(key rawKey: String, value rawValue: String, engine: SimulationEngine = SimulationEngine()) throws -> SimulationResult {
        guard isInstalled else { throw DatabaseMissionError.databaseNotInstalled }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DatabaseMissionError.emptyKey }
        guard !value.isEmpty else { throw DatabaseMissionError.emptyValue }
        operationSequence += 1
        let request = Request(
            id: RequestID(rawValue: String(format: "terminal-write-%03d", operationSequence)),
            type: .databaseWrite(key: key, value: value)
        )
        let run = try execute([request], engine: engine)
        commit(run)
        let succeeded = run.result.metrics.completed == 1
        if succeeded, key == "status", value == "online" { didWriteScriptedRecord = true }
        feedback = feedbackFor(run.result, kind: .write, key: key, value: value)
        return run.result
    }

    @discardableResult
    mutating func read(key rawKey: String, engine: SimulationEngine = SimulationEngine()) throws -> SimulationResult {
        guard isInstalled else { throw DatabaseMissionError.databaseNotInstalled }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DatabaseMissionError.emptyKey }
        operationSequence += 1
        let request = Request(
            id: RequestID(rawValue: String(format: "terminal-read-%03d", operationSequence)),
            type: .databaseRead(key: key, replicaEligible: false)
        )
        let run = try execute([request], engine: engine)
        commit(run)
        if run.result.orderedEvents.contains(where: {
            if case .databaseRead("status", "online", false) = $0.payload { return true }
            return false
        }) { didReadScriptedRecord = true }
        feedback = feedbackFor(run.result, kind: .read, key: key, value: nil)
        return run.result
    }

    @discardableResult
    mutating func runConnectedWorkload(definition: MissionDefinition, engine: SimulationEngine = SimulationEngine()) throws -> VisualizationRun {
        guard isInstalled else { throw DatabaseMissionError.databaseNotInstalled }
        let run = try execute(definition.workload, seed: definition.configuration.seed, engine: engine)
        commit(run)
        workloadRun = run
        feedback = feedbackFor(run.result, kind: .workload, key: "status", value: nil)
        return run
    }

    mutating func reset(to definition: MissionDefinition) {
        self = DatabaseMissionRun(database: definition.baselineState.database)
    }

    private func execute(
        _ workload: [Request],
        seed: UInt64 = 43_003,
        engine: SimulationEngine
    ) throws -> VisualizationRun {
        let databaseNode = SystemNode(id: "primary-database", type: .primaryDatabase, capacity: database.capacity)
        let server = SystemNode(
            id: "server",
            type: .applicationServer,
            connections: isConnected ? [databaseNode.id] : []
        )
        let configuration = SimulationConfiguration(nodes: [server, databaseNode], seed: seed)
        let result = try engine.run(
            initialState: GameState(mission: 3, configuredComponents: isInstalled ? [databaseNode] : [], database: database),
            workload: workload,
            configuration: configuration
        )
        return VisualizationRun(workload: workload, configuration: configuration, result: result, baselineResult: nil)
    }

    private mutating func commit(_ run: VisualizationRun) {
        database = run.result.database
        database.isConnected = isConnected
        lastOperationRun = run
    }

    private func feedbackFor(
        _ result: SimulationResult,
        kind: DatabaseOperationKind,
        key: String,
        value: String?
    ) -> DatabaseOperationFeedback {
        let latency = result.orderedEvents.map(\.timestampMilliseconds).max() ?? 0
        if let failure = result.finalRequests.compactMap({ request -> SimulationFailureReason? in
            if case .failed(_, let reason) = request.status { return reason }
            return nil
        }).first {
            let message: String
            switch failure {
            case .databaseDisconnected: message = "Connection error: connect the Server to the database first."
            case .databaseUnavailable: message = "Database unavailable. No record was changed."
            case .recordNotFound: message = "Record not found."
            case .storageFull: message = "Storage full: upsert an existing key or remove an entry before inserting another."
            default: message = "The database request failed: \(failure.rawValue)."
            }
            return DatabaseOperationFeedback(kind: kind, message: message, icon: "xmark.octagon.fill", latencyMilliseconds: latency, succeeded: false)
        }

        let message: String
        switch kind {
        case .write:
            let wasUpsert = result.orderedEvents.contains { if case .databaseWrite(_, _, true) = $0.payload { true } else { false } }
            message = wasUpsert
                ? "Updated \(key) = \(value ?? "") by upsert. No extra storage slot was used."
                : "Created \(key) = \(value ?? "")."
        case .read:
            let found = result.orderedEvents.compactMap { event -> String? in
                if case .databaseRead(_, let value, _) = event.payload { return value }
                return nil
            }.first ?? ""
            message = "Read \(key) = \(found)."
        case .workload:
            message = "Connected workload complete: \(result.metrics.databaseWrites) write and \(result.metrics.databaseReads) read."
        }
        return DatabaseOperationFeedback(kind: kind, message: message, icon: "checkmark.circle.fill", latencyMilliseconds: latency, succeeded: true)
    }
}

enum InfrastructureUpgrade: String, CaseIterable, Equatable, Identifiable, Sendable {
    case readReplica
    case cache
    case secondServer
    case routing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readReplica: "Read Replica"
        case .cache: "Cache"
        case .secondServer: "Second App Server"
        case .routing: "Load-balancing Route"
        }
    }

    var cost: Int {
        switch self {
        case .readReplica: 3
        case .cache, .secondServer: 2
        case .routing: 1
        }
    }

    var explanation: String {
        switch self {
        case .readReplica: "Splits eligible reads deterministically between the primary and replica; writes remain primary-only."
        case .cache: "The first matching read misses and populates the cache; later fresh reads cost 50 ms."
        case .secondServer: "Adds request-handling capacity, but receives no traffic until a route is connected."
        case .routing: "Connects incoming traffic to both app servers; the shared primary database can still bottleneck reads."
        }
    }
}

enum InfrastructureMissionStage: String, Equatable, Sendable {
    case baselineReady, configure, results, completed
}

enum InfrastructureMissionError: Error, Equatable, Sendable {
    case baselineRequired
    case upgradeRequired
    case insufficientBudget(required: Int, available: Int)
    case routingRequiresSecondServer
}

/// Mission 4 changes an explicit system graph, then measures the exact same
/// ten-request input. The simulator remains the sole owner of outcomes.
struct InfrastructureMissionRun: Equatable, Sendable {
    static let budget = 3

    private(set) var stage: InfrastructureMissionStage = .baselineReady
    private(set) var selectedUpgrades: Set<InfrastructureUpgrade> = []
    private(set) var baselineRun: VisualizationRun?
    private(set) var comparisonRun: VisualizationRun?
    private(set) var feedback = "Measure the ten-read primary-database baseline before buying an upgrade."

    var resourceCost: Int { selectedUpgrades.reduce(0) { $0 + $1.cost } }
    var availableBudget: Int { Self.budget - resourceCost }
    var isVictorious: Bool { stage == .completed }

    func canAfford(_ upgrade: InfrastructureUpgrade) -> Bool {
        selectedUpgrades.contains(upgrade) || upgrade.cost <= availableBudget
    }

    func unavailableReason(for upgrade: InfrastructureUpgrade) -> String? {
        if selectedUpgrades.contains(upgrade) { return nil }
        if upgrade == .routing && !selectedUpgrades.contains(.secondServer) {
            return "Add the second app server before connecting its route."
        }
        guard canAfford(upgrade) else {
            return "Costs \(upgrade.cost); only \(availableBudget) budget remains."
        }
        return nil
    }

    mutating func select(_ upgrade: InfrastructureUpgrade) throws {
        guard baselineRun != nil else { throw InfrastructureMissionError.baselineRequired }
        guard !selectedUpgrades.contains(upgrade) else { return }
        if upgrade == .routing && !selectedUpgrades.contains(.secondServer) {
            throw InfrastructureMissionError.routingRequiresSecondServer
        }
        guard upgrade.cost <= availableBudget else {
            throw InfrastructureMissionError.insufficientBudget(required: upgrade.cost, available: availableBudget)
        }
        selectedUpgrades.insert(upgrade)
        comparisonRun = nil
        stage = .configure
        feedback = "\(upgrade.title) added for \(upgrade.cost) budget. Run the unchanged workload to measure it."
    }

    @discardableResult
    mutating func run(
        definition: MissionDefinition,
        engine: SimulationEngine = SimulationEngine()
    ) throws -> VisualizationRun {
        if baselineRun == nil {
            let configuration = configuration(for: [])
            let result = try engine.run(
                initialState: definition.baselineState,
                workload: definition.workload,
                configuration: configuration
            )
            let run = VisualizationRun(workload: definition.workload, configuration: configuration, result: result, baselineResult: nil)
            baselineRun = run
            stage = .configure
            feedback = "Baseline measured: 1,650 ms average latency and 3,000 ms completion time on one serialized primary database."
            return run
        }

        guard !selectedUpgrades.isEmpty else { throw InfrastructureMissionError.upgradeRequired }
        let configuration = configuration(for: selectedUpgrades)
        let workload = routedWorkload(definition.workload, upgrades: selectedUpgrades)
        let result = try engine.run(
            initialState: definition.baselineState,
            workload: workload,
            configuration: configuration
        )
        let run = VisualizationRun(workload: workload, configuration: configuration, result: result, baselineResult: baselineRun?.result)
        comparisonRun = run
        evaluate(result.metrics)
        return run
    }

    mutating func reset() {
        self = InfrastructureMissionRun()
    }

    private mutating func evaluate(_ metrics: SimulationMetrics) {
        if resourceCost <= Self.budget,
           metrics.completed == 10,
           metrics.failed == 0,
           metrics.rejected == 0,
           metrics.averageLatencyMilliseconds <= 1_000 {
            stage = .completed
            if selectedUpgrades.contains(.cache) {
                feedback = "Target met. One database miss populated the cache, then nine 50 ms hits reduced average latency."
            } else {
                feedback = "Target met. Eligible reads were split across two independently serialized database nodes."
            }
        } else {
            stage = .results
            if selectedUpgrades == [.secondServer] {
                feedback = "The second server received no traffic because no load-balancing route connects it. Reset and try another graph."
            } else if selectedUpgrades.isSuperset(of: [.secondServer, .routing]) {
                feedback = "Both servers received routed traffic, but every read still serialized on the same primary database, so latency did not improve."
            } else {
                feedback = "This measured graph did not meet the 1,000 ms target. Reset and try another upgrade."
            }
        }
    }

    private func configuration(for upgrades: Set<InfrastructureUpgrade>) -> SimulationConfiguration {
        let primary = SystemNode(id: "primary-database", type: .primaryDatabase)
        var serverConnections: [NodeID] = [primary.id]
        var nodes = [SystemNode(id: "client", type: .client, connections: ["server-1"])]

        if upgrades.contains(.cache) {
            serverConnections.insert("cache", at: 0)
            nodes.append(SystemNode(id: "cache", type: .cache, connections: [primary.id]))
        }
        if upgrades.contains(.readReplica) {
            serverConnections.append("replica")
            nodes.append(SystemNode(id: "replica", type: .readReplica))
        }
        nodes.append(SystemNode(id: "server-1", type: .applicationServer, connections: serverConnections))
        if upgrades.contains(.secondServer) {
            nodes.append(SystemNode(id: "server-2", type: .applicationServer, connections: serverConnections))
        }
        if upgrades.contains(.routing) {
            nodes[0].connections = ["router"]
            nodes.append(SystemNode(id: "router", type: .loadBalancer, connections: ["server-1", "server-2"]))
        }
        nodes.append(primary)

        return SimulationConfiguration(
            nodes: nodes,
            cacheEnabled: upgrades.contains(.cache),
            replicaEnabled: upgrades.contains(.readReplica),
            databaseRoutingPolicy: upgrades.contains(.readReplica) ? .alternatePrimaryAndReplica : .primaryOnly,
            seed: 44_004
        )
    }

    private func routedWorkload(_ workload: [Request], upgrades: Set<InfrastructureUpgrade>) -> [Request] {
        guard upgrades.isSuperset(of: [.secondServer, .routing]) else { return workload }
        return workload.enumerated().map { index, request in
            var routed = request
            routed.destinationNodeID = index.isMultiple(of: 2) ? "server-1" : "server-2"
            return routed
        }
    }
}

enum DiagnosticEvidence: String, CaseIterable, Equatable, Identifiable, Sendable {
    case cpu, workerQueue, database, responseAndArchitecture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU pressure"
        case .workerQueue: "Worker queue"
        case .database: "Database load and latency"
        case .responseAndArchitecture: "Response and architecture"
        }
    }
}

enum DiagnosticIntervention: String, CaseIterable, Equatable, Identifiable, Sendable {
    case increasedWorkers, increasedServerCapacity, readReplica, cache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .increasedWorkers: "Increase Workers"
        case .increasedServerCapacity: "Increase App-Server Capacity"
        case .readReplica: "Add Read Replica"
        case .cache: "Add Cache"
        }
    }

    var cost: Int {
        switch self {
        case .increasedWorkers, .increasedServerCapacity: 1
        case .readReplica, .cache: 2
        }
    }
}

enum DiagnosticMissionStage: String, Equatable, Sendable {
    case alert, investigate, configure, results, completed
}

enum DiagnosticMissionError: Error, Equatable, Sendable {
    case baselineRequired
    case evidenceRequired
    case interventionRequired
}

struct DiagnosticSnapshot: Equatable, Sendable {
    let cpuUtilization: Double
    let queuedRequests: Int
    let queueWaitMilliseconds: SimulationTime
    let databaseOperations: Int
    let databaseLatencyMilliseconds: Double
    let averageResponseMilliseconds: Double
    let failures: Int
    let architecture: [SystemNode]

    init(result: SimulationResult, architecture: [SystemNode]) {
        cpuUtilization = result.metrics.cpuUtilization
        queuedRequests = result.metrics.queued
        queueWaitMilliseconds = result.metrics.totalQueueWaitMilliseconds
        databaseOperations = result.metrics.databaseReads + result.metrics.databaseWrites
        databaseLatencyMilliseconds = result.metrics.averageLatencyMilliseconds
        averageResponseMilliseconds = result.metrics.averageLatencyMilliseconds
        failures = result.metrics.failed + result.metrics.rejected
        self.architecture = architecture
    }
}

/// Mission 5 requires evidence inspection before applying any combination of
/// repairs. Every dashboard value, explanation, and victory decision is derived
/// from the same deterministic simulation result.
struct DiagnosticMissionRun: Equatable, Sendable {
    private(set) var stage: DiagnosticMissionStage = .alert
    private(set) var inspectedEvidence: Set<DiagnosticEvidence> = []
    private(set) var selectedInterventions: Set<DiagnosticIntervention> = []
    private(set) var baselineRun: VisualizationRun?
    private(set) var verificationRun: VisualizationRun?
    private(set) var feedback = "System alert: inspect the Monitoring Terminal before changing the architecture."
    private(set) var explanationIDs: [String] = []
    private(set) var attemptCount = 0
    var databaseConnected = true

    var resourceCost: Int { selectedInterventions.reduce(0) { $0 + $1.cost } }
    var canChooseInterventions: Bool { baselineRun != nil && inspectedEvidence.count >= 2 }
    var isVictorious: Bool { stage == .completed }
    var currentRun: VisualizationRun? { verificationRun ?? baselineRun }
    var snapshot: DiagnosticSnapshot? {
        currentRun.map { DiagnosticSnapshot(result: $0.result, architecture: $0.configuration.nodes) }
    }

    @discardableResult
    mutating func measureBaseline(
        definition: MissionDefinition,
        engine: SimulationEngine = SimulationEngine()
    ) throws -> VisualizationRun {
        if let baselineRun { return baselineRun }
        let configuration = configuration(for: [])
        var state = definition.baselineState
        state.database.isConnected = databaseConnected
        let result = try engine.run(initialState: state, workload: definition.workload, configuration: configuration)
        let run = VisualizationRun(workload: definition.workload, configuration: configuration, result: result, baselineResult: nil)
        baselineRun = run
        stage = .investigate
        if databaseConnected {
            feedback = "Baseline captured. Inspect at least two evidence panels before choosing an intervention."
            explanationIDs = []
            if result.metrics.cpuUtilization < 0.5 { explanationIDs.append("diagnostic-low-cpu") }
            if result.metrics.averageLatencyMilliseconds > 1_000 { explanationIDs.append("diagnostic-primary-database-latency") }
        } else {
            feedback = "Configuration fault: the Server has no connection to the primary database. Repair the connection before diagnosing performance."
            explanationIDs = ["diagnostic-database-disconnected"]
        }
        return run
    }

    mutating func inspect(_ evidence: DiagnosticEvidence) throws {
        guard baselineRun != nil else { throw DiagnosticMissionError.baselineRequired }
        inspectedEvidence.insert(evidence)
        if inspectedEvidence.count >= 2 {
            stage = .configure
            feedback = databaseConnected
                ? "Evidence gate complete. Low CPU and queue pressure point to serialized primary-database reads."
                : "Evidence gate complete, but the missing database connection is a configuration fault, not a latency bottleneck."
        } else {
            feedback = "Inspect one more distinct evidence panel to unlock interventions."
        }
    }

    mutating func toggle(_ intervention: DiagnosticIntervention) throws {
        guard canChooseInterventions else { throw DiagnosticMissionError.evidenceRequired }
        if selectedInterventions.remove(intervention) == nil {
            selectedInterventions.insert(intervention)
        }
        verificationRun = nil
        stage = .configure
        feedback = selectedInterventions.isEmpty
            ? "Choose one or more interventions to verify."
            : "Active configuration costs \(resourceCost) units. The full combination will be measured together."
    }

    @discardableResult
    mutating func verify(
        definition: MissionDefinition,
        engine: SimulationEngine = SimulationEngine()
    ) throws -> VisualizationRun {
        guard baselineRun != nil else { throw DiagnosticMissionError.baselineRequired }
        guard canChooseInterventions else { throw DiagnosticMissionError.evidenceRequired }
        guard !selectedInterventions.isEmpty else { throw DiagnosticMissionError.interventionRequired }

        let configuration = configuration(for: selectedInterventions)
        let workload = routedWorkload(definition.workload)
        var state = definition.baselineState
        state.database.isConnected = databaseConnected
        if selectedInterventions.contains(.readReplica) {
            state.database.replicaRecords = state.database.records
        }
        let result = try engine.run(initialState: state, workload: workload, configuration: configuration)
        let run = VisualizationRun(workload: workload, configuration: configuration, result: result, baselineResult: baselineRun?.result)
        verificationRun = run
        attemptCount += 1
        evaluate(result)
        return run
    }

    mutating func resetInterventions() throws {
        guard baselineRun != nil else { throw DiagnosticMissionError.baselineRequired }
        selectedInterventions = []
        verificationRun = nil
        stage = inspectedEvidence.count >= 2 ? .configure : .investigate
        feedback = "Stable diagnostic checkpoint restored. Evidence remains available and retries have no penalty."
        explanationIDs = databaseConnected
            ? ["diagnostic-low-cpu", "diagnostic-primary-database-latency"]
            : ["diagnostic-database-disconnected"]
    }

    private mutating func evaluate(_ result: SimulationResult) {
        let metrics = result.metrics
        let metricsAreConsistent = metrics.completed + metrics.failed + metrics.rejected + metrics.queued + metrics.running == result.finalRequests.count
            && metrics.averageLatencyMilliseconds.isFinite
            && metrics.averageLatencyMilliseconds >= 0

        guard databaseConnected else {
            stage = .results
            feedback = "Configuration fault confirmed: requests failed because the database is disconnected. This is distinct from a performance bottleneck."
            explanationIDs = ["diagnostic-database-disconnected"]
            return
        }
        guard metricsAreConsistent else {
            stage = .results
            feedback = "The measured result was incomplete or inconsistent, so MeOS did not award victory. Retry from the stable checkpoint."
            explanationIDs = ["diagnostic-inconsistent-metrics"]
            return
        }
        if metrics.completed == 10,
           metrics.failed == 0,
           metrics.rejected == 0,
           metrics.averageLatencyMilliseconds <= 1_000 {
            stage = .completed
            feedback = "Repair verified: measured average latency is \(Int(metrics.averageLatencyMilliseconds)) ms, at or below the 1,000 ms target."
            explanationIDs = metrics.cacheHits > 0
                ? ["diagnostic-cache-relieved-database", "diagnostic-target-met"]
                : ["diagnostic-replica-relieved-database", "diagnostic-target-met"]
        } else {
            stage = .results
            feedback = "The run completed, but average latency remains \(Int(metrics.averageLatencyMilliseconds)) ms. Extra app capacity did not remove the serialized primary-database bottleneck."
            explanationIDs = ["diagnostic-database-bottleneck-remains"]
        }
    }

    private func configuration(for interventions: Set<DiagnosticIntervention>) -> SimulationConfiguration {
        let primary = SystemNode(id: "primary-database", type: .primaryDatabase)
        var serverConnections: [NodeID] = databaseConnected ? [primary.id] : []
        var nodes = [SystemNode(id: "client", type: .client, connections: ["server-1"])]
        if interventions.contains(.cache) {
            serverConnections.insert("cache", at: 0)
            nodes.append(SystemNode(id: "cache", type: .cache, connections: [primary.id]))
        }
        if interventions.contains(.readReplica) {
            serverConnections.append("replica")
            nodes.append(SystemNode(id: "replica", type: .readReplica))
        }
        nodes.append(SystemNode(id: "server-1", type: .applicationServer, connections: serverConnections))
        if interventions.contains(.increasedServerCapacity) {
            nodes[0].connections = ["router"]
            nodes.append(SystemNode(id: "router", type: .loadBalancer, connections: ["server-1", "server-2"]))
            nodes.append(SystemNode(id: "server-2", type: .applicationServer, connections: serverConnections))
        }
        nodes.append(primary)
        return SimulationConfiguration(
            workerCount: interventions.contains(.increasedWorkers) ? 4 : 1,
            nodes: nodes,
            cacheEnabled: interventions.contains(.cache),
            replicaEnabled: interventions.contains(.readReplica),
            databaseRoutingPolicy: interventions.contains(.readReplica) ? .alternatePrimaryAndReplica : .primaryOnly,
            seed: 45_005
        )
    }

    private func routedWorkload(_ workload: [Request]) -> [Request] {
        guard selectedInterventions.contains(.increasedServerCapacity) else { return workload }
        return workload.enumerated().map { index, request in
            var routed = request
            routed.destinationNodeID = index.isMultiple(of: 2) ? "server-1" : "server-2"
            return routed
        }
    }
}

enum MissionVictoryRule: String, Codable, Equatable, Sendable {
    case sequentialQueueUnderstood
    case twoWorkerTarget
    case databaseRoundTrip
    case scalingTarget
    case diagnosedBottleneck

    func evaluate(_ context: MissionEvaluationContext, objectives: [MissionObjective]) -> Bool {
        let allObjectivesMet = Set(objectives.map(\.id)).isSubset(of: context.achievedObjectiveIDs)
        guard allObjectivesMet else { return false }

        switch self {
        case .sequentialQueueUnderstood:
            return context.result?.metrics.completed == 5
                && context.result?.metrics.failed == 0
                && context.facts.contains("queue-identified")
        case .twoWorkerTarget:
            return context.workerCount == 2
                && context.resourceCost <= 2
                && context.result?.metrics.completed == 5
                && (context.result?.metrics.completionTimeMilliseconds ?? .max) <= 3_200
        case .databaseRoundTrip:
            return context.facts.isSuperset(of: ["database-installed", "database-connected", "record-matched", "workload-completed"])
        case .scalingTarget:
            return context.resourceCost <= 3
                && context.result?.metrics.completed == 10
                && context.result?.metrics.failed == 0
                && context.result?.metrics.rejected == 0
                && (context.result?.metrics.averageLatencyMilliseconds ?? .infinity) <= 1_000
        case .diagnosedBottleneck:
            guard let result = context.result else { return false }
            let metrics = result.metrics
            let reconciles = metrics.completed + metrics.failed + metrics.rejected + metrics.queued + metrics.running == result.finalRequests.count
            return reconciles
                && metrics.averageLatencyMilliseconds.isFinite
                && metrics.completed == 10
                && metrics.failed == 0
                && metrics.rejected == 0
                && context.inspectedEvidenceCount >= 2
                && context.facts.contains("database-bottleneck-improved")
                && metrics.averageLatencyMilliseconds <= 1_000
        }
    }
}

struct MissionDefinition: Codable, Equatable, Identifiable, Sendable {
    let id: MissionID
    let title: String
    let learningConcepts: [String]
    let prerequisite: MissionID?
    let baselineState: GameState
    let workload: [Request]
    let configuration: SimulationConfiguration
    let permittedActions: [MissionAction]
    let objectives: [MissionObjective]
    let victoryEvaluator: MissionVictoryRule
    let resultExplanations: [MissionExplanation]
    let unlock: MissionID?
}

struct MissionCatalog: Equatable, Sendable {
    let definitions: [MissionDefinition]

    var validationIssues: [String] {
        let ids = definitions.map(\.id)
        var issues: [String] = []
        if ids.count != Set(ids).count { issues.append("Mission IDs must be unique.") }
        for id in MissionID.allCases where !ids.contains(id) {
            issues.append("Missing bundled definition for Mission \(id.rawValue).")
        }
        return issues
    }

    func definition(for id: MissionID) -> MissionDefinition? {
        definitions.first { $0.id == id }
    }

    static let standard = MissionCatalog(definitions: [
        makeSequential(), makeWorkers(), makeDatabase(), makeScaling(), makeDiagnostics()
    ])

    private static func standardRequests(count: Int) -> [Request] {
        (1...count).map { Request(id: RequestID(rawValue: String(format: "request-%02d", $0))) }
    }

    private static func objective(_ id: String, _ text: String) -> MissionObjective {
        MissionObjective(id: id, text: text)
    }

    private static func makeSequential() -> MissionDefinition {
        MissionDefinition(
            id: .sequentialProcessing,
            title: "Sequential Request Processing",
            learningConcepts: ["client/server", "requests", "queues", "sequential processing"],
            prerequisite: nil,
            baselineState: GameState(mission: 1),
            workload: standardRequests(count: 5),
            configuration: SimulationConfiguration(workerCount: 1, seed: 42_001),
            permittedActions: [.inspect, .run, .identifyBottleneck],
            objectives: [objective("run-five", "Inspect the Server to learn how requests are processed."), objective("identify-queue", "Identify why requests waited.")],
            victoryEvaluator: .sequentialQueueUnderstood,
            resultExplanations: [MissionExplanation(id: "sequential-queue", text: "The request queue grew while the only worker was busy.")],
            unlock: .workerConcurrency
        )
    }

    private static func makeWorkers() -> MissionDefinition {
        MissionDefinition(
            id: .workerConcurrency,
            title: "Worker Concurrency",
            learningConcepts: ["concurrency", "workers", "CPU contention", "diminishing returns"],
            prerequisite: .sequentialProcessing,
            baselineState: GameState(mission: 2),
            workload: standardRequests(count: 5),
            configuration: SimulationConfiguration(workerCount: 1, seed: 42_001),
            permittedActions: [.inspect, .run, .configureWorkers],
            objectives: [objective("compare-baseline", "Run the one-worker baseline."), objective("meet-worker-target", "Meet the target with two workers within budget.")],
            victoryEvaluator: .twoWorkerTarget,
            resultExplanations: [MissionExplanation(id: "cpu-limit", text: "Waiting can overlap, but workers still share modeled CPU capacity.")],
            unlock: .databaseStorage
        )
    }

    private static func makeDatabase() -> MissionDefinition {
        var database = DatabaseState.standard
        database.isConnected = false
        return MissionDefinition(
            id: .databaseStorage,
            title: "Database Storage",
            learningConcepts: ["persistent data", "reads", "writes", "connections"],
            prerequisite: .workerConcurrency,
            baselineState: GameState(mission: 3, database: database),
            workload: [
                Request(id: "write-status", type: .databaseWrite(key: "status", value: "online")),
                Request(id: "read-status", type: .databaseRead(key: "status", replicaEligible: false), arrivalTimeMilliseconds: 500)
            ],
            configuration: SimulationConfiguration(seed: 43_003),
            permittedActions: [.installDatabase, .connectDatabase, .writeRecord, .readRecord, .run],
            objectives: [objective("store-record", "Store status = online."), objective("retrieve-record", "Read the matching value."), objective("run-connected", "Complete the connected workload.")],
            victoryEvaluator: .databaseRoundTrip,
            resultExplanations: [MissionExplanation(id: "database-persistence", text: "The connected database stores data for later reads.")],
            unlock: .infrastructureScaling
        )
    }

    private static func makeScaling() -> MissionDefinition {
        var database = DatabaseState.standard
        database.records["catalog"] = "ready"
        database.replicaRecords["catalog"] = "ready"
        let workload = (1...10).map {
            Request(id: RequestID(rawValue: String(format: "catalog-read-%02d", $0)), type: .databaseRead(key: "catalog", replicaEligible: true))
        }
        return MissionDefinition(
            id: .infrastructureScaling,
            title: "Infrastructure Scaling",
            learningConcepts: ["read replicas", "caching", "load balancing", "tradeoffs"],
            prerequisite: .databaseStorage,
            baselineState: GameState(mission: 4, database: database),
            workload: workload,
            configuration: SimulationConfiguration(seed: 44_004),
            permittedActions: [.run, .addReplica, .addCache, .addServer, .connectRouter],
            objectives: [objective("measure-baseline", "Measure the read-heavy baseline."), objective("meet-scaling-target", "Reduce average latency within budget.")],
            victoryEvaluator: .scalingTarget,
            resultExplanations: [MissionExplanation(id: "database-bottleneck", text: "Choose an upgrade that reduces pressure on the primary database.")],
            unlock: .systemDiagnostics
        )
    }

    private static func makeDiagnostics() -> MissionDefinition {
        var database = DatabaseState.standard
        database.records["catalog"] = "ready"
        let workload = (1...10).map {
            Request(id: RequestID(rawValue: String(format: "diagnostic-read-%02d", $0)), type: .databaseRead(key: "catalog", replicaEligible: true))
        }
        return MissionDefinition(
            id: .systemDiagnostics,
            title: "System Diagnostics",
            learningConcepts: ["bottleneck diagnosis", "performance evidence", "tradeoff evaluation"],
            prerequisite: .infrastructureScaling,
            baselineState: GameState(mission: 5, database: database),
            workload: workload,
            configuration: SimulationConfiguration(seed: 45_005),
            permittedActions: [.inspectEvidence, .configureWorkers, .addServer, .addReplica, .addCache, .run],
            objectives: [objective("inspect-evidence", "Inspect at least two evidence panels."), objective("verify-repair", "Verify a measured repair of the database bottleneck.")],
            victoryEvaluator: .diagnosedBottleneck,
            resultExplanations: [MissionExplanation(id: "diagnostic-evidence", text: "Low CPU pressure and high database latency identify the primary bottleneck.")],
            unlock: nil
        )
    }
}
