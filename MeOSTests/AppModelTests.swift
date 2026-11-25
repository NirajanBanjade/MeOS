import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MeOSShellCore
#else
@testable import MeOS
#endif

@MainActor
@Suite("App shell state")
struct AppModelTests {
    @Test("Start enters once and subsequent launch offers Continue")
    func startAndContinue() {
        let store = MemoryStore()
        let model = AppModel(store: store)
        #expect(model.primaryActionTitle == "Start")

        model.enterLaboratory()
        model.enterLaboratory()
        #expect(model.screen == .laboratory)
        #expect(model.primaryActionTitle == "Continue")
        #expect(store.saveCount == 1)

        let restored = AppModel(store: store)
        #expect(restored.primaryActionTitle == "Continue")
    }

    @Test("Rapid panel commands do not replace an open panel")
    func serializesPresentation() {
        let model = AppModel(store: MemoryStore())
        model.present(.mission)
        model.present(.credits)
        #expect(model.presentedPanel == .mission)
        model.closePanel()
        #expect(model.presentedPanel == nil)
    }

    @Test("Corrupt progress explains recovery and stays on Start")
    func recovery() {
        let model = AppModel(store: FailingStore())
        #expect(model.primaryActionTitle == "Start")
        #expect(model.recoveryMessage != nil)
    }

    @Test("Checkpoint write failures are reported to the player")
    func checkpointWriteFailure() {
        let model = AppModel(store: WriteFailingStore())
        model.enterLaboratory()
        #expect(model.recoveryMessage == "Progress could not be saved. Your latest changes may not survive if MeOS closes.")
    }

    @Test("Backgrounding pauses an active presentation and relaunch restores a safe checkpoint")
    func backgroundingAndRestore() throws {
        let store = MemoryStore()
        let model = AppModel(store: store)
        model.enterLaboratory()
        try model.receiveSequentialRequestCards()
        #expect(try model.startSequentialServer())
        #expect(model.playSequentialPresentation())

        model.handleBackgrounding()
        #expect(model.sequentialMission.presentation?.lifecycle == .paused)
        #expect(model.missionEngine.session?.lifecycle == .paused)
        #expect(store.value?.missionProgress.lifecycle == .paused)
        #expect(store.value?.missionProgress.currentMissionID == .sequentialProcessing)

        let restored = AppModel(store: store)
        #expect(restored.primaryActionTitle == "Continue")
        #expect(restored.activeMission == 1)
        #expect(restored.missionEngine.session == nil)
        #expect(restored.missionEngine.progress.lifecycle == .paused)
    }

    @Test("Every component provides beginner identity and state copy")
    func glossaryCompleteness() {
        for component in ComponentKind.allCases {
            #expect(!component.name.isEmpty)
            #expect(!component.purpose.isEmpty)
            #expect(!component.missionRole.isEmpty)
            #expect(!component.visualStates.isEmpty)
            #expect(!component.icon.isEmpty)
        }
    }

    @Test("Every presentation state can be selected without changing player position")
    func presentationReachabilityAndPositionPreservation() {
        let model = AppModel(store: MemoryStore())
        let originalPosition = model.playerPosition
        let states: [AppPanel] = [
            .mission, .sequentialMission, .workerMission, .databaseMission, .infrastructureMission, .system(.server), .results, .pause, .glossary, .credits, .settings,
            .teaching(.server), .accessibleInteractions
        ]
        for state in states {
            model.present(state)
            #expect(model.presentedPanel == state)
            model.closePanel()
            #expect(model.playerPosition == originalPosition)
        }
    }

    @Test("Completed progress, title, Continue, and replay survive relaunch")
    func completedProgressRelaunch() throws {
        let store = MemoryStore()
        let progress = MissionProgress(
            currentMissionID: .systemDiagnostics,
            completedMissionIDs: Set(MissionID.allCases),
            titleAwarded: true,
            lifecycle: .completed,
            configuredComponents: [SystemNode(id: "primary", type: .primaryDatabase)]
        )
        store.value = ShellSave(
            hasEnteredLaboratory: true,
            playerPosition: .init(x: 0.4, y: 0.6),
            soundEnabled: false,
            missionProgress: progress
        )

        let restored = AppModel(store: store)
        #expect(restored.primaryActionTitle == "Continue")
        #expect(restored.activeMission == 5)
        #expect(restored.missionEngine.progress == progress)
        #expect(restored.missionEngine.progress.titleAwarded)
        try restored.replayMission(.sequentialProcessing)
        #expect(restored.missionEngine.session?.isReplay == true)
        #expect(restored.missionEngine.progress.completedMissionIDs == Set(MissionID.allCases))
        #expect(store.value?.missionProgress == progress)
    }

