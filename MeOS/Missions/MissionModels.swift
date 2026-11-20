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
