import Foundation

typealias SimulationTime = Int64

struct RequestID: RawRepresentable, Codable, Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct NodeID: RawRepresentable, Codable, Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct WorkerID: RawRepresentable, Codable, Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum SimulationLifecycle: String, Codable, Equatable, Sendable {
    case ready, running, paused, completed, failed
}

struct GameState: Codable, Equatable, Sendable {
    var mission: Int
    var playerPosition: PlayerPosition
    var configuredComponents: [SystemNode]
    var simulationLifecycle: SimulationLifecycle
    var durableProgressReference: String?
    var database: DatabaseState

    init(
        mission: Int = 1,
        playerPosition: PlayerPosition = .initial,
        configuredComponents: [SystemNode] = [],
        simulationLifecycle: SimulationLifecycle = .ready,
        durableProgressReference: String? = nil,
        database: DatabaseState = .standard
    ) {
        self.mission = mission
        self.playerPosition = playerPosition
        self.configuredComponents = configuredComponents
        self.simulationLifecycle = simulationLifecycle
        self.durableProgressReference = durableProgressReference
        self.database = database
    }
}

enum SystemNodeType: String, Codable, CaseIterable, Sendable {
    case client
    case loadBalancer
    case applicationServer
    case cpu
    case primaryDatabase
    case readReplica
    case cache
}

struct SystemNode: Codable, Equatable, Identifiable, Sendable {
    let id: NodeID
    var type: SystemNodeType
    var capacity: Int
    var connections: [NodeID]
    var isActive: Bool

    init(id: NodeID, type: SystemNodeType, capacity: Int = 1, connections: [NodeID] = [], isActive: Bool = true) {
        self.id = id
        self.type = type
        self.capacity = capacity
        self.connections = connections
        self.isActive = isActive
    }
}

enum RequestType: Codable, Equatable, Sendable {
    case standard
    case databaseRead(key: String, replicaEligible: Bool)
    case databaseWrite(key: String, value: String)
}

enum ProcessingPhaseKind: String, Codable, Sendable {
    case waiting
    case cpu
}

struct ProcessingPhase: Codable, Equatable, Sendable {
    var kind: ProcessingPhaseKind
    var durationMilliseconds: SimulationTime

    static let standard: [ProcessingPhase] = [
        ProcessingPhase(kind: .waiting, durationMilliseconds: 600),
        ProcessingPhase(kind: .cpu, durationMilliseconds: 400)
    ]
}

enum RequestStatus: Codable, Equatable, Sendable {
    case pending
    case queued
    case running(workerID: WorkerID?)
    case completed(at: SimulationTime)
    case failed(at: SimulationTime, reason: SimulationFailureReason)
    case rejected(at: SimulationTime, reason: SimulationRejectionReason)

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .rejected: true
        default: false
        }
    }
}

struct Request: Codable, Equatable, Identifiable, Sendable {
    let id: RequestID
    var type: RequestType
    var arrivalTimeMilliseconds: SimulationTime
    var phases: [ProcessingPhase]
    var status: RequestStatus
    var destinationNodeID: NodeID?

    init(
        id: RequestID,
        type: RequestType = .standard,
        arrivalTimeMilliseconds: SimulationTime = 0,
        phases: [ProcessingPhase]? = nil,
        status: RequestStatus = .pending,
        destinationNodeID: NodeID? = nil
    ) {
        self.id = id
        self.type = type
        self.arrivalTimeMilliseconds = arrivalTimeMilliseconds
        self.phases = phases ?? (type == .standard ? ProcessingPhase.standard : [])
        self.status = status
        self.destinationNodeID = destinationNodeID
    }
}

struct Worker: Codable, Equatable, Identifiable, Sendable {
    let id: WorkerID
    var assignedRequestID: RequestID?
    var availableAtMilliseconds: SimulationTime
    var resourceRequirement: Int

    init(id: WorkerID, assignedRequestID: RequestID? = nil, availableAtMilliseconds: SimulationTime = 0, resourceRequirement: Int = 1) {
        self.id = id
        self.assignedRequestID = assignedRequestID
        self.availableAtMilliseconds = availableAtMilliseconds
        self.resourceRequirement = resourceRequirement
    }
}

struct ReplicaSynchronization: Codable, Equatable, Sendable {
    var key: String
    var value: String
    var completesAtMilliseconds: SimulationTime
}

struct DatabaseState: Codable, Equatable, Sendable {
    var records: [String: String]
    var capacity: Int
    var readTimeMilliseconds: SimulationTime
    var writeTimeMilliseconds: SimulationTime
    var isAvailable: Bool
    var isConnected: Bool
    var replicaRecords: [String: String]
    var isReplicaAvailable: Bool
    var replicaSynchronizedAtMilliseconds: SimulationTime
    var pendingSynchronizations: [ReplicaSynchronization]

    static let standard = DatabaseState()

    init(
        records: [String: String] = [:],
        capacity: Int = 5,
        readTimeMilliseconds: SimulationTime = 300,
        writeTimeMilliseconds: SimulationTime = 500,
        isAvailable: Bool = true,
        isConnected: Bool = true,
        replicaRecords: [String: String] = [:],
        isReplicaAvailable: Bool = true,
        replicaSynchronizedAtMilliseconds: SimulationTime = 0,
        pendingSynchronizations: [ReplicaSynchronization] = []
    ) {
        self.records = records
        self.capacity = capacity
        self.readTimeMilliseconds = readTimeMilliseconds
        self.writeTimeMilliseconds = writeTimeMilliseconds
        self.isAvailable = isAvailable
        self.isConnected = isConnected
        self.replicaRecords = replicaRecords
        self.isReplicaAvailable = isReplicaAvailable
        self.replicaSynchronizedAtMilliseconds = replicaSynchronizedAtMilliseconds
        self.pendingSynchronizations = pendingSynchronizations
    }
}