    @Test("Mission 1 runs the exact fixture and requires the queue explanation")
    func sequentialMissionHappyPath() throws {
        let model = AppModel(store: MemoryStore())
        try model.receiveSequentialRequestCards()
        #expect(model.sequentialMission.workload.map(\.id.rawValue) == [
            "request-01", "request-02", "request-03", "request-04", "request-05"
        ])
        #expect(try model.startSequentialServer())
        #expect(try model.startSequentialServer() == false)
        #expect(model.sequentialMission.startCount == 1)

        let result = try #require(model.sequentialMission.run?.result)
        #expect(result.metrics.completed == 5)
        #expect(result.metrics.failed == 0)
        #expect(result.metrics.rejected == 0)
        #expect(result.metrics.completionTimeMilliseconds == 5_000)
        #expect(result.metrics.averageLatencyMilliseconds == 3_000)
        let completions = result.orderedEvents.compactMap { event -> RequestID? in
            if case .completed = event.payload { return event.requestID }
            return nil
        }
        #expect(completions == model.sequentialMission.workload.map(\.id))

        model.finishSequentialPresentation()
        #expect(model.sequentialMission.stage == .identifyCause)
        #expect(try model.answerSequentialCause(.cpuWasMissing) == false)
        #expect(model.missionEngine.progress.completedMissionIDs.isEmpty)
        #expect(try model.answerSequentialCause(.queueWhileWorkerBusy))
        #expect(model.sequentialMission.stage == .completed)
        #expect(model.missionEngine.progress.completedMissionIDs == [.sequentialProcessing])
        #expect(model.missionEngine.progress.currentMissionID == .workerConcurrency)
        #expect(model.activeMission == 2)
        #expect(throws: SequentialMissionError.runNotFinished) {
            try model.answerSequentialCause(.queueWhileWorkerBusy)
        }
        #expect(model.missionEngine.progress.completedMissionIDs.count == 1)
    }

    @Test("Mission 1 guards empty, repeated, paused, reset, overflow, and invalid inputs")
    func sequentialMissionEdges() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .sequentialProcessing))
        var mission = SequentialMissionRun()

        #expect(mission.feedback == "Queue empty")
        #expect(mission.isStartDisabled)
        #expect(throws: SequentialMissionError.emptyQueue) {
            try mission.start(definition: definition)
        }
        #expect(throws: SequentialMissionError.negativeRequestCount(-1)) {
            try mission.receiveCards(count: -1, definition: definition)
        }

        try mission.receiveCards(count: 5, definition: definition)
        #expect(try mission.start(definition: definition))
        #expect(try mission.start(definition: definition) == false)
        let firstPlay = mission.play()
        #expect(firstPlay)
        for _ in 0..<9 { _ = mission.presentNextEvent() }
        mission.pause()
        let pausedIndex = try #require(mission.presentation?.eventIndex)
        #expect(mission.presentation?.lifecycle == .paused)
        let resumed = mission.play()
        #expect(resumed)
        #expect(mission.presentation?.eventIndex == pausedIndex)
        mission.pause()

        mission.reset()
        #expect(mission.stage == .ready)
        #expect(mission.workload == definition.workload)
        #expect(mission.run == nil)
        #expect(try mission.start(definition: definition))
        mission.finishPresentation()
        let run = try #require(mission.run)
        let renderState = try #require(mission.renderState)
        let phaseEvents = run.result.orderedEvents.filter {
            if case .phaseStarted = $0.payload { return true }
            return false
        }
        #expect(renderState.timeline.count == phaseEvents.count)
        #expect(SimulationMetricFormatter.metrics(from: run.result).first { $0.id == "makespan" }?.numericValue == 5_000)
        #expect(renderState.timestampMilliseconds == run.result.orderedEvents.last?.timestampMilliseconds)

        var overflow = SequentialMissionRun()
        try overflow.receiveCards(count: 12, definition: definition)
        #expect(try overflow.start(definition: definition))
        let overflowResult = try #require(overflow.run?.result)
        #expect(overflowResult.metrics.completed == 11)
        #expect(overflowResult.metrics.rejected == 1)
        #expect(overflowResult.metrics.completed + overflowResult.metrics.rejected == 12)
        #expect(overflowResult.explanationIDs.contains("queue-capacity-reached"))
    }

    @Test("Mission 2 compares the identical fixture and unlocks Mission 3 exactly once")
    func workerMissionHappyPath() throws {
        let model = AppModel(store: completedMission1Store())
        let mission1 = try #require(MissionCatalog.standard.definition(for: .sequentialProcessing))
        let mission2 = try #require(MissionCatalog.standard.definition(for: .workerConcurrency))
        #expect(mission2.workload == mission1.workload)
        #expect(mission2.configuration.seed == mission1.configuration.seed)
        #expect(mission2.workload.map(\.arrivalTimeMilliseconds) == mission1.workload.map(\.arrivalTimeMilliseconds))
        #expect(mission2.workload.map(\.phases) == mission1.workload.map(\.phases))

        #expect(try model.startWorkerRun())
        #expect(throws: WorkerMissionError.runInProgress) { try model.selectWorkerCount(2) }
        #expect(try model.finishWorkerPresentation() == false)
        let baseline = try #require(model.workerMission.baselineRun)
        #expect(baseline.result.metrics.completionTimeMilliseconds == 5_000)
        #expect(baseline.result.metrics.averageLatencyMilliseconds == 3_000)

        try model.selectWorkerCount(2)
        #expect(try model.startWorkerRun())
        let comparison = try #require(model.workerMission.comparisonRun)
        #expect(comparison.workload == baseline.workload)
        #expect(comparison.configuration.seed == baseline.configuration.seed)
        #expect(comparison.result.metrics.completionTimeMilliseconds == 3_000)
        #expect(comparison.result.metrics.averageLatencyMilliseconds == 1_960)
        #expect(comparison.result.finalRequests.map(\.id) == mission2.workload.map(\.id))

        let projected = SimulationEventProjector().project(
            events: comparison.result.orderedEvents[...],
            workload: comparison.workload,
            configuration: comparison.configuration
        )
        let phaseEvents = comparison.result.orderedEvents.filter {
            if case .phaseStarted = $0.payload { return true }
            return false
        }
        #expect(projected.timeline.count == phaseEvents.count)
        #expect(Set(projected.timeline.compactMap(\.workerID)).count == 2)

        #expect(try model.finishWorkerPresentation())
        #expect(model.missionEngine.progress.completedMissionIDs == [.sequentialProcessing, .workerConcurrency])
        #expect(model.missionEngine.progress.currentMissionID == .databaseStorage)
        #expect(model.activeMission == 3)
        #expect(try model.finishWorkerPresentation())
        #expect(model.missionEngine.progress.completedMissionIDs.count == 2)
    }

    @Test("Mission 2 validates zero through four workers, budget, feedback, and retry")
    func workerMissionEdges() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .workerConcurrency))
        var mission = WorkerMissionRun()
        #expect(throws: WorkerMissionError.workerCountOutOfRange(-1)) { try mission.selectWorkerCount(-1) }
        #expect(throws: WorkerMissionError.workerCountOutOfRange(5)) { try mission.selectWorkerCount(5) }
        #expect(throws: WorkerMissionError.baselineRequired) { try mission.selectWorkerCount(2) }

        #expect(try mission.start(definition: definition))
        #expect(try mission.start(definition: definition) == false)
        #expect(mission.finishPresentation() == false)
        let baseline = try #require(mission.baselineRun)
        #expect(baseline.result.metrics.completionTimeMilliseconds == 5_000)

        for workers in [0, 1, 3, 4, 2] {
            try mission.selectWorkerCount(workers)
            #expect(mission.resourceCost == workers)
            #expect(try mission.start(definition: definition))
            let run = try #require(mission.comparisonRun)
            let repeated = try SimulationEngine().run(
                initialState: definition.baselineState,
                workload: definition.workload,
                configuration: run.configuration
            )
            #expect(run.result == repeated)
            #expect(run.workload == baseline.workload)
            #expect(run.configuration.seed == baseline.configuration.seed)
            let won = mission.finishPresentation()
            #expect(won == (workers == 2))
            if workers == 0 {
                #expect(run.result.metrics.completed == 0)
                #expect(run.result.metrics.queued == 5)
                #expect(mission.feedback.contains("remain queued"))
            }
            if workers > 2 {
                #expect(mission.feedback.contains("diminishing returns"))
                #expect(mission.feedback.contains("exceed the two-unit budget"))
            }
        }

        mission.reset()
        #expect(mission.stage == .baselineReady)
        #expect(mission.selectedWorkerCount == 1)
        #expect(mission.baselineRun == nil)
        #expect(mission.comparisonRun == nil)
        #expect(try mission.start(definition: definition))
        #expect(mission.baselineRun?.result == baseline.result)
    }

    @Test("Mission 3 installs, connects, persists a round trip, and unlocks Mission 4 once")
    func databaseMissionHappyPath() throws {
        let model = AppModel(store: completedMission2Store())
        try model.installDatabase()
        #expect(model.databaseMission.isInstalled)
        #expect(!model.databaseMission.isConnected)
        #expect(model.missionEngine.progress.configuredComponents.filter { $0.type == .primaryDatabase }.count == 1)

        let disconnected = try model.readDatabaseRecord(key: "status")
        #expect(disconnected.finalRequests.first?.status == .failed(at: 0, reason: .databaseDisconnected))
        #expect(model.databaseMission.feedback?.message.contains("Connection error") == true)

        try model.connectDatabase()
        let write = try model.writeDatabaseRecord(key: " status ", value: " online ")
        #expect(write.metrics.databaseWrites == 1)
        #expect(write.metrics.completionTimeMilliseconds == 500)
        let read = try model.readDatabaseRecord(key: "status")
        #expect(read.metrics.databaseReads == 1)
        #expect(read.metrics.completionTimeMilliseconds == 300)
        #expect(model.databaseMission.database.records["status"] == "online")

        let workload = try model.runDatabaseWorkload()
        #expect(workload.result.metrics.completed == 2)
        #expect(workload.result.metrics.databaseWrites == 1)
        #expect(workload.result.metrics.databaseReads == 1)
        let projected = SimulationEventProjector().project(
            events: workload.result.orderedEvents[...],
            workload: workload.workload,
            configuration: workload.configuration
        )
        #expect(projected.presentedEventCount == workload.result.orderedEvents.count)
        #expect(model.databaseMission.isComplete)
        #expect(model.missionEngine.progress.completedMissionIDs == [.sequentialProcessing, .workerConcurrency, .databaseStorage])
        #expect(model.missionEngine.progress.currentMissionID == .infrastructureScaling)
        #expect(model.activeMission == 4)

        let completionCount = model.missionEngine.progress.completedMissionIDs.count
        #expect(throws: MissionEngineError.missionUnavailable(.databaseStorage)) {
            _ = try model.runDatabaseWorkload()
        }
        #expect(model.missionEngine.progress.completedMissionIDs.count == completionCount)

        try model.replayMission(.sequentialProcessing)
        #expect(model.missionEngine.session?.state.database.records.isEmpty == true)
        #expect(model.databaseMission.database.records.isEmpty)
    }

    @Test("Mission 3 validates terminal input, capacity, upsert, missing reads, and reset")
    func databaseMissionEdges() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .databaseStorage))
        var mission = DatabaseMissionRun(database: definition.baselineState.database)
        #expect(throws: DatabaseMissionError.databaseNotInstalled) { try mission.connect() }
        mission.install()
        #expect(throws: DatabaseMissionError.emptyKey) { try mission.write(key: "  ", value: "value") }
        #expect(throws: DatabaseMissionError.emptyValue) { try mission.write(key: "key", value: " \n ") }
        try mission.connect()

        for index in 1...5 {
            let result = try mission.write(key: "key-\(index)", value: "value-\(index)")
            #expect(result.metrics.completed == 1)
        }
        #expect(mission.capacityUsed == 5)
        let full = try mission.write(key: "sixth", value: "blocked")
        #expect(full.finalRequests.first?.status == .failed(at: 0, reason: .storageFull))
        #expect(mission.capacityUsed == 5)
        let upsert = try mission.write(key: "key-1", value: "updated")
        #expect(upsert.metrics.completed == 1)
        #expect(mission.database.records["key-1"] == "updated")
        #expect(mission.capacityUsed == 5)
        let missing = try mission.read(key: "absent")
        #expect(missing.finalRequests.first?.status == .failed(at: 300, reason: .recordNotFound))
        #expect(mission.feedback?.message == "Record not found.")

        mission.reset(to: definition)
        #expect(!mission.isInstalled)
        #expect(!mission.isConnected)
        #expect(mission.database.records.isEmpty)
        #expect(mission.workloadRun == nil)
    }

    @Test("Mission 4 baseline, cache, and replica fixtures meet their exact measured contracts")
    func infrastructureMeasuredSolutions() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .infrastructureScaling))

        var cacheMission = InfrastructureMissionRun()
        let baseline = try cacheMission.run(definition: definition)
        #expect(baseline.workload.count == 10)
        #expect(baseline.workload.allSatisfy { $0.arrivalTimeMilliseconds == 0 })
        #expect(baseline.result.metrics.averageLatencyMilliseconds == 1_650)
        #expect(baseline.result.metrics.completionTimeMilliseconds == 3_000)
        #expect(completionTimes(baseline.result) == stride(from: 300, through: 3_000, by: 300).map(Int64.init))

        try cacheMission.select(.cache)
        let cached = try cacheMission.run(definition: definition)
        #expect(cacheMission.resourceCost == 2)
        #expect(cached.result.metrics.cacheMisses == 1)
        #expect(cached.result.metrics.cacheHits == 9)
        #expect(cached.result.metrics.databaseReads == 1)
        #expect(cached.result.metrics.averageLatencyMilliseconds == 525)
        #expect(cacheMission.isVictorious)

        var replicaMission = InfrastructureMissionRun()
        _ = try replicaMission.run(definition: definition)
        try replicaMission.select(.readReplica)
        let replicated = try replicaMission.run(definition: definition)
        #expect(replicaMission.resourceCost == 3)
        #expect(replicated.result.metrics.replicaReads == 5)
        #expect(replicated.result.metrics.averageLatencyMilliseconds == 900)
        #expect(replicated.result.metrics.completionTimeMilliseconds == 1_500)
        #expect(replicaMission.isVictorious)
        #expect(try replicaMission.run(definition: definition) == replicated)
    }

    @Test("Mission 4 enforces budget and routing while preserving playable ineffective results")
    func infrastructureEdgesAndServerTradeoff() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .infrastructureScaling))
        var mission = InfrastructureMissionRun()
        #expect(throws: InfrastructureMissionError.baselineRequired) { try mission.select(.cache) }
        _ = try mission.run(definition: definition)
        #expect(throws: InfrastructureMissionError.routingRequiresSecondServer) { try mission.select(.routing) }

        try mission.select(.secondServer)
        #expect(mission.unavailableReason(for: .cache)?.contains("only 1 budget remains") == true)
        #expect(throws: InfrastructureMissionError.insufficientBudget(required: 2, available: 1)) {
            try mission.select(.cache)
        }
        let serverOnly = try mission.run(definition: definition)
        #expect(serverOnly.configuration.nodes.contains { $0.id == "server-2" })
        #expect(!serverOnly.configuration.nodes.contains { $0.type == .loadBalancer })
        #expect(serverOnly.workload.allSatisfy { $0.destinationNodeID == nil })
        #expect(serverOnly.result.metrics.averageLatencyMilliseconds == 1_650)
        #expect(mission.feedback.contains("received no traffic"))
        #expect(!mission.isVictorious)

        try mission.select(.routing)
        let routed = try mission.run(definition: definition)
        #expect(mission.resourceCost == 3)
        #expect(routed.configuration.nodes.contains { $0.type == .loadBalancer && $0.connections == ["server-1", "server-2"] })
        #expect(routed.workload.filter { $0.destinationNodeID == "server-2" }.count == 5)
        #expect(routed.result.metrics.averageLatencyMilliseconds == 1_650)
        #expect(mission.feedback.contains("same primary database"))

        mission.reset()
        #expect(mission.stage == .baselineReady)
        #expect(mission.resourceCost == 0)
        #expect(mission.baselineRun == nil)
    }

    @Test("Mission 4 cache victory unlocks Mission 5 and its alert exactly once")
    func infrastructureUnlock() throws {
        let model = AppModel(store: completedMission3Store())
        let baseline = try model.runInfrastructureWorkload()
        #expect(baseline.result.metrics.averageLatencyMilliseconds == 1_650)
        try model.selectInfrastructureUpgrade(.cache)
        let result = try model.runInfrastructureWorkload()
        #expect(result.result.metrics.averageLatencyMilliseconds == 525)
        #expect(model.missionEngine.progress.completedMissionIDs == [.sequentialProcessing, .workerConcurrency, .databaseStorage, .infrastructureScaling])
        #expect(model.missionEngine.progress.currentMissionID == .systemDiagnostics)
        #expect(model.activeMission == 5)
        #expect(model.laboratoryWorld.object(.monitoringTerminal)?.isEnabled(in: model.activeMission) == true)

        let completionCount = model.missionEngine.progress.completedMissionIDs.count
        #expect(throws: MissionEngineError.missionUnavailable(.infrastructureScaling)) {
            _ = try model.runInfrastructureWorkload()
        }
        #expect(model.missionEngine.progress.completedMissionIDs.count == completionCount)

        try model.replayMission(.infrastructureScaling)
        #expect(model.activeMission == 4)
        #expect(model.infrastructureMission.stage == .baselineReady)
        #expect(model.missionEngine.progress.completedMissionIDs.count == completionCount)
    }

    @Test("Mission 5 baseline evidence is low-CPU, queue-light, and database-bound")
    func diagnosticBaselineAndEvidenceGate() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .systemDiagnostics))
        var mission = DiagnosticMissionRun()
        #expect(throws: DiagnosticMissionError.baselineRequired) { try mission.inspect(.cpu) }
        let baseline = try mission.measureBaseline(definition: definition)
        #expect(baseline.result.metrics.cpuUtilization == 0)
        #expect(baseline.result.metrics.queued == 0)
        #expect(baseline.result.metrics.totalQueueWaitMilliseconds == 0)
        #expect(baseline.result.metrics.averageLatencyMilliseconds == 1_650)
        #expect(baseline.result.metrics.averageLatencyMilliseconds > 1_000)
        #expect(baseline.result.metrics.databaseReads == 10)
        #expect(mission.snapshot?.databaseLatencyMilliseconds == 1_650)
        #expect(!mission.canChooseInterventions)
        #expect(throws: DiagnosticMissionError.evidenceRequired) { try mission.toggle(.cache) }

        try mission.inspect(.cpu)
        try mission.inspect(.cpu)
        #expect(mission.inspectedEvidence.count == 1)
        #expect(!mission.canChooseInterventions)
        try mission.inspect(.database)
        #expect(mission.inspectedEvidence.count == 2)
        #expect(mission.canChooseInterventions)
        #expect(mission.feedback.contains("serialized primary-database reads"))
    }

    @Test("Mission 5 workers and server capacity do not repair the database bottleneck")
    func diagnosticIncorrectInterventionsAndUnlimitedRetry() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .systemDiagnostics))
        var mission = DiagnosticMissionRun()
        _ = try mission.measureBaseline(definition: definition)
        try mission.inspect(.cpu)
        try mission.inspect(.workerQueue)

        try mission.toggle(.increasedWorkers)
        let workers = try mission.verify(definition: definition)
        #expect(workers.configuration.workerCount == 4)
        #expect(workers.result.metrics.averageLatencyMilliseconds == 1_650)
        #expect(!mission.isVictorious)
        #expect(mission.explanationIDs == ["diagnostic-database-bottleneck-remains"])
        #expect(mission.attemptCount == 1)

        try mission.resetInterventions()
        #expect(mission.inspectedEvidence.count == 2)
        #expect(mission.attemptCount == 1)
        try mission.toggle(.increasedServerCapacity)
        let server = try mission.verify(definition: definition)
        #expect(server.configuration.nodes.contains { $0.type == .loadBalancer })
        #expect(server.workload.filter { $0.destinationNodeID == "server-2" }.count == 5)
        #expect(server.result.metrics.averageLatencyMilliseconds == 1_650)
        #expect(mission.attemptCount == 2)
        #expect(!mission.isVictorious)

        for _ in 0..<3 {
            try mission.resetInterventions()
            try mission.toggle(.increasedWorkers)
            _ = try mission.verify(definition: definition)
        }
        #expect(mission.attemptCount == 5)
        #expect(mission.feedback.contains("serialized primary-database bottleneck"))
    }

    @Test("Mission 5 replica, cache, and combined configurations win from measured results")
    func diagnosticMeasuredRepairsAndCombinedConfiguration() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .systemDiagnostics))

        var replicaMission = DiagnosticMissionRun()
        _ = try replicaMission.measureBaseline(definition: definition)
        try replicaMission.inspect(.database)
        try replicaMission.inspect(.responseAndArchitecture)
        try replicaMission.toggle(.readReplica)
        let replica = try replicaMission.verify(definition: definition)
        #expect(replica.result.metrics.averageLatencyMilliseconds == 900)
        #expect(replica.result.metrics.replicaReads == 5)
        #expect(replicaMission.isVictorious)
        #expect(replicaMission.explanationIDs == ["diagnostic-replica-relieved-database", "diagnostic-target-met"])

        var cacheMission = DiagnosticMissionRun()
        _ = try cacheMission.measureBaseline(definition: definition)
        try cacheMission.inspect(.cpu)
        try cacheMission.inspect(.database)
        try cacheMission.toggle(.increasedWorkers)
        try cacheMission.toggle(.increasedServerCapacity)
        try cacheMission.toggle(.cache)
        let combined = try cacheMission.verify(definition: definition)
        #expect(cacheMission.resourceCost == 4)
        #expect(combined.configuration.workerCount == 4)
        #expect(combined.configuration.nodes.contains { $0.type == .loadBalancer })
        #expect(combined.configuration.cacheEnabled)
        #expect(combined.result.metrics.averageLatencyMilliseconds == 525)
        #expect(combined.result.metrics.cacheHits == 9)
        #expect(cacheMission.isVictorious)
        #expect(cacheMission.explanationIDs == ["diagnostic-cache-relieved-database", "diagnostic-target-met"])
    }

    @Test("Mission 5 distinguishes a missing database connection and rejects inconsistent victory metrics")
    func diagnosticConnectionFaultAndSafeEvaluation() throws {
        let definition = try #require(MissionCatalog.standard.definition(for: .systemDiagnostics))
        var mission = DiagnosticMissionRun(databaseConnected: false)
        let baseline = try mission.measureBaseline(definition: definition)
        #expect(baseline.result.metrics.failed == 10)
        #expect(mission.explanationIDs == ["diagnostic-database-disconnected"])
        #expect(mission.feedback.contains("Configuration fault"))
        try mission.inspect(.database)
        try mission.inspect(.responseAndArchitecture)
        try mission.toggle(.cache)
        _ = try mission.verify(definition: definition)
        #expect(!mission.isVictorious)
        #expect(mission.explanationIDs == ["diagnostic-database-disconnected"])

        let inconsistent = SimulationResult(
            metrics: SimulationMetrics(completed: 10, failed: 0, rejected: 0, queued: 0, running: 0, totalQueueWaitMilliseconds: 0, averageLatencyMilliseconds: 500, completionTimeMilliseconds: 500, databaseReads: 1, databaseWrites: 0, cacheHits: 9, cacheMisses: 1, replicaReads: 0, cpuUtilization: 0),
            orderedEvents: [], finalRequests: [], workers: [], database: .standard, seed: 45_005, explanationIDs: []
        )
        let objectives = definition.objectives
        #expect(!MissionVictoryRule.diagnosedBottleneck.evaluate(.init(
            result: inconsistent,
            achievedObjectiveIDs: Set(objectives.map(\.id)),
            facts: ["database-bottleneck-improved"],
            inspectedEvidenceCount: 2
        ), objectives: objectives))
    }

    @Test("Mission 5 completion, title, persistence, and replay are idempotent")
    func diagnosticCompletionPersistenceAndReplay() throws {
        let store = completedMission4Store()
        let model = AppModel(store: store)
        let baseline = try model.measureDiagnosticBaseline()
        #expect(baseline.result.metrics.averageLatencyMilliseconds == 1_650)
        try model.inspectDiagnosticEvidence(.cpu)
        try model.inspectDiagnosticEvidence(.database)
        try model.toggleDiagnosticIntervention(.cache)
        let verification = try model.verifyDiagnosticRepair()
        #expect(verification.result.metrics.averageLatencyMilliseconds == 525)
        #expect(model.missionEngine.progress.completedMissionIDs == Set(MissionID.allCases))
        #expect(model.missionEngine.progress.titleAwarded)
        #expect(model.diagnosticMission.isVictorious)

        let restored = AppModel(store: store)
        #expect(restored.missionEngine.progress.completedMissionIDs == Set(MissionID.allCases))
        #expect(restored.missionEngine.progress.titleAwarded)
        let completionCount = restored.missionEngine.progress.completedMissionIDs.count
        try restored.replayMission(.systemDiagnostics)
        #expect(restored.activeMission == 5)
        #expect(restored.diagnosticMission.stage == .alert)
        #expect(restored.missionEngine.progress.completedMissionIDs.count == completionCount)
        #expect(restored.missionEngine.progress.titleAwarded)

        _ = try restored.measureDiagnosticBaseline()
        try restored.inspectDiagnosticEvidence(.cpu)
        try restored.inspectDiagnosticEvidence(.database)
        try restored.toggleDiagnosticIntervention(.readReplica)
        _ = try restored.verifyDiagnosticRepair()
        #expect(restored.missionEngine.progress.completedMissionIDs.count == completionCount)
        #expect(restored.missionEngine.progress.titleAwarded)
    }

    @Test("A clean offline journey completes all missions and replays each saved mission")
    func cleanOfflineMissionJourneyAndReplay() throws {
        let store = MemoryStore()
        let model = AppModel(store: store)
        model.enterLaboratory()

        try model.receiveSequentialRequestCards()
        #expect(try model.startSequentialServer())
        model.finishSequentialPresentation()
        #expect(try model.answerSequentialCause(.queueWhileWorkerBusy))
        #expect(model.activeMission == 2)

        #expect(try model.startWorkerRun())
        #expect(try model.finishWorkerPresentation() == false)
        try model.selectWorkerCount(2)
        #expect(try model.startWorkerRun())
        #expect(try model.finishWorkerPresentation())
        #expect(model.activeMission == 3)

        try model.installDatabase()
        try model.connectDatabase()
        _ = try model.writeDatabaseRecord(key: "status", value: "online")
        _ = try model.readDatabaseRecord(key: "status")
        _ = try model.runDatabaseWorkload()
        #expect(model.activeMission == 4)

        let baseline = try model.runInfrastructureWorkload()
        #expect(baseline.result.metrics.averageLatencyMilliseconds == 1_650)
        try model.selectInfrastructureUpgrade(.cache)
        let scaled = try model.runInfrastructureWorkload()
        #expect(scaled.result.metrics.averageLatencyMilliseconds == 525)
        #expect(model.activeMission == 5)

        let diagnosticBaseline = try model.measureDiagnosticBaseline()
        #expect(diagnosticBaseline.result.metrics.averageLatencyMilliseconds == 1_650)
        try model.inspectDiagnosticEvidence(.cpu)
        try model.inspectDiagnosticEvidence(.database)
        try model.toggleDiagnosticIntervention(.cache)
        let repair = try model.verifyDiagnosticRepair()
        #expect(repair.result.metrics.averageLatencyMilliseconds == 525)
        #expect(model.missionEngine.progress.completedMissionIDs == Set(MissionID.allCases))
        #expect(model.missionEngine.progress.titleAwarded)
        #expect(model.missionEngine.progress.currentMissionID == .systemDiagnostics)

        let restored = AppModel(store: store)
        #expect(restored.primaryActionTitle == "Continue")
        #expect(restored.missionEngine.progress.completedMissionIDs == Set(MissionID.allCases))
        #expect(restored.missionEngine.progress.titleAwarded)

        for missionID in MissionID.allCases {
            let replay = AppModel(store: store)
            try replay.replayMission(missionID)
            #expect(replay.activeMission == missionID.rawValue)
            #expect(replay.missionEngine.session?.isReplay == true)
            #expect(replay.missionEngine.progress.completedMissionIDs == Set(MissionID.allCases))
            #expect(replay.missionEngine.progress.titleAwarded)
        }
    }

    private func completionTimes(_ result: SimulationResult) -> [SimulationTime] {
        result.orderedEvents.compactMap { event in
            if case .completed = event.payload { return event.timestampMilliseconds }
            return nil
        }.sorted()
    }
}

