import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MeOSShellCore
#else
@testable import MeOS
#endif

@Suite("Mission progression")
struct MissionEngineTests {
    @Test("All five complete local definitions expose the required contract")
    func definitions() throws {
        let catalog = MissionCatalog.standard
        #expect(catalog.validationIssues.isEmpty)
        #expect(catalog.definitions.map(\.id) == MissionID.allCases)
        for (index, definition) in catalog.definitions.enumerated() {
            #expect(!definition.title.isEmpty)
            #expect(!definition.learningConcepts.isEmpty)
            #expect(!definition.workload.isEmpty)
            #expect(!definition.permittedActions.isEmpty)
            #expect(!definition.objectives.isEmpty)
            #expect(!definition.resultExplanations.isEmpty)
            #expect(definition.baselineState.mission == index + 1)
            #expect(definition.prerequisite == (index == 0 ? nil : MissionID(rawValue: index)))
            #expect(definition.unlock == (index == 4 ? nil : MissionID(rawValue: index + 2)))
        }
    }

    @Test("Prerequisites, objectives, unlocks, and completion are centralized and idempotent")
    func fullProgression() throws {
        var engine = MissionEngine()
        #expect(throws: MissionEngineError.prerequisiteIncomplete(.workerConcurrency)) {
            try engine.start(.workerConcurrency)
        }

        try completeMission1(&engine)
        #expect(engine.progress.currentMissionID == .workerConcurrency)
        #expect(engine.progress.completedMissionIDs == [.sequentialProcessing])
        #expect(try completeMission1Again(&engine) == false)

        try completeMission2(&engine)
        try completeMission3(&engine)
        try completeMission4(&engine)
        try completeMission5(&engine)

