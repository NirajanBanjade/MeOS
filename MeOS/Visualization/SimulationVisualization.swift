import Foundation

struct VisualizationRun: Equatable, Sendable {
    let workload: [Request]
    let configuration: SimulationConfiguration
    let result: SimulationResult
    let baselineResult: SimulationResult?
}

enum VisualRequestStatus: String, Codable, Equatable, Sendable {
    case submitted, queued, assigned, waiting, running, database, completed, failed, rejected

    var label: String {
        switch self {
        case .submitted: "Submitted"
        case .queued: "Queued"
        case .assigned: "Assigned"
        case .waiting: "Waiting"
        case .running: "Running"
        case .database: "Database access"
        case .completed: "Completed"
        case .failed: "Failed"
        case .rejected: "Rejected"
        }
    }

    var icon: String {
        switch self {
        case .submitted: "paperplane.fill"
        case .queued: "rectangle.stack.fill"
        case .assigned: "person.badge.clock.fill"
        case .waiting: "hourglass"
        case .running: "cpu.fill"
        case .database: "externaldrive.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .rejected: "nosign"
        }
    }

    var isTerminal: Bool { self == .completed || self == .failed || self == .rejected }
}

enum VisualNodeActivity: String, Codable, Equatable, Sendable {
    case idle, active, hit, miss, stale, failed, synchronized

    var label: String {
        switch self {
        case .idle: "Idle"
        case .active: "Active"
        case .hit: "Cache hit"
        case .miss: "Cache miss"
        case .stale: "Stale read"
        case .failed: "Failed"
        case .synchronized: "Synchronized"
        }
    }
}

struct RequestRenderState: Codable, Equatable, Identifiable, Sendable {
    let id: RequestID
    var status: VisualRequestStatus
    var workerID: WorkerID?
    var queuePosition: Int?
    var nodeID: NodeID?
    var detail: String
    var timestampMilliseconds: SimulationTime
}

struct WorkerRenderState: Codable, Equatable, Identifiable, Sendable {
    let id: WorkerID
    var requestID: RequestID?
    var isUsingCPU: Bool
}

struct NodeRenderState: Codable, Equatable, Identifiable, Sendable {
    let id: NodeID
    var type: SystemNodeType
    var activity: VisualNodeActivity
    var detail: String
}

struct ArchitectureConnection: Codable, Equatable, Hashable, Sendable {
    let from: NodeID
    let to: NodeID
}

struct TimelineSegment: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(requestID.rawValue)-\(sequenceNumber)" }
    let requestID: RequestID
    let workerID: WorkerID?
    let kind: ProcessingPhaseKind
    let startMilliseconds: SimulationTime
    let durationMilliseconds: SimulationTime
    let sequenceNumber: Int
}

struct VisualizationAnnouncement: Codable, Equatable, Identifiable, Sendable {
    var id: Int { sequenceNumber }
    let sequenceNumber: Int
    let text: String
}

struct SimulationRenderState: Codable, Equatable, Sendable {
    var timestampMilliseconds: SimulationTime = 0
    var requests: [RequestID: RequestRenderState] = [:]
    var workers: [WorkerID: WorkerRenderState] = [:]
    var nodes: [NodeID: NodeRenderState] = [:]
    var connections: [ArchitectureConnection] = []
    var timeline: [TimelineSegment] = []
    var announcements: [VisualizationAnnouncement] = []
    var presentedEventCount = 0

    var orderedRequests: [RequestRenderState] { requests.values.sorted { $0.id < $1.id } }
    var orderedWorkers: [WorkerRenderState] { workers.values.sorted { $0.id < $1.id } }
    var orderedNodes: [NodeRenderState] { nodes.values.sorted { $0.id < $1.id } }
}

struct SimulationEventProjector: Equatable, Sendable {
    func baseline(workload: [Request], configuration: SimulationConfiguration) -> SimulationRenderState {
        var state = SimulationRenderState()
        state.requests = Dictionary(uniqueKeysWithValues: workload.map { request in
            (request.id, RequestRenderState(
                id: request.id,
                status: .submitted,
                workerID: nil,
                queuePosition: nil,
                nodeID: request.destinationNodeID,
                detail: "Ready",
                timestampMilliseconds: 0
            ))
        })
        state.workers = Dictionary(uniqueKeysWithValues: (0..<configuration.workerCount).map { index in
            let id = WorkerID(rawValue: String(format: "worker-%02d", index + 1))
            return (id, WorkerRenderState(id: id, requestID: nil, isUsingCPU: false))
        })
        state.nodes = Dictionary(uniqueKeysWithValues: configuration.nodes.map { node in
            (node.id, NodeRenderState(
                id: node.id,
                type: node.type,
                activity: node.isActive ? .idle : .failed,
                detail: node.isActive ? "Idle" : "Inactive"
            ))
        })
        var connections: [ArchitectureConnection] = []
        for node in configuration.nodes {
            for destination in node.connections {
                connections.append(ArchitectureConnection(from: node.id, to: destination))
            }
        }
        state.connections = connections.sorted { lhs, rhs in
            lhs.from == rhs.from ? lhs.to < rhs.to : lhs.from < rhs.from
        }
        return state
    }

