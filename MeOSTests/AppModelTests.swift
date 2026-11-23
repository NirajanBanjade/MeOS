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
            .mission, .sequentialMission, .workerMission, .system(.server), .results, .pause, .glossary, .credits, .settings,
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