        #expect(engine.progress.completedMissionIDs == Set(MissionID.allCases))
        #expect(engine.progress.currentMissionID == .systemDiagnostics)
        #expect(engine.progress.titleAwarded)
        #expect(engine.progress.lifecycle == .completed)
        #expect(try engine.complete(using: diagnosticContext()) == false)
    }

    @Test("Retry is unlimited and restores byte-equivalent baseline inputs and results")
    func retryDeterminism() throws {
        var engine = MissionEngine()
        try engine.start()
        let initial = try #require(engine.session)
        let simulator = SimulationEngine()
        let expected = try simulator.run(
            initialState: initial.state,
            workload: initial.workload,
            configuration: initial.configuration
        )

        try engine.pause()
        var changed = initial.configuration
        changed.workerCount = 2
        try engine.changeConfiguration(changed)
        for retry in 1...100 {
            try engine.retry()
            let restored = try #require(engine.session)
            #expect(restored.retryCount == retry)
            #expect(restored.state == initial.state)
            #expect(restored.workload == initial.workload)
            #expect(restored.configuration == initial.configuration)
            let actual = try simulator.run(
                initialState: restored.state,
                workload: restored.workload,
                configuration: restored.configuration
            )
            #expect(actual == expected)
        }
    }

    @Test("Replay uses a clean baseline and cannot relock or overwrite newer progress")
    func replayIsolation() throws {
        let laterNode = SystemNode(id: "cache", type: .cache)
        let progress = MissionProgress(
            currentMissionID: .systemDiagnostics,
            completedMissionIDs: Set(MissionID.allCases),
            titleAwarded: true,
            lifecycle: .completed,
            configuredComponents: [laterNode]
        )
        var engine = MissionEngine(progress: progress)
        try engine.replay(.sequentialProcessing)
        let replay = try #require(engine.session)
        #expect(replay.isReplay)
        #expect(replay.state.database.records.isEmpty)
        #expect(replay.state.configuredComponents.isEmpty)
        #expect(replay.configuration.nodes.isEmpty)

        for objective in MissionCatalog.standard.definition(for: .sequentialProcessing)!.objectives {
            try engine.markObjective(objective.id)
        }
        let result = try SimulationEngine().run(
            initialState: replay.state,
            workload: replay.workload,
            configuration: replay.configuration
        )
        let awarded = try engine.complete(using: .init(result: result, facts: ["queue-identified"]))
        #expect(!awarded)
        #expect(engine.progress.currentMissionID == .systemDiagnostics)
        #expect(engine.progress.completedMissionIDs == Set(MissionID.allCases))
        #expect(engine.progress.configuredComponents == [laterNode])
        #expect(engine.progress.titleAwarded)
    }

    @Test("Runs reject configuration mutation and backgrounding creates a stable checkpoint")
    func lifecycleEdges() throws {
        var engine = MissionEngine()
        try engine.start()
        #expect(throws: MissionEngineError.runInProgress) {
            try engine.changeConfiguration(.init(workerCount: 2))
        }
        #expect(engine.durableProgress.lifecycle == .ready)
        engine.prepareForBackground()
        #expect(engine.session?.lifecycle == .paused)
        #expect(engine.progress.lifecycle == .paused)
        #expect(engine.durableProgress.lifecycle == .paused)

        try engine.retry()
        #expect(engine.session?.lifecycle == .ready)
        try engine.start()
        try engine.retry()
        #expect(engine.session?.lifecycle == .ready)

        var interrupted = MissionProgress.initial
        interrupted.lifecycle = .running
        let restored = MissionEngine(progress: interrupted)
        #expect(restored.progress.lifecycle == .ready)
        #expect(restored.session == nil)
    }

    @Test("Missing bundled content reports a safe unavailable state")
    func missingDefinition() {
        let catalog = MissionCatalog(definitions: [])
        var engine = MissionEngine(catalog: catalog)
        #expect(!catalog.validationIssues.isEmpty)
        #expect(engine.userFacingUnavailableMessage != nil)
        #expect(throws: MissionEngineError.missionUnavailable(.sequentialProcessing)) {
            try engine.start()
        }
    }

    private func completeMission1(_ engine: inout MissionEngine) throws {
        try engine.start(.sequentialProcessing)
        for id in ["run-five", "identify-queue"] { try engine.markObjective(id) }
        let session = try #require(engine.session)
        let result = try SimulationEngine().run(initialState: session.state, workload: session.workload, configuration: session.configuration)
        #expect(try engine.complete(using: .init(result: result, facts: ["queue-identified"])))
    }

    private func completeMission1Again(_ engine: inout MissionEngine) throws -> Bool {
        let session = try #require(engine.session)
        let result = try SimulationEngine().run(initialState: MissionCatalog.standard.definition(for: .sequentialProcessing)!.baselineState, workload: session.workload, configuration: session.configuration)
        return try engine.complete(using: .init(result: result, achievedObjectiveIDs: ["run-five", "identify-queue"], facts: ["queue-identified"]))
    }

    private func completeMission2(_ engine: inout MissionEngine) throws {
        try engine.start()
        for id in ["compare-baseline", "meet-worker-target"] { try engine.markObjective(id) }
        let definition = MissionCatalog.standard.definition(for: .workerConcurrency)!
        let configuration = SimulationConfiguration(workerCount: 2, seed: definition.configuration.seed)
        let result = try SimulationEngine().run(initialState: definition.baselineState, workload: definition.workload, configuration: configuration)
        _ = try engine.complete(using: .init(result: result, workerCount: 2, resourceCost: 2))
    }

    private func completeMission3(_ engine: inout MissionEngine) throws {
        try engine.start()
        for id in ["store-record", "retrieve-record", "run-connected"] { try engine.markObjective(id) }
        _ = try engine.complete(using: .init(facts: ["database-installed", "database-connected", "record-matched", "workload-completed"]))
    }

    private func completeMission4(_ engine: inout MissionEngine) throws {
        try engine.start()
        for id in ["measure-baseline", "meet-scaling-target"] { try engine.markObjective(id) }
        _ = try engine.complete(using: .init(result: result(averageLatency: 525), resourceCost: 2))
    }

    private func completeMission5(_ engine: inout MissionEngine) throws {
        try engine.start()
        for id in ["inspect-evidence", "verify-repair"] { try engine.markObjective(id) }
        _ = try engine.complete(using: diagnosticContext())
    }

    private func diagnosticContext() -> MissionEvaluationContext {
        .init(result: result(averageLatency: 800), facts: ["database-bottleneck-improved"], inspectedEvidenceCount: 2)
    }

    private func result(averageLatency: Double) -> SimulationResult {
        SimulationResult(
            metrics: SimulationMetrics(completed: 10, failed: 0, rejected: 0, queued: 0, running: 0, totalQueueWaitMilliseconds: 0, averageLatencyMilliseconds: averageLatency, completionTimeMilliseconds: 1_000, databaseReads: 10, databaseWrites: 0, cacheHits: 9, cacheMisses: 1, replicaReads: 0, cpuUtilization: 0.1),
            orderedEvents: [], finalRequests: [], workers: [], database: .standard, seed: 1, explanationIDs: []
        )
    }
}