    func project(
        events: ArraySlice<SimulationEvent>,
        workload: [Request],
        configuration: SimulationConfiguration
    ) -> SimulationRenderState {
        var state = baseline(workload: workload, configuration: configuration)
        for event in events.sorted(by: Self.eventOrder) { apply(event, to: &state) }
        return state
    }

    func apply(_ event: SimulationEvent, to state: inout SimulationRenderState) {
        state.timestampMilliseconds = event.timestampMilliseconds
        state.presentedEventCount += 1
        let requestID = event.requestID

        func updateRequest(
            _ status: VisualRequestStatus,
            detail: String,
            workerID: WorkerID? = nil,
            queuePosition: Int? = nil,
            nodeID: NodeID? = nil
        ) {
            guard let requestID else { return }
            var request = state.requests[requestID] ?? RequestRenderState(
                id: requestID,
                status: status,
                workerID: nil,
                queuePosition: nil,
                nodeID: nil,
                detail: detail,
                timestampMilliseconds: event.timestampMilliseconds
            )
            // Engine priority can place a same-timestamp terminal event before its
            // submitted event. Preserve the terminal truth instead of visually
            // regressing a request after completion/failure/rejection.
            if request.status.isTerminal && !status.isTerminal { return }
            request.status = status
            request.detail = detail
            request.timestampMilliseconds = event.timestampMilliseconds
            if let workerID { request.workerID = workerID }
            if let queuePosition { request.queuePosition = queuePosition }
            if let nodeID { request.nodeID = nodeID }
            state.requests[requestID] = request
        }

        func updateNode(_ id: NodeID?, activity: VisualNodeActivity, detail: String, fallbackType: SystemNodeType) {
            guard let id else { return }
            var node = state.nodes[id] ?? NodeRenderState(id: id, type: fallbackType, activity: .idle, detail: "Idle")
            node.activity = activity
            node.detail = detail
            state.nodes[id] = node
        }

        func releaseWorker() {
            guard let requestID,
                  let workerID = state.requests[requestID]?.workerID,
                  var worker = state.workers[workerID] else { return }
            worker.requestID = nil
            worker.isUsingCPU = false
            state.workers[workerID] = worker
        }

        switch event.payload {
        case .submitted:
            updateRequest(.submitted, detail: "Submitted")
        case .queued(let position):
            updateRequest(.queued, detail: "Queue position \(position)", queuePosition: position)
        case .assigned(let workerID):
            updateRequest(.assigned, detail: "Assigned to \(workerID.rawValue)", workerID: workerID)
            state.workers[workerID] = WorkerRenderState(id: workerID, requestID: requestID, isUsingCPU: false)
        case .phaseStarted(let kind, let duration):
            let status: VisualRequestStatus = kind == .waiting ? .waiting : .running
            updateRequest(status, detail: "\(kind.rawValue.capitalized) for \(duration) ms")
            if let requestID {
                state.timeline.append(TimelineSegment(
                    requestID: requestID,
                    workerID: state.requests[requestID]?.workerID,
                    kind: kind,
                    startMilliseconds: event.timestampMilliseconds,
                    durationMilliseconds: duration,
                    sequenceNumber: event.sequenceNumber
                ))
            }
        case .phaseCompleted(let kind):
            updateRequest(.running, detail: "\(kind.rawValue.capitalized) phase complete")
        case .cpuAcquired:
            updateRequest(.running, detail: "CPU acquired")
            if let requestID, let workerID = state.requests[requestID]?.workerID, var worker = state.workers[workerID] {
                worker.isUsingCPU = true
                state.workers[workerID] = worker
            }
        case .cpuReleased:
            updateRequest(.running, detail: "CPU released")
            if let requestID, let workerID = state.requests[requestID]?.workerID, var worker = state.workers[workerID] {
                worker.isUsingCPU = false
                state.workers[workerID] = worker
            }
        case .databaseOperationStarted(let kind, let key, let nodeID):
            updateRequest(.database, detail: "\(kind.capitalized) ‘\(key)’", nodeID: nodeID)
            updateNode(nodeID, activity: .active, detail: "\(kind.capitalized): \(key)", fallbackType: .primaryDatabase)
        case .databaseRead(let key, _, let isStale):
            updateRequest(.database, detail: isStale ? "Stale read: \(key)" : "Read: \(key)")
            updateNode(event.nodeID, activity: isStale ? .stale : .active, detail: isStale ? "Stale read" : "Read complete", fallbackType: .primaryDatabase)
        case .databaseWrite(let key, _, let wasUpsert):
            updateRequest(.database, detail: wasUpsert ? "Updated: \(key)" : "Created: \(key)")
            updateNode(event.nodeID, activity: .active, detail: wasUpsert ? "Upsert complete" : "Write complete", fallbackType: .primaryDatabase)
        case .replicaSynchronized(let key):
            updateNode(event.nodeID ?? "replica", activity: .synchronized, detail: "Synchronized: \(key)", fallbackType: .readReplica)
        case .cacheHit(let key):
            updateRequest(.database, detail: "Cache hit: \(key)", nodeID: event.nodeID)
            updateNode(event.nodeID ?? "cache", activity: .hit, detail: "Hit: \(key)", fallbackType: .cache)
        case .cacheMiss(let key):
            updateRequest(.database, detail: "Cache miss: \(key)", nodeID: event.nodeID)
            updateNode(event.nodeID ?? "cache", activity: .miss, detail: "Miss: \(key)", fallbackType: .cache)
        case .cacheInvalidated(let key):
            updateNode(event.nodeID ?? "cache", activity: .active, detail: "Invalidated: \(key)", fallbackType: .cache)
        case .completed:
            updateRequest(.completed, detail: "Completed")
            releaseWorker()
        case .failed(let reason):
            updateRequest(.failed, detail: Self.failureText(reason), nodeID: event.nodeID)
            updateNode(event.nodeID, activity: .failed, detail: Self.failureText(reason), fallbackType: .primaryDatabase)
            releaseWorker()
        case .rejected(let reason):
            updateRequest(.rejected, detail: reason == .queueFull ? "Queue full" : "Rejected")
            releaseWorker()
        case .unknown:
            // Preserve the timestamp and accessible audit trail only. Unknown
            // input must never invent a request, route, node, or animation.
            break
        }

        state.announcements.append(VisualizationAnnouncement(
            sequenceNumber: event.sequenceNumber,
            text: Self.announcement(for: event, state: state)
        ))
    }

