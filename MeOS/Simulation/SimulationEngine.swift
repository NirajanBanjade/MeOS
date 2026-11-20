import Foundation

struct SimulationEngine: Sendable {
    private struct RawEvent {
        var time: SimulationTime
        var requestID: RequestID?
        var nodeID: NodeID?
        var payload: SimulationEventPayload
        var insertion: Int
    }

    private enum ActionKind {
        case arrival
        case phaseFinished(worker: Int, phase: Int)
        case cpuFinished(worker: Int, phase: Int)
    }

    private struct Action {
        var time: SimulationTime
        var priority: Int
        var requestID: RequestID
        var kind: ActionKind
        var insertion: Int
    }

    func run(
        initialState: GameState,
        workload: [Request],
        configuration: SimulationConfiguration
    ) throws -> SimulationResult {
        try validate(initialState: initialState, workload: workload, configuration: configuration)
        if workload.contains(where: { $0.type != .standard }) {
            return runDatabase(initialState: initialState, workload: workload, configuration: configuration)
        }
        return runStandard(initialState: initialState, workload: workload, configuration: configuration)
    }

    func snapshot(
        initialState: GameState,
        workload: [Request],
        configuration: SimulationConfiguration,
        throughEvent eventCount: Int
    ) throws -> SimulationSnapshot {
        let result = try run(initialState: initialState, workload: workload, configuration: configuration)
        let count = min(max(eventCount, 0), result.orderedEvents.count)
        return SimulationSnapshot(
            initialState: initialState,
            workload: workload,
            configuration: configuration,
            presentedEventCount: count,
            presentedEvents: Array(result.orderedEvents.prefix(count))
        )
    }

    func resume(from snapshot: SimulationSnapshot) throws -> SimulationResult {
        let result = try run(
            initialState: snapshot.initialState,
            workload: snapshot.workload,
            configuration: snapshot.configuration
        )
        guard Array(result.orderedEvents.prefix(snapshot.presentedEventCount)) == snapshot.presentedEvents else {
            throw SimulationValidationError.overlappingRun
        }
        return result
    }

    func reset(from snapshot: SimulationSnapshot) throws -> SimulationResult {
        try run(initialState: snapshot.initialState, workload: snapshot.workload, configuration: snapshot.configuration)
    }

    private func validate(
        initialState: GameState,
        workload: [Request],
        configuration: SimulationConfiguration
    ) throws {
        guard initialState.simulationLifecycle != .running else {
            throw SimulationValidationError.overlappingRun
        }
        guard (0...4).contains(configuration.workerCount) else {
            throw SimulationValidationError.workerCountOutOfRange(configuration.workerCount)
        }
        for (name, value) in [
            ("CPU capacity", configuration.cpuCapacity),
            ("queue capacity", configuration.queueCapacity),
            ("database capacity", initialState.database.capacity)
        ] where value < 0 {
            throw SimulationValidationError.negativeCapacity(field: name)
        }
        for (name, value) in [
            ("database read time", initialState.database.readTimeMilliseconds),
            ("database write time", initialState.database.writeTimeMilliseconds),
            ("replica lag", configuration.replicaLagMilliseconds),
            ("cache hit time", configuration.cacheHitMilliseconds)
        ] where value < 0 {
            throw SimulationValidationError.negativeCapacity(field: name)
        }

        var requestIDs = Set<RequestID>()
        for request in workload {
            guard requestIDs.insert(request.id).inserted else {
                throw SimulationValidationError.duplicateRequestID(request.id)
            }
            guard request.arrivalTimeMilliseconds >= 0,
                  request.phases.allSatisfy({ $0.durationMilliseconds >= 0 }) else {
                throw SimulationValidationError.negativeDuration(requestID: request.id)
            }
            switch request.type {
            case .databaseRead(let key, _), .databaseWrite(let key, _):
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SimulationValidationError.invalidDatabaseKey(requestID: request.id)
                }
            case .standard:
                break
            }
        }

