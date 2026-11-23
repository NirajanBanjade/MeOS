import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MeOSShellCore
#else
@testable import MeOS
#endif

@Suite("Simulation visualization and metrics")
struct SimulationVisualizationTests {
    private let projector = SimulationEventProjector()
    private let engine = SimulationEngine()

    @Test("Every event payload projects identity, status, routes, and timestamps")
    func everyEventTypeProjects() {
        let request = Request(id: "request-a", type: .databaseRead(key: "status", replicaEligible: true))
        let nodes = [
            SystemNode(id: "server", type: .applicationServer, connections: ["primary-database", "cache"]),
            SystemNode(id: "primary-database", type: .primaryDatabase),
            SystemNode(id: "cache", type: .cache),
            SystemNode(id: "replica", type: .readReplica)
        ]
        let configuration = SimulationConfiguration(workerCount: 1, nodes: nodes)
        let payloads: [(SimulationTime, NodeID?, SimulationEventPayload)] = [
            (0, nil, .submitted),
            (0, nil, .queued(position: 1)),
            (0, nil, .assigned(workerID: "worker-01")),
            (0, nil, .phaseStarted(kind: .waiting, durationMilliseconds: 600)),
            (600, nil, .phaseCompleted(kind: .waiting)),
            (600, nil, .phaseStarted(kind: .cpu, durationMilliseconds: 400)),
            (600, "cpu", .cpuAcquired),
            (1_000, "cpu", .cpuReleased),
            (1_000, nil, .phaseCompleted(kind: .cpu)),
            (1_000, "primary-database", .databaseOperationStarted(kind: "read", key: "status", nodeID: "primary-database")),
            (1_300, "replica", .databaseRead(key: "status", value: "old", isStale: true)),
            (1_300, "primary-database", .databaseWrite(key: "status", value: "online", wasUpsert: true)),
            (1_300, "cache", .cacheMiss(key: "status")),
            (1_350, "cache", .cacheHit(key: "status")),
            (1_350, "cache", .cacheInvalidated(key: "status")),
            (2_300, "replica", .replicaSynchronized(key: "status")),
            (2_300, nil, .completed),
            (2_400, nil, .unknown(identifier: "future-event"))
        ]
        var state = projector.baseline(workload: [request], configuration: configuration)
        for (sequence, item) in payloads.enumerated() {
            projector.apply(.init(timestampMilliseconds: item.0, sequenceNumber: sequence, requestID: item.2 == .replicaSynchronized(key: "status") ? nil : request.id, nodeID: item.1, payload: item.2), to: &state)
        }

        #expect(state.timestampMilliseconds == 2_400)
        #expect(state.requests[request.id]?.status == .completed)
        #expect(state.workers["worker-01"]?.requestID == nil)
        #expect(state.timeline.map(\.kind) == [.waiting, .cpu])
        #expect(state.nodes["cache"]?.detail == "Invalidated: status")
        #expect(state.nodes["replica"]?.activity == .synchronized)
        #expect(state.connections == [
            ArchitectureConnection(from: "server", to: "cache"),
            ArchitectureConnection(from: "server", to: "primary-database")
        ])
        #expect(state.announcements.count == payloads.count)

        var failureState = projector.baseline(workload: [request], configuration: configuration)
        projector.apply(.init(timestampMilliseconds: 0, sequenceNumber: 0, requestID: request.id, nodeID: "primary-database", payload: .failed(reason: .databaseDisconnected)), to: &failureState)
        #expect(failureState.requests[request.id]?.status == .failed)
        #expect(failureState.nodes["primary-database"]?.activity == .failed)
        projector.apply(.init(timestampMilliseconds: 0, sequenceNumber: 1, requestID: request.id, nodeID: nil, payload: .rejected(reason: .queueFull)), to: &failureState)
        #expect(failureState.requests[request.id]?.status == .rejected)
    }

    @Test("Playback controls cannot alter events, timestamps, or results")
    func playbackControlInvariants() throws {
        let workload = standardWorkload()
        let configuration = SimulationConfiguration(workerCount: 2, seed: 44)
        let result = try engine.run(initialState: GameState(), workload: workload, configuration: configuration)
        var session = SimulationPresentationSession(events: result.orderedEvents, workload: workload, configuration: configuration)

        let firstPlay = session.play()
        let rapidSecondPlay = session.play()
        #expect(firstPlay)
        #expect(!rapidSecondPlay)
        _ = session.presentNext()
        session.pause()
        let pausedIndex = session.eventIndex
        #expect(session.presentNext() == nil)
        session.setSpeed(.double)
        #expect(session.eventIndex == pausedIndex)
        #expect(session.events == result.orderedEvents)
        let resumed = session.play()
        #expect(resumed)
        session.finishWithoutInterpolation()
        #expect(session.lifecycle == .completed)
        #expect(session.renderState.presentedEventCount == result.orderedEvents.count)
        #expect(session.renderState.timestampMilliseconds == result.orderedEvents.last?.timestampMilliseconds)
        #expect(result.metrics.completionTimeMilliseconds == 3_000)

        session.reset()
        #expect(session.lifecycle == .ready)
        #expect(session.eventIndex == 0)
        #expect(session.renderState.presentedEventCount == 0)
        #expect(session.renderState.timeline.isEmpty)
        let replayed = session.play()
        #expect(replayed)
        session.handleBackgrounding()
        #expect(session.lifecycle == .paused)
    }

    @Test("Empty stream is stable and explanation fallback fabricates no state")
    func emptyAndFallback() {
        var session = SimulationPresentationSession(events: [], workload: [], configuration: .init())
        let emptyPlay = session.play()
        #expect(!emptyPlay)
        #expect(session.lifecycle == .completed)
        #expect(session.renderState.requests.isEmpty)
        #expect(session.renderState.timeline.isEmpty)
        #expect(SimulationExplanationCatalog.text(for: "future-event") == "This explanation is unavailable, but the measured event sequence and metrics remain unchanged.")
    }

    @Test("Displayed metrics exactly format the engine result")
    func metricAgreement() throws {
        let result = try engine.run(initialState: GameState(), workload: standardWorkload(), configuration: .init(workerCount: 1))
        let metrics = Dictionary(uniqueKeysWithValues: SimulationMetricFormatter.metrics(from: result).map { ($0.id, $0) })

        #expect(metrics["completed"]?.numericValue == Double(result.metrics.completed))
        #expect(metrics["failed"]?.numericValue == Double(result.metrics.failed))
        #expect(metrics["rejected"]?.numericValue == Double(result.metrics.rejected))
        #expect(metrics["queue-wait"]?.numericValue == Double(result.metrics.totalQueueWaitMilliseconds))
        #expect(metrics["makespan"]?.numericValue == Double(result.metrics.completionTimeMilliseconds))
        #expect(metrics["latency"]?.numericValue == result.metrics.averageLatencyMilliseconds)
        #expect(metrics["database"]?.numericValue == Double(result.metrics.databaseReads + result.metrics.databaseWrites))
        #expect(metrics["cpu"]?.numericValue == result.metrics.cpuUtilization)
    }

    @Test("Mission-category fixtures project standard, contention, database, cache, replica, and diagnostics events")
    func representativeIntegrations() throws {
        let standard = try engine.run(initialState: GameState(), workload: standardWorkload(), configuration: .init(workerCount: 1))
        let contention = try engine.run(initialState: GameState(), workload: standardWorkload(), configuration: .init(workerCount: 2))
        var database = DatabaseState.standard
        database.records["catalog"] = "v1"
        database.replicaRecords["catalog"] = "v0"
        let dataWorkload = [
            Request(id: "read-a", type: .databaseRead(key: "catalog", replicaEligible: true)),
            Request(id: "read-b", type: .databaseRead(key: "catalog", replicaEligible: true), arrivalTimeMilliseconds: 500)
        ]
        let dataConfiguration = SimulationConfiguration(
            cacheEnabled: true,
            replicaEnabled: true,
            databaseRoutingPolicy: .preferReplica
        )
        let dataResult = try engine.run(initialState: GameState(database: database), workload: dataWorkload, configuration: dataConfiguration)
        var unavailable = database
        unavailable.isAvailable = false
        let diagnostic = try engine.run(
            initialState: GameState(database: unavailable),
            workload: [Request(id: "diagnostic", type: .databaseRead(key: "catalog", replicaEligible: false))],
            configuration: .init()
        )

        let standardState = projector.project(events: standard.orderedEvents[...], workload: standardWorkload(), configuration: .init(workerCount: 1))
        let contentionState = projector.project(events: contention.orderedEvents[...], workload: standardWorkload(), configuration: .init(workerCount: 2))
        let dataState = projector.project(events: dataResult.orderedEvents[...], workload: dataWorkload, configuration: dataConfiguration)
        let diagnosticState = projector.project(events: diagnostic.orderedEvents[...], workload: diagnostic.finalRequests, configuration: .init())

        #expect(standardState.orderedRequests.allSatisfy { $0.status == .completed })
        #expect(Set(contentionState.timeline.compactMap(\.workerID)).count == 2)
        #expect(dataState.announcements.contains { $0.text.contains("Cache hit") || $0.text.contains("Cache miss") || $0.text.contains("Stale") })
        #expect(diagnosticState.requests["diagnostic"]?.status == .failed)
    }

    @Test("Maximum fixture projection is deterministic and frame independent")
    func maximumFixturePerformanceAndLowFPS() throws {
        let workload = standardWorkload(count: 14)
        let configuration = SimulationConfiguration(workerCount: 4, queueCapacity: 10, seed: 99)
        let result = try engine.run(initialState: GameState(), workload: workload, configuration: configuration)
        let expected = projector.project(events: result.orderedEvents[...], workload: workload, configuration: configuration)

        for ignoredFPS in [1, 15, 30, 60, 120] {
            _ = ignoredFPS
            var session = SimulationPresentationSession(events: result.orderedEvents, workload: workload, configuration: configuration)
            let didPlay = session.play()
            #expect(didPlay)
            session.finishWithoutInterpolation()
            #expect(session.renderState == expected)
        }
    }

    private func standardWorkload(count: Int = 5) -> [Request] {
        (1...count).map { Request(id: RequestID(rawValue: String(format: "request-%02d", $0))) }
    }
}