    private static func eventOrder(_ lhs: SimulationEvent, _ rhs: SimulationEvent) -> Bool {
        if lhs.timestampMilliseconds != rhs.timestampMilliseconds { return lhs.timestampMilliseconds < rhs.timestampMilliseconds }
        return lhs.sequenceNumber < rhs.sequenceNumber
    }

    private static func failureText(_ reason: SimulationFailureReason) -> String {
        switch reason {
        case .databaseDisconnected: "Database connection failed"
        case .databaseUnavailable: "Database unavailable"
        case .replicaUnavailable: "Replica unavailable"
        case .recordNotFound: "Record not found"
        case .storageFull: "Storage full"
        case .invalidRoute: "Connection route failed"
        case .noCPUCapacity: "No CPU capacity"
        }
    }

    private static func announcement(for event: SimulationEvent, state: SimulationRenderState) -> String {
        let identity = event.requestID.map { "Request \($0.rawValue)" } ?? "System"
        if let requestID = event.requestID, let request = state.requests[requestID] {
            return "At \(event.timestampMilliseconds) milliseconds, \(identity): \(request.status.label), \(request.detail)."
        }
        if let nodeID = event.nodeID, let node = state.nodes[nodeID] {
            return "At \(event.timestampMilliseconds) milliseconds, \(nodeID.rawValue): \(node.activity.label), \(node.detail)."
        }
        return "At \(event.timestampMilliseconds) milliseconds, system state updated."
    }
}

enum PresentationSpeed: Double, CaseIterable, Codable, Sendable {
    case half = 0.5
    case normal = 1
    case double = 2

    var label: String { "\(rawValue.formatted(.number.precision(.fractionLength(0...1))))×" }
}

enum PresentationLifecycle: String, Codable, Equatable, Sendable {
    case ready, playing, paused, completed
}

struct SimulationPresentationSession: Equatable, Sendable {
    let events: [SimulationEvent]
    let workload: [Request]
    let configuration: SimulationConfiguration
    private(set) var eventIndex: Int
    private(set) var lifecycle: PresentationLifecycle
    private(set) var speed: PresentationSpeed
    private(set) var renderState: SimulationRenderState
    private let projector = SimulationEventProjector()

