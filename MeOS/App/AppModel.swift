import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var screen: AppScreen = .home
    @Published var presentedPanel: AppPanel?
    @Published private(set) var hasValidSave = false
    @Published private(set) var recoveryMessage: String?
    @Published var soundEnabled: Bool {
        didSet {
            store.saveSoundEnabled(soundEnabled)
            if !isRestoring { persistCheckpoint() }
        }
    }
    @Published private(set) var playerPosition = PlayerPosition.initial
    @Published private(set) var laboratoryState = LaboratorySessionState.initial
    @Published private(set) var nearbyObjectID: LaboratoryObjectID?
    @Published private(set) var movementMessage: String?
    @Published private(set) var activeMission = 1
    @Published private(set) var missionEngine = MissionEngine()
    @Published private(set) var visualizationRun: VisualizationRun?
    @Published private(set) var sequentialMission = SequentialMissionRun()
    @Published private(set) var workerMission = WorkerMissionRun()
    @Published private(set) var databaseMission = DatabaseMissionRun()
    @Published private(set) var infrastructureMission = InfrastructureMissionRun()
    @Published private(set) var diagnosticMission = DiagnosticMissionRun()

    var currentObjective: String {
        missionEngine.currentDefinition?.objectives.first?.text
            ?? "Mission content is unavailable."
    }
    var missionTitle: String {
        guard let definition = missionEngine.currentDefinition else { return "Mission unavailable" }
        return "Mission \(definition.id.rawValue) · \(definition.title)"
    }
    var missionProgress: String {
        "\(missionEngine.progress.completedMissionIDs.count) of \(MissionID.allCases.count) complete"
    }
    let forceReduceMotion = ProcessInfo.processInfo.arguments.contains("-UI_TEST_REDUCE_MOTION")

    private let store: any ShellSaving
    private var isRestoring = false
    let laboratoryWorld = LaboratoryWorld.standard

    init(store: any ShellSaving = AtomicFileShellStore()) {
        self.store = store
        soundEnabled = store.loadSoundEnabled()
        restore()
    }

    var primaryActionTitle: String { hasValidSave ? "Continue" : "Start" }
    var shouldShowEngineerIntroduction: Bool { !laboratoryState.engineerIntroductionSeen }
    var nearbyObject: LaboratoryObject? {
        nearbyObjectID.flatMap(laboratoryWorld.object)
    }
    var completedMissionDefinitions: [MissionDefinition] {
        missionEngine.progress.completedMissionIDs.sorted().compactMap {
            missionEngine.catalog.definition(for: $0)
        }
    }

    func enterLaboratory() {
        guard screen == .home else { return }
        screen = .laboratory
        hasValidSave = true
        persistCheckpoint()
    }

    func returnHome() {
        presentedPanel = nil
        screen = .home
        persistCheckpoint()
    }

    func present(_ panel: AppPanel) {
        guard presentedPanel == nil else { return }
        presentedPanel = panel
    }

    func replacePanel(with panel: AppPanel) {
        presentedPanel = panel
    }

    func closePanel() {
        presentedPanel = nil
    }

    func updatePlayerPosition(_ position: PlayerPosition) {
        playerPosition = position
        laboratoryState.playerTile = Self.tile(from: position)
        updateNearbyObject()
        persistCheckpoint()
    }

    func updatePlayerTile(_ tile: GridPoint) {
        laboratoryState.playerTile = tile
        playerPosition = Self.position(from: tile)
        updateNearbyObject()
        persistCheckpoint()
    }

    func reportMovementIssue(_ message: String?) {
        movementMessage = message
    }

    func dismissMovementMessage() {
        movementMessage = nil
    }

    func acknowledgeEngineerIntroduction() {
        laboratoryState.engineerIntroductionSeen = true
        persistCheckpoint()
    }

    func requestInteraction(with id: LaboratoryObjectID, accessible: Bool = false) {
        guard presentedPanel == nil || presentedPanel == .accessibleInteractions,
              let object = laboratoryWorld.object(id) else { return }
        guard object.isEnabled(in: activeMission) else {
            movementMessage = "\(object.name) unlocks in Mission \(object.minimumMission)."
            return
        }
        if !accessible {
            let resolution = InteractionManager(world: laboratoryWorld).resolve(
                id,
                player: laboratoryState.playerTile,
                mission: activeMission
            )
            guard case .available = resolution else { return }
        }

        if laboratoryState.discoveredObjects.insert(id).inserted {
            presentedPanel = .teaching(id)
            persistCheckpoint()
        } else {
            openDestination(for: object)
        }
    }

    func continueFromTeaching(_ id: LaboratoryObjectID) {
        guard let object = laboratoryWorld.object(id) else {
            closePanel()
            return
        }
        openDestination(for: object)
    }

    func updateMission(_ mission: Int) {
        activeMission = min(max(mission, 1), 5)
        updateNearbyObject()
    }

    func startCurrentMission() throws {
        try missionEngine.start()
    }

    func receiveSequentialRequestCards(count: Int = 5) throws {
        guard let definition = missionEngine.catalog.definition(for: .sequentialProcessing) else {
            throw MissionEngineError.missionUnavailable(.sequentialProcessing)
        }
        try sequentialMission.receiveCards(count: count, definition: definition)
    }

    @discardableResult
    func startSequentialServer() throws -> Bool {
        guard activeMission == MissionID.sequentialProcessing.rawValue,
              let definition = missionEngine.catalog.definition(for: .sequentialProcessing) else {
            throw MissionEngineError.missionUnavailable(.sequentialProcessing)
        }
        guard sequentialMission.canStart else {
            if sequentialMission.workload.isEmpty { throw SequentialMissionError.emptyQueue }
            return false
        }
        if missionEngine.session == nil {
            try missionEngine.start(.sequentialProcessing)
        }
        let started = try sequentialMission.start(definition: definition)
        if started { try missionEngine.markObjective("run-five") }
        return started
    }

    @discardableResult
    func playSequentialPresentation() -> Bool { sequentialMission.play() }

    func pauseSequentialPresentation() { sequentialMission.pause() }

    func setSequentialPresentationSpeed(_ speed: PresentationSpeed) {
        sequentialMission.setSpeed(speed)
    }

    @discardableResult
    func presentNextSequentialEvent() -> SimulationEvent? {
        sequentialMission.presentNextEvent()
    }

    func finishSequentialPresentation() { sequentialMission.finishPresentation() }

    @discardableResult
    func answerSequentialCause(_ cause: SequentialWaitCause) throws -> Bool {
        guard try sequentialMission.answer(cause) else { return false }
        try missionEngine.markObjective("identify-queue")
        guard let result = sequentialMission.run?.result else {
            throw SequentialMissionError.runNotFinished
        }
        _ = try completeCurrentMission(using: MissionEvaluationContext(
            result: result,
            facts: ["queue-identified"]
        ))
        return true
    }

    func resetSequentialMission() throws {
        sequentialMission.reset()
        if missionEngine.session != nil { try missionEngine.retry() }
        persistCheckpoint()
    }

    func selectWorkerCount(_ count: Int) throws {
        try workerMission.selectWorkerCount(count)
    }

    @discardableResult
    func startWorkerRun() throws -> Bool {
        guard activeMission == MissionID.workerConcurrency.rawValue,
              let definition = missionEngine.catalog.definition(for: .workerConcurrency) else {
            throw MissionEngineError.missionUnavailable(.workerConcurrency)
        }
        if missionEngine.session?.missionID != .workerConcurrency {
            try missionEngine.start(.workerConcurrency)
        }
        return try workerMission.start(definition: definition)
    }

    @discardableResult
    func playWorkerPresentation() -> Bool { workerMission.play() }

    func pauseWorkerPresentation() { workerMission.pause() }

    @discardableResult
    func presentNextWorkerEvent() -> SimulationEvent? { workerMission.presentNextEvent() }

    @discardableResult
    func finishWorkerPresentation() throws -> Bool {
        let wasBaseline = workerMission.comparisonRun == nil
        let won = workerMission.finishPresentation()
        if wasBaseline, workerMission.stage == .configure {
            try missionEngine.markObjective("compare-baseline")
        }
        if won {
            try missionEngine.markObjective("meet-worker-target")
            guard let result = workerMission.comparisonRun?.result else {
                throw MissionEngineError.victoryRequirementsNotMet
            }
            _ = try completeCurrentMission(using: MissionEvaluationContext(
                result: result,
                workerCount: workerMission.selectedWorkerCount,
                resourceCost: workerMission.resourceCost
            ))
        }
        return won
    }

    func resetWorkerMission() throws {
        workerMission.reset()
        if missionEngine.session?.missionID == .workerConcurrency { try missionEngine.retry() }
        persistCheckpoint()
    }

    func installDatabase() throws {
        let definition = try databaseDefinition()
        try ensureDatabaseSession()
        databaseMission.install()
        try updateConfiguredComponents(databaseComponents(connected: false))
        if definition.id != .databaseStorage { throw MissionEngineError.missionUnavailable(.databaseStorage) }
    }

    func connectDatabase() throws {
        try ensureDatabaseSession()
        try databaseMission.connect()
        try updateConfiguredComponents(databaseComponents(connected: true))
    }

    @discardableResult
    func writeDatabaseRecord(key: String, value: String) throws -> SimulationResult {
        try ensureDatabaseSession()
        let result = try databaseMission.write(key: key, value: value)
        if databaseMission.didWriteScriptedRecord { try missionEngine.markObjective("store-record") }
        persistCheckpoint()
        return result
    }

    @discardableResult
    func readDatabaseRecord(key: String) throws -> SimulationResult {
        try ensureDatabaseSession()
        let result = try databaseMission.read(key: key)
        if databaseMission.didReadScriptedRecord { try missionEngine.markObjective("retrieve-record") }
        persistCheckpoint()
        return result
    }

    @discardableResult
    func runDatabaseWorkload() throws -> VisualizationRun {
        let definition = try databaseDefinition()
        try ensureDatabaseSession()
        let run = try databaseMission.runConnectedWorkload(definition: definition)
        if run.result.metrics.completed == definition.workload.count,
           run.result.metrics.failed == 0 {
            try missionEngine.markObjective("run-connected")
        }
        if databaseMission.isComplete {
            _ = try completeCurrentMission(using: MissionEvaluationContext(
                result: run.result,
                facts: ["database-installed", "database-connected", "record-matched", "workload-completed"]
            ))
        } else {
            persistCheckpoint()
        }
        return run
    }

    func resetDatabaseMission() throws {
        let definition = try databaseDefinition()
        databaseMission.reset(to: definition)
        if missionEngine.session?.missionID == .databaseStorage { try missionEngine.retry() }
        try updateConfiguredComponents([])
    }

    @discardableResult
    func runInfrastructureWorkload() throws -> VisualizationRun {
        let definition = try infrastructureDefinition()
        try ensureInfrastructureSession()
        let wasBaseline = infrastructureMission.baselineRun == nil
        let run = try infrastructureMission.run(definition: definition)
        if wasBaseline {
            try missionEngine.markObjective("measure-baseline")
        } else if infrastructureMission.isVictorious {
            try missionEngine.markObjective("meet-scaling-target")
            _ = try completeCurrentMission(using: MissionEvaluationContext(
                result: run.result,
                resourceCost: infrastructureMission.resourceCost
            ))
        }
        try updateConfiguredComponents(run.configuration.nodes)
        return run
    }

    func selectInfrastructureUpgrade(_ upgrade: InfrastructureUpgrade) throws {
        try ensureInfrastructureSession()
        try infrastructureMission.select(upgrade)
    }

    func resetInfrastructureMission() throws {
        _ = try infrastructureDefinition()
        infrastructureMission.reset()
        if missionEngine.session?.missionID == .infrastructureScaling { try missionEngine.retry() }
        try updateConfiguredComponents([])
    }

    @discardableResult
    func measureDiagnosticBaseline() throws -> VisualizationRun {
        let definition = try diagnosticDefinition()
        try ensureDiagnosticSession()
        let run = try diagnosticMission.measureBaseline(definition: definition)
        try updateConfiguredComponents(run.configuration.nodes)
        return run
    }

    func inspectDiagnosticEvidence(_ evidence: DiagnosticEvidence) throws {
        try ensureDiagnosticSession()
        try diagnosticMission.inspect(evidence)
        if diagnosticMission.inspectedEvidence.count >= 2 {
            try missionEngine.markObjective("inspect-evidence")
        }
    }

    func toggleDiagnosticIntervention(_ intervention: DiagnosticIntervention) throws {
        try ensureDiagnosticSession()
        try diagnosticMission.toggle(intervention)
    }

    @discardableResult
    func verifyDiagnosticRepair() throws -> VisualizationRun {
        let definition = try diagnosticDefinition()
        try ensureDiagnosticSession()
        let run = try diagnosticMission.verify(definition: definition)
        try updateConfiguredComponents(run.configuration.nodes)
        if diagnosticMission.isVictorious {
            try missionEngine.markObjective("verify-repair")
            _ = try completeCurrentMission(using: MissionEvaluationContext(
                result: run.result,
                facts: ["database-bottleneck-improved"],
                resourceCost: diagnosticMission.resourceCost,
                inspectedEvidenceCount: diagnosticMission.inspectedEvidence.count
            ))
        } else {
            persistCheckpoint()
        }
        return run
    }

    func resetDiagnosticInterventions() throws {
        try ensureDiagnosticSession()
        try diagnosticMission.resetInterventions()
        if missionEngine.session?.missionID == .systemDiagnostics { try missionEngine.retry() }
        if diagnosticMission.inspectedEvidence.count >= 2 {
            try missionEngine.markObjective("inspect-evidence")
        }
        persistCheckpoint()
    }

    func markMissionObjective(_ objectiveID: String) throws {
        try missionEngine.markObjective(objectiveID)
    }

    @discardableResult
    func completeCurrentMission(using context: MissionEvaluationContext) throws -> Bool {
        let awarded = try missionEngine.complete(using: context)
        activeMission = missionEngine.progress.currentMissionID.rawValue
        updateNearbyObject()
        persistCheckpoint()
        return awarded
    }

    func retryCurrentMission() throws {
        try missionEngine.retry()
        persistCheckpoint()
    }

    func replayMission(_ id: MissionID) throws {
        try missionEngine.replay(id)
        if id < .databaseStorage { databaseMission = DatabaseMissionRun() }
        if id <= .infrastructureScaling { infrastructureMission = InfrastructureMissionRun() }
        if id <= .systemDiagnostics { diagnosticMission = DiagnosticMissionRun() }
        activeMission = id.rawValue
        updateNearbyObject()
        closePanel()
    }

    func updateConfiguredComponents(_ components: [SystemNode]) throws {
        try missionEngine.updateConfiguredComponents(components)
        persistCheckpoint()
    }

    func handleBackgrounding() {
        sequentialMission.pause()
        workerMission.pause()
        missionEngine.prepareForBackground()
        persistCheckpoint()
    }

    /// Creates a deterministic, non-mission preview for the shared Feature 05
    /// visualization. Mission completion remains exclusively owned by MissionEngine.
    func prepareVisualizationPreview() {
        let nodes = [
            SystemNode(id: "client", type: .client, connections: ["server"]),
            SystemNode(id: "server", type: .applicationServer, connections: ["cpu"]),
            SystemNode(id: "cpu", type: .cpu)
        ]
        let workload = (1...5).map { Request(id: RequestID(rawValue: "request-\($0)")) }
        let configuration = SimulationConfiguration(workerCount: 1, nodes: nodes, seed: 5)
        do {
            let result = try SimulationEngine().run(
                initialState: GameState(mission: activeMission),
                workload: workload,
                configuration: configuration
            )
            visualizationRun = VisualizationRun(
                workload: workload,
                configuration: configuration,
                result: result,
                baselineResult: nil
            )
        } catch {
            visualizationRun = nil
            movementMessage = "The simulation preview could not be prepared."
        }
    }

    func dismissRecoveryMessage() {
        recoveryMessage = nil
    }

    private func restore() {
        isRestoring = true
        defer { isRestoring = false }
        do {
            guard let save = try store.load() else { return }
            hasValidSave = save.hasEnteredLaboratory
            playerPosition = save.playerPosition
            laboratoryState = LaboratorySessionState(
                playerTile: Self.tile(from: save.playerPosition),
                discoveredObjects: save.discoveredObjectIDs,
                engineerIntroductionSeen: save.engineerIntroductionSeen
            )
            soundEnabled = save.soundEnabled
            missionEngine = MissionEngine(progress: save.missionProgress)
            activeMission = missionEngine.progress.currentMissionID.rawValue
            if save.missionProgress.lifecycle == .running {
                persistCheckpoint()
            }
        } catch {
            hasValidSave = false
            playerPosition = .initial
            laboratoryState = .initial
            recoveryMessage = "Saved progress could not be read, so MeOS started new progress safely."
        }
    }

    private func persistCheckpoint() {
        do {
            try store.save(ShellSave(
                hasEnteredLaboratory: hasValidSave,
                playerPosition: playerPosition,
                discoveredObjectIDs: laboratoryState.discoveredObjects,
                engineerIntroductionSeen: laboratoryState.engineerIntroductionSeen,
                soundEnabled: soundEnabled,
                missionProgress: missionEngine.durableProgress
            ))
        } catch {
            recoveryMessage = "Progress could not be saved. Your latest changes may not survive if MeOS closes."
        }
    }

    private func updateNearbyObject() {
        nearbyObjectID = InteractionManager(world: laboratoryWorld)
            .nearestEnabledObject(to: laboratoryState.playerTile, mission: activeMission)?.id
    }

    private func openDestination(for object: LaboratoryObject) {
        if object.id == .systemEngineer {
            presentedPanel = .mission
        } else if object.id == .server && activeMission == MissionID.sequentialProcessing.rawValue {
            presentedPanel = .sequentialMission
        } else if object.id == .server && activeMission == MissionID.workerConcurrency.rawValue {
            presentedPanel = .workerMission
        } else if activeMission == MissionID.databaseStorage.rawValue,
                  object.id == .server || object.id == .databaseSlotA {
            presentedPanel = .databaseMission
        } else if activeMission == MissionID.infrastructureScaling.rawValue,
                  [.server, .databaseSlotB, .infrastructureSlotA, .infrastructureSlotB].contains(object.id) {
            presentedPanel = .infrastructureMission
        } else if activeMission == MissionID.systemDiagnostics.rawValue,
                  object.id == .monitoringTerminal {
            presentedPanel = .diagnosticMission
        } else if let component = object.component {
            presentedPanel = .system(component)
        }
    }

    private func databaseDefinition() throws -> MissionDefinition {
        guard activeMission == MissionID.databaseStorage.rawValue,
              let definition = missionEngine.catalog.definition(for: .databaseStorage) else {
            throw MissionEngineError.missionUnavailable(.databaseStorage)
        }
        return definition
    }

    private func ensureDatabaseSession() throws {
        _ = try databaseDefinition()
        if missionEngine.session?.missionID != .databaseStorage {
            try missionEngine.start(.databaseStorage)
        }
    }

    private func databaseComponents(connected: Bool) -> [SystemNode] {
        let database = SystemNode(id: "primary-database", type: .primaryDatabase, capacity: databaseMission.capacity)
        let server = SystemNode(id: "server", type: .applicationServer, connections: connected ? [database.id] : [])
        return [server, database]
    }

    private func infrastructureDefinition() throws -> MissionDefinition {
        guard activeMission == MissionID.infrastructureScaling.rawValue,
              let definition = missionEngine.catalog.definition(for: .infrastructureScaling) else {
            throw MissionEngineError.missionUnavailable(.infrastructureScaling)
        }
        return definition
    }

    private func ensureInfrastructureSession() throws {
        _ = try infrastructureDefinition()
        if missionEngine.session?.missionID != .infrastructureScaling {
            try missionEngine.start(.infrastructureScaling)
        }
    }

    private func diagnosticDefinition() throws -> MissionDefinition {
        guard activeMission == MissionID.systemDiagnostics.rawValue,
              let definition = missionEngine.catalog.definition(for: .systemDiagnostics) else {
            throw MissionEngineError.missionUnavailable(.systemDiagnostics)
        }
        return definition
    }

    private func ensureDiagnosticSession() throws {
        _ = try diagnosticDefinition()
        if missionEngine.session?.missionID != .systemDiagnostics {
            try missionEngine.start(.systemDiagnostics)
        }
    }

    private static func position(from tile: GridPoint) -> PlayerPosition {
        PlayerPosition(
            x: Double(tile.x) / Double(LaboratoryWorld.columns - 1),
            y: Double(tile.y) / Double(LaboratoryWorld.rows - 1)
        )
    }

    private static func tile(from position: PlayerPosition) -> GridPoint {
        GridPoint(
            x: min(max(Int((position.x * Double(LaboratoryWorld.columns - 1)).rounded()), 1), LaboratoryWorld.columns - 2),
            y: min(max(Int((position.y * Double(LaboratoryWorld.rows - 1)).rounded()), 1), LaboratoryWorld.rows - 2)
        )
    }
}