@MainActor
private func completedMission1Store() -> MemoryStore {
    let store = MemoryStore()
    store.value = ShellSave(
        hasEnteredLaboratory: true,
        playerPosition: .initial,
        soundEnabled: true,
        missionProgress: MissionProgress(
            currentMissionID: .workerConcurrency,
            completedMissionIDs: [.sequentialProcessing],
            titleAwarded: false,
            lifecycle: .completed,
            configuredComponents: []
        )
    )
    return store
}

@MainActor
private func completedMission2Store() -> MemoryStore {
    let store = MemoryStore()
    store.value = ShellSave(
        hasEnteredLaboratory: true,
        playerPosition: .initial,
        soundEnabled: true,
        missionProgress: MissionProgress(
            currentMissionID: .databaseStorage,
            completedMissionIDs: [.sequentialProcessing, .workerConcurrency],
            titleAwarded: false,
            lifecycle: .completed,
            configuredComponents: []
        )
    )
    return store
}

@MainActor
private func completedMission3Store() -> MemoryStore {
    let store = MemoryStore()
    store.value = ShellSave(
        hasEnteredLaboratory: true,
        playerPosition: .initial,
        soundEnabled: true,
        missionProgress: MissionProgress(
            currentMissionID: .infrastructureScaling,
            completedMissionIDs: [.sequentialProcessing, .workerConcurrency, .databaseStorage],
            titleAwarded: false,
            lifecycle: .completed,
            configuredComponents: []
        )
    )
    return store
}

