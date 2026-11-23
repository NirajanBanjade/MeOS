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
                && (context.result?.metrics.averageLatencyMilliseconds ?? .infinity) <= 1_000
        case .diagnosedBottleneck:
            return context.inspectedEvidenceCount >= 2
                && context.facts.contains("database-bottleneck-improved")
                && (context.result?.metrics.averageLatencyMilliseconds ?? .infinity) <= 1_000
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
