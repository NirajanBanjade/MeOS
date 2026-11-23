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
        activeMission = id.rawValue
        updateNearbyObject()
        closePanel()
    }

    func updateConfiguredComponents(_ components: [SystemNode]) throws {
        try missionEngine.updateConfiguredComponents(components)
        persistCheckpoint()
    }

    func handleBackgrounding() {
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
        try? store.save(ShellSave(
            hasEnteredLaboratory: hasValidSave,
            playerPosition: playerPosition,
            discoveredObjectIDs: laboratoryState.discoveredObjects,
            engineerIntroductionSeen: laboratoryState.engineerIntroductionSeen,
            soundEnabled: soundEnabled,
            missionProgress: missionEngine.durableProgress
        ))
    }

    private func updateNearbyObject() {
        nearbyObjectID = InteractionManager(world: laboratoryWorld)
            .nearestEnabledObject(to: laboratoryState.playerTile, mission: activeMission)?.id
    }

    private func openDestination(for object: LaboratoryObject) {
        if object.id == .systemEngineer {
            presentedPanel = .mission
        } else if let component = object.component {
            presentedPanel = .system(component)
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