@MainActor
private func completedMission4Store() -> MemoryStore {
    let store = MemoryStore()
    store.value = ShellSave(
        hasEnteredLaboratory: true,
        playerPosition: .initial,
        soundEnabled: true,
        missionProgress: MissionProgress(
            currentMissionID: .systemDiagnostics,
            completedMissionIDs: [.sequentialProcessing, .workerConcurrency, .databaseStorage, .infrastructureScaling],
            titleAwarded: false,
            lifecycle: .completed,
            configuredComponents: []
        )
    )
    return store
}

private final class MemoryStore: ShellSaving {
    var value: ShellSave?
    var sound = true
    var saveCount = 0

    func load() throws -> ShellSave? { value }
    func save(_ value: ShellSave) throws { self.value = value; saveCount += 1 }
    func loadSoundEnabled() -> Bool { sound }
    func saveSoundEnabled(_ enabled: Bool) { sound = enabled }
}

private struct FailingStore: ShellSaving {
    func load() throws -> ShellSave? { throw ShellSaveError.invalidData }
    func save(_ value: ShellSave) throws { }
    func loadSoundEnabled() -> Bool { true }
    func saveSoundEnabled(_ enabled: Bool) { }
}

private struct WriteFailingStore: ShellSaving {
    func load() throws -> ShellSave? { nil }
    func save(_ value: ShellSave) throws { throw TestSaveFailure.unavailable }
    func loadSoundEnabled() -> Bool { true }
    func saveSoundEnabled(_ enabled: Bool) { }
}

private enum TestSaveFailure: Error {
    case unavailable
}