    init(events: [SimulationEvent], workload: [Request], configuration: SimulationConfiguration) {
        self.events = events.sorted {
            $0.timestampMilliseconds == $1.timestampMilliseconds
                ? $0.sequenceNumber < $1.sequenceNumber
                : $0.timestampMilliseconds < $1.timestampMilliseconds
        }
        self.workload = workload
        self.configuration = configuration
        eventIndex = 0
        lifecycle = .ready
        speed = .normal
        renderState = projector.baseline(workload: workload, configuration: configuration)
    }

    @discardableResult
    mutating func play() -> Bool {
        guard lifecycle == .ready || lifecycle == .paused else { return false }
        guard eventIndex < events.count else {
            lifecycle = .completed
            return false
        }
        lifecycle = .playing
        return true
    }

    mutating func pause() {
        guard lifecycle == .playing else { return }
        lifecycle = .paused
    }

    mutating func setSpeed(_ speed: PresentationSpeed) { self.speed = speed }

    @discardableResult
    mutating func presentNext() -> SimulationEvent? {
        guard lifecycle == .playing, eventIndex < events.count else { return nil }
        let event = events[eventIndex]
        projector.apply(event, to: &renderState)
        eventIndex += 1
        if eventIndex == events.count { lifecycle = .completed }
        return event
    }

    mutating func finishWithoutInterpolation() {
        guard lifecycle == .playing || lifecycle == .paused else { return }
        lifecycle = .playing
        while presentNext() != nil { }
    }

    mutating func reset() {
        eventIndex = 0
        lifecycle = .ready
        renderState = projector.baseline(workload: workload, configuration: configuration)
    }

    mutating func handleBackgrounding() { pause() }
}

struct DisplayMetric: Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let value: String
    let numericValue: Double
    let icon: String
}

enum SimulationMetricFormatter {
    static func metrics(from result: SimulationResult) -> [DisplayMetric] {
        let metrics = result.metrics
        return [
            DisplayMetric(id: "completed", label: "Completed", value: "\(metrics.completed)", numericValue: Double(metrics.completed), icon: "checkmark.circle.fill"),
            DisplayMetric(id: "failed", label: "Failed", value: "\(metrics.failed)", numericValue: Double(metrics.failed), icon: "xmark.octagon.fill"),
            DisplayMetric(id: "rejected", label: "Rejected", value: "\(metrics.rejected)", numericValue: Double(metrics.rejected), icon: "nosign"),
            DisplayMetric(id: "queue-wait", label: "Queue wait", value: "\(metrics.totalQueueWaitMilliseconds) ms", numericValue: Double(metrics.totalQueueWaitMilliseconds), icon: "rectangle.stack.fill"),
            DisplayMetric(id: "makespan", label: "Makespan", value: "\(metrics.completionTimeMilliseconds) ms", numericValue: Double(metrics.completionTimeMilliseconds), icon: "flag.checkered"),
            DisplayMetric(id: "latency", label: "Avg latency", value: "\(Int(metrics.averageLatencyMilliseconds.rounded())) ms", numericValue: metrics.averageLatencyMilliseconds, icon: "timer"),
            DisplayMetric(id: "database", label: "Database ops", value: "\(metrics.databaseReads + metrics.databaseWrites)", numericValue: Double(metrics.databaseReads + metrics.databaseWrites), icon: "externaldrive.fill"),
            DisplayMetric(id: "cpu", label: "CPU use", value: "\(Int((metrics.cpuUtilization * 100).rounded()))%", numericValue: metrics.cpuUtilization, icon: "cpu.fill")
        ]
    }
}

enum SimulationExplanationCatalog {
    static func text(for id: String) -> String {
        switch id {
        case "sequential-queueing", "requests-waited-in-queue": "One worker handles one request at a time, so later requests wait in the queue."
        case "concurrent-wait-overlap": "Workers overlap waiting phases, while CPU work still respects modeled capacity."
        case "no-workers": "No workers are available, so accepted requests remain queued."
        case "queue-overflow", "queue-capacity-reached": "The queue reached capacity, so later arrivals were rejected."
        case "database-disconnected": "The server has no usable database connection."
        case "database-unavailable": "The configured database route exists, but the database is unavailable."
        case "cache-benefit", "cache-reduced-latency": "Cache hits avoid repeated database service time."
        case "replica-benefit", "replica-served-reads": "Eligible reads are shared with the replica while writes remain on the primary."
        case "replica-read-was-stale": "The replica returned an older value because synchronization lag had not elapsed."
        case "cpu-contention", "no-cpu-capacity": "CPU phases wait for the modeled CPU capacity even when more workers exist."
        default: "This explanation is unavailable, but the measured event sequence and metrics remain unchanged."
        }
    }
}