        var nodeIDs = Set<NodeID>()
        for node in configuration.nodes {
            guard nodeIDs.insert(node.id).inserted else {
                throw SimulationValidationError.duplicateNodeID(node.id)
            }
            guard node.capacity >= 0 else {
                throw SimulationValidationError.negativeCapacity(field: "node \(node.id.rawValue) capacity")
            }
        }
        for node in configuration.nodes {
            for connection in node.connections where !nodeIDs.contains(connection) {
                throw SimulationValidationError.nonexistentRoute(from: node.id, to: connection)
            }
        }
        for request in workload {
            if let destination = request.destinationNodeID, !nodeIDs.contains(destination) {
                throw SimulationValidationError.nonexistentDestination(requestID: request.id, nodeID: destination)
            }
        }
    }

    private func runStandard(
        initialState: GameState,
        workload: [Request],
        configuration: SimulationConfiguration
    ) -> SimulationResult {
        var requests = Dictionary(uniqueKeysWithValues: workload.map { request in
            var copy = request
            copy.status = .pending
            return (copy.id, copy)
        })
        var workers = (0..<configuration.workerCount).map {
            Worker(id: WorkerID(rawValue: String(format: "worker-%02d", $0 + 1)))
        }
        var actions: [Action] = []
        var actionInsertion = 0
        var rawEvents: [RawEvent] = []
        var eventInsertion = 0
        var waitingQueue: [RequestID] = []
        var cpuQueue: [(ready: SimulationTime, requestID: RequestID, worker: Int, phase: Int)] = []
        var activeCPU = 0

        func emit(_ time: SimulationTime, _ requestID: RequestID?, _ payload: SimulationEventPayload, nodeID: NodeID? = nil) {
            rawEvents.append(RawEvent(time: time, requestID: requestID, nodeID: nodeID, payload: payload, insertion: eventInsertion))
            eventInsertion += 1
        }
        func schedule(_ time: SimulationTime, _ priority: Int, _ requestID: RequestID, _ kind: ActionKind) {
            actions.append(Action(time: time, priority: priority, requestID: requestID, kind: kind, insertion: actionInsertion))
            actionInsertion += 1
        }

        for request in workload {
            schedule(request.arrivalTimeMilliseconds, 2, request.id, .arrival)
        }

        func schedulePhase(for workerIndex: Int, requestID: RequestID, phaseIndex: Int, at time: SimulationTime) {
            guard let request = requests[requestID] else { return }
            guard phaseIndex < request.phases.count else {
                requests[requestID]?.status = .completed(at: time)
                workers[workerIndex].assignedRequestID = nil
                workers[workerIndex].availableAtMilliseconds = time
                emit(time, requestID, .completed)
                return
            }
            let phase = request.phases[phaseIndex]
            emit(time, requestID, .phaseStarted(kind: phase.kind, durationMilliseconds: phase.durationMilliseconds))
            switch phase.kind {
            case .waiting:
                schedule(time + phase.durationMilliseconds, 1, requestID, .phaseFinished(worker: workerIndex, phase: phaseIndex))
            case .cpu:
                cpuQueue.append((time, requestID, workerIndex, phaseIndex))
            }
        }

        func assignWaiting(at time: SimulationTime) {
            while let workerIndex = workers.indices.first(where: { workers[$0].assignedRequestID == nil }),
                  !waitingQueue.isEmpty {
                let requestID = waitingQueue.removeFirst()
                workers[workerIndex].assignedRequestID = requestID
                requests[requestID]?.status = .running(workerID: workers[workerIndex].id)
                emit(time, requestID, .assigned(workerID: workers[workerIndex].id))
                schedulePhase(for: workerIndex, requestID: requestID, phaseIndex: 0, at: time)
            }
        }

        func startCPU(at time: SimulationTime) {
            cpuQueue.sort {
                if $0.ready != $1.ready { return $0.ready < $1.ready }
                return $0.requestID < $1.requestID
            }
            while activeCPU < configuration.cpuCapacity, !cpuQueue.isEmpty {
                let item = cpuQueue.removeFirst()
                guard let request = requests[item.requestID] else { continue }
                let duration = request.phases[item.phase].durationMilliseconds
                activeCPU += 1
                emit(time, item.requestID, .cpuAcquired)
                schedule(time + duration, 0, item.requestID, .cpuFinished(worker: item.worker, phase: item.phase))
            }
        }

        while !actions.isEmpty {
            actions.sort {
                if $0.time != $1.time { return $0.time < $1.time }
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                if $0.requestID != $1.requestID { return $0.requestID < $1.requestID }
                return $0.insertion < $1.insertion
            }
            let action = actions.removeFirst()
            let time = action.time
            switch action.kind {
            case .arrival:
                emit(time, action.requestID, .submitted)
                guard routeIsUsable(for: requests[action.requestID], nodes: configuration.nodes) else {
                    requests[action.requestID]?.status = .failed(at: time, reason: .invalidRoute)
                    emit(time, action.requestID, .failed(reason: .invalidRoute))
                    continue
                }
                if let workerIndex = workers.indices.first(where: { workers[$0].assignedRequestID == nil }) {
                    workers[workerIndex].assignedRequestID = action.requestID
                    requests[action.requestID]?.status = .running(workerID: workers[workerIndex].id)
                    emit(time, action.requestID, .assigned(workerID: workers[workerIndex].id))
                    schedulePhase(for: workerIndex, requestID: action.requestID, phaseIndex: 0, at: time)
                } else if waitingQueue.count < configuration.queueCapacity {
                    waitingQueue.append(action.requestID)
                    requests[action.requestID]?.status = .queued
                    emit(time, action.requestID, .queued(position: waitingQueue.count))
                } else {
                    requests[action.requestID]?.status = .rejected(at: time, reason: .queueFull)
                    emit(time, action.requestID, .rejected(reason: .queueFull))
                }
            case .phaseFinished(let worker, let phase):
                guard let request = requests[action.requestID], worker < workers.count else { continue }
                emit(time, action.requestID, .phaseCompleted(kind: request.phases[phase].kind))
                schedulePhase(for: worker, requestID: action.requestID, phaseIndex: phase + 1, at: time)
            case .cpuFinished(let worker, let phase):
                guard let request = requests[action.requestID], worker < workers.count else { continue }
                activeCPU = max(activeCPU - 1, 0)
                emit(time, action.requestID, .cpuReleased)
                emit(time, action.requestID, .phaseCompleted(kind: request.phases[phase].kind))
                schedulePhase(for: worker, requestID: action.requestID, phaseIndex: phase + 1, at: time)
                assignWaiting(at: time)
            }
            startCPU(at: time)
        }

        if configuration.cpuCapacity == 0 {
            for item in cpuQueue {
                requests[item.requestID]?.status = .failed(at: item.ready, reason: .noCPUCapacity)
                if item.worker < workers.count {
                    workers[item.worker].assignedRequestID = nil
                }
                emit(item.ready, item.requestID, .failed(reason: .noCPUCapacity))
            }
        }

        let events = ordered(rawEvents)
        let final = workload.compactMap { requests[$0.id] }
        return makeResult(
            requests: final,
            workers: workers,
            database: initialState.database,
            events: events,
            cpuCapacity: configuration.cpuCapacity,
            seed: configuration.seed
        )
    }

    private func runDatabase(
        initialState: GameState,
        workload: [Request],
        configuration: SimulationConfiguration
    ) -> SimulationResult {
        var database = initialState.database
        var cache = configuration.cacheEntries
        var requests = workload.map { request -> Request in
            var copy = request
            copy.status = .pending
            return copy
        }
        var rawEvents: [RawEvent] = []
        var insertion = 0
        var primaryAvailable: SimulationTime = 0
        var replicaAvailable: SimulationTime = 0
        var cacheAvailable: SimulationTime = 0
        var replicaRouteIndex = 0

        func emit(_ time: SimulationTime, _ requestID: RequestID?, _ payload: SimulationEventPayload, nodeID: NodeID? = nil) {
            rawEvents.append(RawEvent(time: time, requestID: requestID, nodeID: nodeID, payload: payload, insertion: insertion))
            insertion += 1
        }
        func applySynchronizations(through time: SimulationTime) {
            let ready = database.pendingSynchronizations
                .filter { $0.completesAtMilliseconds <= time }
                .sorted {
                    if $0.completesAtMilliseconds != $1.completesAtMilliseconds {
                        return $0.completesAtMilliseconds < $1.completesAtMilliseconds
                    }
                    return $0.key < $1.key
                }
            for synchronization in ready {
                database.replicaRecords[synchronization.key] = synchronization.value
                database.replicaSynchronizedAtMilliseconds = synchronization.completesAtMilliseconds
                emit(synchronization.completesAtMilliseconds, nil, .replicaSynchronized(key: synchronization.key), nodeID: "replica")
            }
            database.pendingSynchronizations.removeAll { $0.completesAtMilliseconds <= time }
        }

        let orderedIndices = requests.indices.sorted {
            let lhs = requests[$0]
            let rhs = requests[$1]
            if lhs.arrivalTimeMilliseconds != rhs.arrivalTimeMilliseconds {
                return lhs.arrivalTimeMilliseconds < rhs.arrivalTimeMilliseconds
            }
            return lhs.id < rhs.id
        }

        for index in orderedIndices {
            let request = requests[index]
            let arrival = request.arrivalTimeMilliseconds
            emit(arrival, request.id, .submitted)
            guard routeIsUsable(for: request, nodes: configuration.nodes) else {
                requests[index].status = .failed(at: arrival, reason: .invalidRoute)
                emit(arrival, request.id, .failed(reason: .invalidRoute))
                continue
            }
            guard database.isConnected else {
                requests[index].status = .failed(at: arrival, reason: .databaseDisconnected)
                emit(arrival, request.id, .failed(reason: .databaseDisconnected))
                continue
            }

            switch request.type {
            case .standard:
                requests[index].status = .completed(at: arrival)
                emit(arrival, request.id, .completed)
            case .databaseWrite(let rawKey, let value):
                let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let start = max(arrival, primaryAvailable)
                applySynchronizations(through: start)
                if cache[key] != nil {
                    cache.removeValue(forKey: key)
                    emit(start, request.id, .cacheInvalidated(key: key), nodeID: "cache")
                }
                guard database.isAvailable else {
                    requests[index].status = .failed(at: start, reason: .databaseUnavailable)
                    emit(start, request.id, .failed(reason: .databaseUnavailable), nodeID: "primary-database")
                    continue
                }
                let upsert = database.records[key] != nil
                guard upsert || database.records.count < database.capacity else {
                    requests[index].status = .failed(at: start, reason: .storageFull)
                    emit(start, request.id, .failed(reason: .storageFull), nodeID: "primary-database")
                    continue
                }
                emit(start, request.id, .databaseOperationStarted(kind: "write", key: key, nodeID: "primary-database"), nodeID: "primary-database")
                let completion = start + database.writeTimeMilliseconds
                primaryAvailable = completion
                database.records[key] = value
                emit(completion, request.id, .databaseWrite(key: key, value: value, wasUpsert: upsert), nodeID: "primary-database")
                if configuration.replicaEnabled {
                    database.pendingSynchronizations.append(ReplicaSynchronization(
                        key: key,
                        value: value,
                        completesAtMilliseconds: completion + configuration.replicaLagMilliseconds
                    ))
                }
                requests[index].status = .completed(at: completion)
                emit(completion, request.id, .completed)
            case .databaseRead(let rawKey, let replicaEligible):
                let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if configuration.cacheEnabled {
                    let start = max(arrival, cacheAvailable, primaryAvailable)
                    applySynchronizations(through: start)
                    if let entry = cache[key], entry.isFresh {
                        emit(start, request.id, .cacheHit(key: key), nodeID: "cache")
                        let completion = start + configuration.cacheHitMilliseconds
                        cacheAvailable = completion
                        emit(completion, request.id, .databaseRead(key: key, value: entry.value, isStale: false), nodeID: "cache")
                        requests[index].status = .completed(at: completion)
                        emit(completion, request.id, .completed)
                        continue
                    }
                    emit(start, request.id, .cacheMiss(key: key), nodeID: "cache")
                    guard database.isAvailable else {
                        requests[index].status = .failed(at: start, reason: .databaseUnavailable)
                        emit(start, request.id, .failed(reason: .databaseUnavailable), nodeID: "primary-database")
                        cacheAvailable = start
                        continue
                    }
                    let completion = start + database.readTimeMilliseconds
                    cacheAvailable = completion
                    primaryAvailable = max(primaryAvailable, completion)
                    if let value = database.records[key] {
                        cache[key] = CacheEntry(value: value, isFresh: true)
                        emit(completion, request.id, .databaseRead(key: key, value: value, isStale: false), nodeID: "primary-database")
                        requests[index].status = .completed(at: completion)
                        emit(completion, request.id, .completed)
                    } else {
                        requests[index].status = .failed(at: completion, reason: .recordNotFound)
                        emit(completion, request.id, .databaseRead(key: key, value: nil, isStale: false), nodeID: "primary-database")
                        emit(completion, request.id, .failed(reason: .recordNotFound))
                    }
                    continue
                }

                let useReplica: Bool
                switch configuration.databaseRoutingPolicy {
                case .primaryOnly:
                    useReplica = false
                case .preferReplica:
                    useReplica = replicaEligible && configuration.replicaEnabled
                case .alternatePrimaryAndReplica:
                    useReplica = replicaEligible && configuration.replicaEnabled && replicaRouteIndex.isMultiple(of: 2) == false
                    replicaRouteIndex += 1
                }
                if useReplica {
                    let start = max(arrival, replicaAvailable)
                    applySynchronizations(through: start)
                    guard database.isReplicaAvailable else {
                        requests[index].status = .failed(at: start, reason: .replicaUnavailable)
                        emit(start, request.id, .failed(reason: .replicaUnavailable), nodeID: "replica")
                        continue
                    }
                    emit(start, request.id, .databaseOperationStarted(kind: "read", key: key, nodeID: "replica"), nodeID: "replica")
                    let completion = start + database.readTimeMilliseconds
                    replicaAvailable = completion
                    let value = database.replicaRecords[key]
                    let stale = value != database.records[key]
                    emit(completion, request.id, .databaseRead(key: key, value: value, isStale: stale), nodeID: "replica")
                    if value != nil {
                        requests[index].status = .completed(at: completion)
                        emit(completion, request.id, .completed)
                    } else {
                        requests[index].status = .failed(at: completion, reason: .recordNotFound)
                        emit(completion, request.id, .failed(reason: .recordNotFound))
                    }
                } else {
                    let start = max(arrival, primaryAvailable)
                    applySynchronizations(through: start)
                    guard database.isAvailable else {
                        requests[index].status = .failed(at: start, reason: .databaseUnavailable)
                        emit(start, request.id, .failed(reason: .databaseUnavailable), nodeID: "primary-database")
                        continue
                    }
                    emit(start, request.id, .databaseOperationStarted(kind: "read", key: key, nodeID: "primary-database"), nodeID: "primary-database")
                    let completion = start + database.readTimeMilliseconds
                    primaryAvailable = completion
                    let value = database.records[key]
                    emit(completion, request.id, .databaseRead(key: key, value: value, isStale: false), nodeID: "primary-database")
                    if value != nil {
                        requests[index].status = .completed(at: completion)
                        emit(completion, request.id, .completed)
                    } else {
                        requests[index].status = .failed(at: completion, reason: .recordNotFound)
                        emit(completion, request.id, .failed(reason: .recordNotFound))
                    }
                }
            }
        }
        applySynchronizations(through: .max)

        let events = ordered(rawEvents)
        return makeResult(
            requests: requests,
            workers: [],
            database: database,
            events: events,
            cpuCapacity: configuration.cpuCapacity,
            seed: configuration.seed
        )
    }

    private func routeIsUsable(for request: Request?, nodes: [SystemNode]) -> Bool {
        guard let destination = request?.destinationNodeID else { return true }
        guard let node = nodes.first(where: { $0.id == destination && $0.isActive }) else { return false }
        guard node.type == .applicationServer else { return true }
        let servers = nodes.filter { $0.type == .applicationServer && $0.isActive }.sorted { $0.id < $1.id }
        guard servers.first?.id != destination else { return true }
        return nodes.contains { candidate in
            candidate.isActive && candidate.type == .loadBalancer && candidate.connections.contains(destination)
        }
    }

    private func ordered(_ raw: [RawEvent]) -> [SimulationEvent] {
        raw.sorted {
            if $0.time != $1.time { return $0.time < $1.time }
            let lhsPriority = eventPriority($0.payload)
            let rhsPriority = eventPriority($1.payload)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            let lhsRequest = $0.requestID?.rawValue ?? ""
            let rhsRequest = $1.requestID?.rawValue ?? ""
            if lhsRequest != rhsRequest { return lhsRequest < rhsRequest }
            let lhsNode = $0.nodeID?.rawValue ?? ""
            let rhsNode = $1.nodeID?.rawValue ?? ""
            if lhsNode != rhsNode { return lhsNode < rhsNode }
            return $0.insertion < $1.insertion
        }.enumerated().map { sequence, event in
            SimulationEvent(
                timestampMilliseconds: event.time,
                sequenceNumber: sequence,
                requestID: event.requestID,
                nodeID: event.nodeID,
                payload: event.payload
            )
        }
    }

    private func eventPriority(_ payload: SimulationEventPayload) -> Int {
        switch payload {
        case .phaseCompleted, .cpuReleased, .databaseRead, .databaseWrite, .replicaSynchronized: 0
        case .completed, .failed: 1
        case .submitted: 2
        case .rejected: 3
        case .queued: 4
        case .assigned: 5
        case .cacheHit, .cacheMiss, .cacheInvalidated, .databaseOperationStarted: 6
        case .phaseStarted, .cpuAcquired: 7
        }
    }

    private func makeResult(
        requests: [Request],
        workers: [Worker],
        database: DatabaseState,
        events: [SimulationEvent],
        cpuCapacity: Int,
        seed: UInt64
    ) -> SimulationResult {
        enum EventStatus { case pending, queued, running, completed, failed, rejected }
        var eventStatuses = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, EventStatus.pending) })
        var submittedAt: [RequestID: SimulationTime] = [:]
        var queuedAt: [RequestID: SimulationTime] = [:]
        var completedLatencies: [SimulationTime] = []
        var totalQueueWait: SimulationTime = 0
        var terminalTimes: [SimulationTime] = []
        var cpuAcquiredAt: [RequestID: [SimulationTime]] = [:]
        var measuredCPUBusy: SimulationTime = 0

        for event in events {
            guard let requestID = event.requestID else { continue }
            switch event.payload {
            case .submitted:
                submittedAt[requestID] = event.timestampMilliseconds
            case .queued:
                eventStatuses[requestID] = .queued
                queuedAt[requestID] = event.timestampMilliseconds
            case .assigned:
                eventStatuses[requestID] = .running
                if let queuedTime = queuedAt.removeValue(forKey: requestID) {
                    totalQueueWait += max(event.timestampMilliseconds - queuedTime, 0)
                }
            case .cpuAcquired:
                cpuAcquiredAt[requestID, default: []].append(event.timestampMilliseconds)
            case .cpuReleased:
                if let acquired = cpuAcquiredAt[requestID]?.first {
                    measuredCPUBusy += max(event.timestampMilliseconds - acquired, 0)
                    cpuAcquiredAt[requestID]?.removeFirst()
                }
            case .completed:
                eventStatuses[requestID] = .completed
                terminalTimes.append(event.timestampMilliseconds)
                if let arrival = submittedAt[requestID] {
                    completedLatencies.append(max(event.timestampMilliseconds - arrival, 0))
                }
            case .failed:
                eventStatuses[requestID] = .failed
                terminalTimes.append(event.timestampMilliseconds)
            case .rejected:
                eventStatuses[requestID] = .rejected
                terminalTimes.append(event.timestampMilliseconds)
            default:
                break
            }
        }

        let completed = eventStatuses.values.filter { if case .completed = $0 { true } else { false } }.count
        let failed = eventStatuses.values.filter { if case .failed = $0 { true } else { false } }.count
        let rejected = eventStatuses.values.filter { if case .rejected = $0 { true } else { false } }.count
        let queued = eventStatuses.values.filter { if case .queued = $0 { true } else { false } }.count
        let running = eventStatuses.values.filter { if case .running = $0 { true } else { false } }.count
        let completionTime = terminalTimes.max() ?? 0
        let averageLatency = completedLatencies.isEmpty
            ? 0
            : Double(completedLatencies.reduce(0, +)) / Double(completedLatencies.count)
        let databaseReads = events.filter { if case .databaseRead = $0.payload { true } else { false } }.count
        let databaseWrites = events.filter { if case .databaseWrite = $0.payload { true } else { false } }.count
        let cacheHits = events.filter { if case .cacheHit = $0.payload { true } else { false } }.count
        let cacheMisses = events.filter { if case .cacheMiss = $0.payload { true } else { false } }.count
        let replicaReads = events.filter {
            if case .databaseRead = $0.payload { return $0.nodeID == NodeID(rawValue: "replica") }
            return false
        }.count
        let utilizationDenominator = completionTime * SimulationTime(max(cpuCapacity, 0))
        let utilization = utilizationDenominator > 0 ? Double(measuredCPUBusy) / Double(utilizationDenominator) : 0

        var explanations: [String] = []
        if !requests.isEmpty,
           requests.allSatisfy({ $0.type == .standard }),
           workers.isEmpty,
           queued > 0,
           completed == 0,
           running == 0 {
            explanations.append("no-workers")
        }
        if requests.contains(where: { if case .failed(_, .noCPUCapacity) = $0.status { true } else { false } }) {
            explanations.append("no-cpu-capacity")
        }
        if rejected > 0 { explanations.append("queue-capacity-reached") }
        if totalQueueWait > 0 { explanations.append("requests-waited-in-queue") }
        if cacheHits > 0 { explanations.append("cache-reduced-latency") }
        if replicaReads > 0 { explanations.append("replica-served-reads") }
        if events.contains(where: { if case .databaseRead(_, _, true) = $0.payload { true } else { false } }) {
            explanations.append("replica-read-was-stale")
        }

        let metrics = SimulationMetrics(
            completed: completed,
            failed: failed,
            rejected: rejected,
            queued: queued,
            running: running,
            totalQueueWaitMilliseconds: totalQueueWait,
            averageLatencyMilliseconds: averageLatency.isFinite ? averageLatency : 0,
            completionTimeMilliseconds: completionTime,
            databaseReads: databaseReads,
            databaseWrites: databaseWrites,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            replicaReads: replicaReads,
            cpuUtilization: utilization.isFinite && utilization >= 0 ? utilization : 0
        )
        return SimulationResult(
            metrics: metrics,
            orderedEvents: events,
            finalRequests: requests,
            workers: workers,
            database: database,
            seed: seed,
            explanationIDs: explanations
        )
    }
}
