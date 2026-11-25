import Foundation

struct MissionProgress: Codable, Equatable, Sendable {
    var currentMissionID: MissionID
    var completedMissionIDs: Set<MissionID>
    var titleAwarded: Bool
    var lifecycle: SimulationLifecycle
    var configuredComponents: [SystemNode]

    static let initial = MissionProgress(
        currentMissionID: .sequentialProcessing,
        completedMissionIDs: [],
        titleAwarded: false,
        lifecycle: .ready,
        configuredComponents: []
    )
}

struct MissionSession: Codable, Equatable, Sendable {
    let missionID: MissionID
    let isReplay: Bool
    var lifecycle: SimulationLifecycle
    var state: GameState
    var workload: [Request]
    var configuration: SimulationConfiguration
    var achievedObjectiveIDs: Set<String>
    var retryCount: Int
}

enum MissionEngineError: Error, Equatable, Sendable {
    case missionUnavailable(MissionID)
    case prerequisiteIncomplete(MissionID)
    case replayRequiresCompletion(MissionID)
    case noActiveSession
    case runInProgress
    case victoryRequirementsNotMet
}

struct MissionEngine: Equatable, Sendable {
    private(set) var progress: MissionProgress
    private(set) var session: MissionSession?
    private(set) var userFacingUnavailableMessage: String?
    let catalog: MissionCatalog

    init(progress: MissionProgress = .initial, catalog: MissionCatalog = .standard) {
        self.catalog = catalog
        var restored = progress
        if restored.lifecycle == .running {
            restored.lifecycle = .ready
        }
        self.progress = restored
        self.session = nil
        self.userFacingUnavailableMessage = catalog.validationIssues.first.map { _ in
            "Mission content is unavailable. Your saved progress is safe."
        }
    }

    var currentDefinition: MissionDefinition? {
        if let session, session.lifecycle != .completed {
            return catalog.definition(for: session.missionID)
        }
        return catalog.definition(for: progress.currentMissionID)
    }

    var durableProgress: MissionProgress {
        var stable = progress
        if stable.lifecycle == .running {
            stable.lifecycle = .ready
        }
        return stable
    }

    func isUnlocked(_ id: MissionID) -> Bool {
        guard let definition = catalog.definition(for: id) else { return false }
        guard let prerequisite = definition.prerequisite else { return true }
        return progress.completedMissionIDs.contains(prerequisite)
    }

    mutating func start(_ id: MissionID? = nil) throws {
        let requested = id ?? progress.currentMissionID
        guard let definition = catalog.definition(for: requested) else {
            userFacingUnavailableMessage = "Mission \(requested.rawValue) is unavailable. Your saved progress is safe."
            throw MissionEngineError.missionUnavailable(requested)
        }
        guard isUnlocked(requested) else { throw MissionEngineError.prerequisiteIncomplete(requested) }
        try begin(definition, replay: false)
    }

    mutating func replay(_ id: MissionID) throws {
        guard progress.completedMissionIDs.contains(id) else {
            throw MissionEngineError.replayRequiresCompletion(id)
        }
        guard let definition = catalog.definition(for: id) else {
            userFacingUnavailableMessage = "Mission \(id.rawValue) is unavailable. Your saved progress is safe."
            throw MissionEngineError.missionUnavailable(id)
        }
        try begin(definition, replay: true)
    }

    mutating func pause() throws {
        guard var session else { throw MissionEngineError.noActiveSession }
        if session.lifecycle == .running {
            session.lifecycle = .paused
            session.state.simulationLifecycle = .paused
            self.session = session
            progress.lifecycle = .paused
        }
    }

    mutating func resume() throws {
        guard var session else { throw MissionEngineError.noActiveSession }
        if session.lifecycle == .paused {
            session.lifecycle = .running
            session.state.simulationLifecycle = .ready
            self.session = session
            progress.lifecycle = .running
        }
    }

    mutating func markObjective(_ objectiveID: String) throws {
        guard var session else { throw MissionEngineError.noActiveSession }
        guard let definition = catalog.definition(for: session.missionID),
              definition.objectives.contains(where: { $0.id == objectiveID }) else {
            throw MissionEngineError.missionUnavailable(session.missionID)
        }
        session.achievedObjectiveIDs.insert(objectiveID)
        self.session = session
    }

    mutating func changeConfiguration(_ configuration: SimulationConfiguration) throws {
        guard var session else { throw MissionEngineError.noActiveSession }
        guard session.lifecycle != .running else { throw MissionEngineError.runInProgress }
        session.configuration = configuration
        self.session = session
    }

    mutating func updateConfiguredComponents(_ components: [SystemNode]) throws {
        // A mission may be active while its deterministic simulation is at a
        // stable ready checkpoint. Installation commands are valid there; only
        // an actually running simulation blocks graph mutation.
        guard session?.state.simulationLifecycle != .running else { throw MissionEngineError.runInProgress }
        progress.configuredComponents = components
    }

    @discardableResult
    mutating func complete(using context: MissionEvaluationContext) throws -> Bool {
        guard var session,
              let definition = catalog.definition(for: session.missionID) else {
            throw MissionEngineError.noActiveSession
        }
        var evaluated = context
        evaluated.achievedObjectiveIDs.formUnion(session.achievedObjectiveIDs)
        guard definition.victoryEvaluator.evaluate(evaluated, objectives: definition.objectives) else {
            throw MissionEngineError.victoryRequirementsNotMet
        }

        session.lifecycle = .completed
        session.state.simulationLifecycle = .completed
        self.session = session
        let inserted = progress.completedMissionIDs.insert(session.missionID).inserted
        progress.lifecycle = .completed
        if session.missionID == .systemDiagnostics {
            progress.titleAwarded = true
        }
        if !session.isReplay, let unlock = definition.unlock, unlock > progress.currentMissionID {
            progress.currentMissionID = unlock
        }
        return inserted
    }

    mutating func fail() throws {
        guard var session else { throw MissionEngineError.noActiveSession }
        session.lifecycle = .failed
        session.state.simulationLifecycle = .failed
        self.session = session
        progress.lifecycle = .failed
    }

    mutating func retry() throws {
        guard let session,
              let definition = catalog.definition(for: session.missionID) else {
            throw MissionEngineError.noActiveSession
        }
        let nextRetry = session.retryCount + 1
        self.session = makeSession(definition, replay: session.isReplay, retryCount: nextRetry)
        progress.lifecycle = .ready
    }

    mutating func prepareForBackground() {
        if session?.lifecycle == .running {
            try? pause()
        }
    }

    private mutating func begin(_ definition: MissionDefinition, replay: Bool) throws {
        guard session?.lifecycle != .running else { throw MissionEngineError.runInProgress }
        session = makeSession(definition, replay: replay, retryCount: 0)
        session?.lifecycle = .running
        // Mission activity and simulation execution are separate state machines.
        // The pure simulator must receive a stable, non-running baseline.
        session?.state.simulationLifecycle = .ready
        progress.lifecycle = .running
    }

    private func makeSession(_ definition: MissionDefinition, replay: Bool, retryCount: Int) -> MissionSession {
        MissionSession(
            missionID: definition.id,
            isReplay: replay,
            lifecycle: .ready,
            state: definition.baselineState,
            workload: definition.workload,
            configuration: definition.configuration,
            achievedObjectiveIDs: [],
            retryCount: retryCount
        )
    }
}
