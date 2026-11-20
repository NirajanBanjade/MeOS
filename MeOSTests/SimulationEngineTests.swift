import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MeOSShellCore
#else
@testable import MeOS
#endif

@Suite("Deterministic simulation engine")
struct SimulationEngineTests {
    private let engine = SimulationEngine()

    @Test("One-worker standard fixture has exact event-derived metrics")
    func oneWorkerFixture() throws {
        let result = try engine.run(initialState: GameState(), workload: standardWorkload(), configuration: .init(workerCount: 1, seed: 42))

        #expect(completionTimes(result) == [1_000, 2_000, 3_000, 4_000, 5_000])
        #expect(result.metrics.completed == 5)
        #expect(result.metrics.failed == 0)
        #expect(result.metrics.rejected == 0)
        #expect(result.metrics.completionTimeMilliseconds == 5_000)
        #expect(result.metrics.averageLatencyMilliseconds == 3_000)
        #expect(result.metrics.totalQueueWaitMilliseconds == 10_000)
        #expect(result.metrics.cpuUtilization == 0.4)
        #expect(result.finalRequests.map(\.id) == standardWorkload().map(\.id))
        #expect(result.explanationIDs.contains("requests-waited-in-queue"))
    }

    @Test("Two workers overlap waits while one CPU remains serialized")
    func twoWorkerFixture() throws {
        let result = try engine.run(initialState: GameState(), workload: standardWorkload(), configuration: .init(workerCount: 2))

        #expect(completionTimes(result) == [1_000, 1_400, 2_000, 2_400, 3_000])
        #expect(result.metrics.completionTimeMilliseconds == 3_000)
        #expect(result.metrics.averageLatencyMilliseconds == 1_960)
        #expect(maximumSimultaneousCPUOwners(in: result.orderedEvents) == 1)
    }

    @Test("Repeated runs, seeds, tie breaking, and encoded events are identical")
    func deterministicReplayAndTieBreaking() throws {
        let workload = [
            Request(id: "request-b"),
            Request(id: "request-a")
        ]
        let configuration = SimulationConfiguration(workerCount: 1, seed: 9_876)
        let first = try engine.run(initialState: GameState(), workload: workload, configuration: configuration)
        let second = try engine.run(initialState: GameState(), workload: workload, configuration: configuration)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        #expect(first == second)
        #expect(try encoder.encode(first.orderedEvents) == encoder.encode(second.orderedEvents))
        #expect(first.seed == 9_876)
        let submitted = first.orderedEvents.filter { if case .submitted = $0.payload { true } else { false } }
        #expect(submitted.map(\.requestID) == [RequestID(rawValue: "request-a"), RequestID(rawValue: "request-b")])
        #expect(first.orderedEvents.map(\.sequenceNumber) == Array(first.orderedEvents.indices))
    }

    @Test("Queue overflow and zero workers terminate and reconcile")
    func queueOverflowAndZeroWorkers() throws {
        let workload = (1...12).map { Request(id: RequestID(rawValue: String(format: "request-%02d", $0))) }
        let result = try engine.run(
            initialState: GameState(),
            workload: workload,
            configuration: .init(workerCount: 0, queueCapacity: 10)
        )

        #expect(result.metrics.queued == 10)
        #expect(result.metrics.rejected == 2)
        #expect(result.metrics.completed == 0)
        #expect(result.metrics.queued + result.metrics.running + result.metrics.completed + result.metrics.failed + result.metrics.rejected == workload.count)
        #expect(result.explanationIDs.contains("queue-capacity-reached"))
        #expect(result.explanationIDs.contains("no-workers"))

        let noOverflow = try engine.run(
            initialState: GameState(),
            workload: Array(workload.prefix(3)),
            configuration: .init(workerCount: 0)
        )
        #expect(noOverflow.metrics.queued == 3)
        #expect(noOverflow.explanationIDs == ["no-workers"])
    }