enum DatabaseRoutingPolicy: String, Codable, Sendable {
    case primaryOnly
    case preferReplica
    case alternatePrimaryAndReplica
}

struct CacheEntry: Codable, Equatable, Sendable {
    var value: String
    var isFresh: Bool
}

struct SimulationConfiguration: Codable, Equatable, Sendable {
    var workerCount: Int
    var cpuCapacity: Int
    var queueCapacity: Int
    var nodes: [SystemNode]
    var cacheEnabled: Bool
    var cacheEntries: [String: CacheEntry]
    var replicaEnabled: Bool
    var databaseRoutingPolicy: DatabaseRoutingPolicy
    var replicaLagMilliseconds: SimulationTime
    var cacheHitMilliseconds: SimulationTime
    var seed: UInt64

    init(
        workerCount: Int = 1,
        cpuCapacity: Int = 1,
        queueCapacity: Int = 10,
        nodes: [SystemNode] = [],
        cacheEnabled: Bool = false,
        cacheEntries: [String: CacheEntry] = [:],
        replicaEnabled: Bool = false,
        databaseRoutingPolicy: DatabaseRoutingPolicy = .primaryOnly,
        replicaLagMilliseconds: SimulationTime = 1_000,
        cacheHitMilliseconds: SimulationTime = 50,
        seed: UInt64 = 0
    ) {
        self.workerCount = workerCount
        self.cpuCapacity = cpuCapacity
        self.queueCapacity = queueCapacity
        self.nodes = nodes
        self.cacheEnabled = cacheEnabled
        self.cacheEntries = cacheEntries
        self.replicaEnabled = replicaEnabled
        self.databaseRoutingPolicy = databaseRoutingPolicy
        self.replicaLagMilliseconds = replicaLagMilliseconds
        self.cacheHitMilliseconds = cacheHitMilliseconds
        self.seed = seed
    }
}

enum SimulationFailureReason: String, Codable, Equatable, Sendable {
    case databaseDisconnected
    case databaseUnavailable
    case replicaUnavailable
    case recordNotFound
    case storageFull
    case invalidRoute
    case noCPUCapacity
}

enum SimulationRejectionReason: String, Codable, Equatable, Sendable {
    case queueFull
}

enum SimulationValidationError: Error, Codable, Equatable, Sendable {
    case negativeCapacity(field: String)
    case workerCountOutOfRange(Int)
    case duplicateRequestID(RequestID)
    case duplicateNodeID(NodeID)
    case duplicateWorkerID(WorkerID)
    case negativeDuration(requestID: RequestID)
    case invalidDatabaseKey(requestID: RequestID)
    case nonexistentRoute(from: NodeID, to: NodeID)
    case nonexistentDestination(requestID: RequestID, nodeID: NodeID)
    case overlappingRun
}

enum SimulationEventPayload: Codable, Equatable, Sendable {
    case submitted
    case queued(position: Int)
    case assigned(workerID: WorkerID)
    case phaseStarted(kind: ProcessingPhaseKind, durationMilliseconds: SimulationTime)
    case phaseCompleted(kind: ProcessingPhaseKind)
    case cpuAcquired
    case cpuReleased
    case databaseOperationStarted(kind: String, key: String, nodeID: NodeID)
    case databaseRead(key: String, value: String?, isStale: Bool)
    case databaseWrite(key: String, value: String, wasUpsert: Bool)
    case replicaSynchronized(key: String)
    case cacheHit(key: String)
    case cacheMiss(key: String)
    case cacheInvalidated(key: String)
    case completed
    case failed(reason: SimulationFailureReason)
    case rejected(reason: SimulationRejectionReason)
    /// Forward-compatible presentation fallback. The engine never emits this case.
    case unknown(identifier: String)
}

struct SimulationEvent: Codable, Equatable, Sendable {
    var timestampMilliseconds: SimulationTime
    var sequenceNumber: Int
    var requestID: RequestID?
    var nodeID: NodeID?
    var payload: SimulationEventPayload
}

struct SimulationMetrics: Codable, Equatable, Sendable {
    var completed: Int
    var failed: Int
    var rejected: Int
    var queued: Int
    var running: Int
    var totalQueueWaitMilliseconds: SimulationTime
    var averageLatencyMilliseconds: Double
    var completionTimeMilliseconds: SimulationTime
    var databaseReads: Int
    var databaseWrites: Int
    var cacheHits: Int
    var cacheMisses: Int
    var replicaReads: Int
    var cpuUtilization: Double
}

struct SimulationResult: Codable, Equatable, Sendable {
    var metrics: SimulationMetrics
    var orderedEvents: [SimulationEvent]
    var finalRequests: [Request]
    var workers: [Worker]
    var database: DatabaseState
    var seed: UInt64
    var explanationIDs: [String]

    var completedCount: Int { metrics.completed }
    var failedCount: Int { metrics.failed }
    var rejectedCount: Int { metrics.rejected }
}

struct SimulationSnapshot: Codable, Equatable, Sendable {
    var initialState: GameState
    var workload: [Request]
    var configuration: SimulationConfiguration
    var presentedEventCount: Int
    var presentedEvents: [SimulationEvent]
}