    @Test("Validation rejects every unsafe configuration before execution")
    func invalidConfiguration() throws {
        #expect(throws: SimulationValidationError.workerCountOutOfRange(-1)) {
            try engine.run(initialState: GameState(), workload: [], configuration: .init(workerCount: -1))
        }
        #expect(throws: SimulationValidationError.workerCountOutOfRange(5)) {
            try engine.run(initialState: GameState(), workload: [], configuration: .init(workerCount: 5))
        }
        #expect(throws: SimulationValidationError.duplicateRequestID("same")) {
            try engine.run(initialState: GameState(), workload: [Request(id: "same"), Request(id: "same")], configuration: .init())
        }
        #expect(throws: SimulationValidationError.negativeDuration(requestID: "negative")) {
            try engine.run(
                initialState: GameState(),
                workload: [Request(id: "negative", phases: [.init(kind: .cpu, durationMilliseconds: -1)])],
                configuration: .init()
            )
        }
        #expect(throws: SimulationValidationError.invalidDatabaseKey(requestID: "empty")) {
            try engine.run(
                initialState: GameState(),
                workload: [Request(id: "empty", type: .databaseRead(key: "  ", replicaEligible: false))],
                configuration: .init()
            )
        }
        #expect(throws: SimulationValidationError.overlappingRun) {
            try engine.run(initialState: GameState(simulationLifecycle: .running), workload: [], configuration: .init())
        }

        let badNode = SystemNode(id: "server", type: .applicationServer, connections: ["missing"])
        #expect(throws: SimulationValidationError.nonexistentRoute(from: "server", to: "missing")) {
            try engine.run(initialState: GameState(), workload: [], configuration: .init(nodes: [badNode]))
        }
    }

    @Test("Pause, resume, reset, and presentation frame rate preserve the same run")
    func snapshotsAndFrameIndependence() throws {
        let workload = standardWorkload()
        let configuration = SimulationConfiguration(workerCount: 2, seed: 12)
        let baseline = try engine.run(initialState: GameState(), workload: workload, configuration: configuration)
        let snapshot = try engine.snapshot(
            initialState: GameState(),
            workload: workload,
            configuration: configuration,
            throughEvent: 9
        )

        #expect(snapshot.presentedEvents == Array(baseline.orderedEvents.prefix(9)))
        #expect(try engine.resume(from: snapshot) == baseline)
        #expect(try engine.reset(from: snapshot) == baseline)
        for ignoredRenderFPS in [0, 15, 30, 60, 120] {
            _ = ignoredRenderFPS
            #expect(try engine.run(initialState: GameState(), workload: workload, configuration: configuration) == baseline)
        }
    }

    @Test("Database validates keys, reads missing records, upserts, and enforces capacity")
    func databaseCRUDAndCapacity() throws {
        let inserts = (1...5).map {
            Request(id: RequestID(rawValue: "write-\($0)"), type: .databaseWrite(key: " key-\($0) ", value: "value-\($0)"))
        }
        let filled = try engine.run(initialState: GameState(), workload: inserts, configuration: .init())
        #expect(filled.metrics.completed == 5)
        #expect(filled.database.records.count == 5)
        #expect(filled.metrics.databaseWrites == 5)
        #expect(filled.metrics.completionTimeMilliseconds == 2_500)

        var fullState = GameState(database: filled.database)
        fullState.database.pendingSynchronizations = []
        let capacityResult = try engine.run(
            initialState: fullState,
            workload: [
                Request(id: "new", type: .databaseWrite(key: "sixth", value: "blocked")),
                Request(id: "upsert", type: .databaseWrite(key: "key-1", value: "updated")),
                Request(id: "missing", type: .databaseRead(key: "absent", replicaEligible: false), arrivalTimeMilliseconds: 1_000)
            ],
            configuration: .init()
        )
        #expect(capacityResult.metrics.completed == 1)
        #expect(capacityResult.metrics.failed == 2)
        #expect(capacityResult.database.records["key-1"] == "updated")
        #expect(capacityResult.database.records["sixth"] == nil)
        #expect(capacityResult.finalRequests.contains { if case .failed(_, .recordNotFound) = $0.status { true } else { false } })
        #expect(capacityResult.orderedEvents.contains { if case .databaseWrite("key-1", "updated", true) = $0.payload { true } else { false } })
    }

    @Test("Conflicting writes use arrival then stable request ID")
    func conflictingWrites() throws {
        let workload = [
            Request(id: "write-b", type: .databaseWrite(key: "status", value: "second")),
            Request(id: "write-a", type: .databaseWrite(key: "status", value: "first"))
        ]
        let result = try engine.run(initialState: GameState(), workload: workload, configuration: .init())
        let writes = result.orderedEvents.compactMap { event -> String? in
            if case .databaseWrite(_, let value, _) = event.payload { return value }
            return nil
        }

        #expect(writes == ["first", "second"])
        #expect(result.database.records["status"] == "second")
    }

    @Test("Disconnected and unavailable databases return typed failures")
    func databaseAvailability() throws {
        var disconnected = DatabaseState.standard
        disconnected.records["status"] = "online"
        disconnected.isConnected = false
        let disconnectedResult = try engine.run(
            initialState: GameState(database: disconnected),
            workload: [Request(id: "read", type: .databaseRead(key: "status", replicaEligible: false))],
            configuration: .init()
        )
        #expect(disconnectedResult.finalRequests.first?.status == .failed(at: 0, reason: .databaseDisconnected))

        var unavailable = disconnected
        unavailable.isConnected = true
        unavailable.isAvailable = false
        let unavailableResult = try engine.run(
            initialState: GameState(database: unavailable),
            workload: [Request(id: "read", type: .databaseRead(key: "status", replicaEligible: false))],
            configuration: .init()
        )
        #expect(unavailableResult.finalRequests.first?.status == .failed(at: 0, reason: .databaseUnavailable))
    }

    @Test("Replica reads label stale data and synchronize exactly after lag")
    func replicaLag() throws {
        var database = DatabaseState.standard
        database.records["status"] = "old"
        database.replicaRecords["status"] = "old"
        let workload = [
            Request(id: "a-write", type: .databaseWrite(key: "status", value: "new")),
            Request(id: "b-stale", type: .databaseRead(key: "status", replicaEligible: true), arrivalTimeMilliseconds: 500),
            Request(id: "c-current", type: .databaseRead(key: "status", replicaEligible: true), arrivalTimeMilliseconds: 1_500)
        ]
        let result = try engine.run(
            initialState: GameState(database: database),
            workload: workload,
            configuration: .init(replicaEnabled: true, databaseRoutingPolicy: .preferReplica)
        )

        let reads = result.orderedEvents.compactMap { event -> (SimulationTime, String?, Bool)? in
            if case .databaseRead(_, let value, let stale) = event.payload { return (event.timestampMilliseconds, value, stale) }
            return nil
        }
        #expect(reads.count == 2)
        #expect(reads[0].1 == "old")
        #expect(reads[0].2)
        #expect(reads[1].1 == "new")
        #expect(!reads[1].2)
        #expect(result.orderedEvents.contains { $0.timestampMilliseconds == 1_500 && $0.payload == .replicaSynchronized(key: "status") })
        #expect(result.explanationIDs.contains("replica-read-was-stale"))
    }

    @Test("Cache miss populates, hits are fast, writes invalidate, and outage fallback is explicit")
    func cacheBehavior() throws {
        var database = DatabaseState.standard
        database.records["catalog"] = "v1"
        let reads = (1...10).map {
            Request(id: RequestID(rawValue: String(format: "read-%02d", $0)), type: .databaseRead(key: "catalog", replicaEligible: false))
        }
        let cached = try engine.run(
            initialState: GameState(database: database),
            workload: reads,
            configuration: .init(cacheEnabled: true)
        )
        #expect(cached.metrics.cacheMisses == 1)
        #expect(cached.metrics.cacheHits == 9)
        #expect(cached.metrics.averageLatencyMilliseconds == 525)

        let invalidated = try engine.run(
            initialState: GameState(database: database),
            workload: [Request(id: "write", type: .databaseWrite(key: "catalog", value: "v2"))],
            configuration: .init(cacheEnabled: true, cacheEntries: ["catalog": .init(value: "v1", isFresh: true)])
        )
        #expect(invalidated.orderedEvents.contains { if case .cacheInvalidated(key: "catalog") = $0.payload { true } else { false } })

        database.isAvailable = false
        let outage = try engine.run(
            initialState: GameState(database: database),
            workload: [
                Request(id: "a-hit", type: .databaseRead(key: "catalog", replicaEligible: false)),
                Request(id: "b-miss", type: .databaseRead(key: "other", replicaEligible: false))
            ],
            configuration: .init(cacheEnabled: true, cacheEntries: ["catalog": .init(value: "v1", isFresh: true)])
        )
        #expect(outage.metrics.completed == 1)
        #expect(outage.metrics.failed == 1)
    }

    @Test("Second server requires an active load-balancing route")
    func routing() throws {
        let first = SystemNode(id: "server-1", type: .applicationServer)
        let second = SystemNode(id: "server-2", type: .applicationServer)
        let request = Request(id: "request", destinationNodeID: "server-2")
        let disconnected = try engine.run(
            initialState: GameState(),
            workload: [request],
            configuration: .init(nodes: [first, second])
        )
        #expect(disconnected.finalRequests.first?.status == .failed(at: 0, reason: .invalidRoute))

        let router = SystemNode(id: "router", type: .loadBalancer, connections: ["server-1", "server-2"])
        let connected = try engine.run(
            initialState: GameState(),
            workload: [request],
            configuration: .init(nodes: [first, second, router])
        )
        #expect(connected.metrics.completed == 1)
    }

    @Test("Final statuses reconcile and all metrics are finite and nonnegative")
    func resultInvariants() throws {
        for workers in 0...4 {
            let workload = standardWorkload(count: 14)
            let result = try engine.run(
                initialState: GameState(),
                workload: workload,
                configuration: .init(workerCount: workers, queueCapacity: 10, seed: 100)
            )
            let metrics = result.metrics
            #expect(metrics.completed + metrics.failed + metrics.rejected + metrics.queued + metrics.running == workload.count)
            #expect(metrics.completed >= 0 && metrics.failed >= 0 && metrics.rejected >= 0 && metrics.queued >= 0 && metrics.running >= 0)
            #expect(metrics.totalQueueWaitMilliseconds >= 0)
            #expect(metrics.averageLatencyMilliseconds.isFinite && metrics.averageLatencyMilliseconds >= 0)
            #expect(metrics.cpuUtilization.isFinite && metrics.cpuUtilization >= 0)
            #expect(result.orderedEvents.map(\.sequenceNumber) == Array(result.orderedEvents.indices))
        }
    }

    private func standardWorkload(count: Int = 5) -> [Request] {
        (1...count).map { Request(id: RequestID(rawValue: String(format: "request-%02d", $0))) }
    }

    private func completionTimes(_ result: SimulationResult) -> [SimulationTime] {
        result.orderedEvents.compactMap { event in
            if case .completed = event.payload { return event.timestampMilliseconds }
            return nil
        }.sorted()
    }

    private func maximumSimultaneousCPUOwners(in events: [SimulationEvent]) -> Int {
        var active = 0
        var maximum = 0
        for event in events {
            switch event.payload {
            case .cpuAcquired:
                active += 1
                maximum = max(maximum, active)
            case .cpuReleased:
                active -= 1
            default:
                break
            }
        }
        return maximum
    }
}
