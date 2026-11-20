import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MeOSShellCore
#else
@testable import MeOS
#endif

@Suite("Laboratory world and interactions")
struct LaboratoryWorldTests {
    let world = LaboratoryWorld.standard

    @Test("Every required object has unique identity and complete teaching copy")
    func objectMetadataIsComplete() {
        #expect(world.objects.count == LaboratoryObjectID.allCases.count)
        #expect(Set(world.objects.map(\.id)).count == world.objects.count)
        #expect(Set(world.objects.map(\.name)).count == world.objects.count)
        for object in world.objects {
            #expect(!object.name.isEmpty)
            #expect(!object.icon.isEmpty)
            #expect(!object.purpose.isEmpty)
            #expect(!object.missionRole.isEmpty)
            #expect(!object.interactionTiles.isEmpty)
            #expect(object.interactionTiles.allSatisfy(world.isWalkable))
        }
    }

    @Test("A safe route reaches every workstation without entering an obstacle")
    func routesReachEveryObject() {
        let controller = PlayerController(world: world)
        let start = LaboratorySessionState.initial.playerTile
        for object in world.objects {
            guard case .route(let route) = controller.route(from: start, to: object) else {
                Issue.record("No route to \(object.name)")
                continue
            }
            #expect(route.allSatisfy(world.isWalkable))
            #expect(route.last.map(object.interactionTiles.contains) ?? object.interactionTiles.contains(start))
            for (first, second) in zip([start] + route, route) {
                #expect(first.manhattanDistance(to: second) == 1)
            }
        }
    }

    @Test("Blocked tiles stop at a nearest valid tile and outside destinations reject")
    func blockedAndInvalidDestinations() {
        let controller = PlayerController(world: world)
        let start = LaboratorySessionState.initial.playerTile
        let blocked = GridPoint(x: 17, y: 8)
        guard case .route(let route) = controller.route(from: start, to: blocked) else {
            Issue.record("Expected a route to the edge of the server")
            return
        }
        #expect(route.last != blocked)
        #expect(route.allSatisfy(world.isWalkable))
        #expect(route.last?.manhattanDistance(to: blocked) == 1)
        #expect(controller.route(from: start, to: .init(x: -1, y: 3)) == .rejected(.outsideRoom))
        #expect(controller.route(from: start, to: .init(x: 0, y: 0)) == .rejected(.unreachable))
    }

    @Test("Routes are deterministic when a destination is replaced")
    func routeReplacementIsDeterministic() {
        let controller = PlayerController(world: world)
        let start = LaboratorySessionState.initial.playerTile
        let first = controller.route(from: start, to: .init(x: 14, y: 6))
        let replacementA = controller.route(from: start, to: .init(x: 2, y: 9))
        let replacementB = controller.route(from: start, to: .init(x: 2, y: 9))
        #expect(first != replacementA)
        #expect(replacementA == replacementB)
    }

    @Test("Range and mission availability are state driven")
    func interactionResolution() throws {
        let manager = InteractionManager(world: world)
        let server = try #require(world.object(.server))
        let nearby = try #require(server.interactionTiles.first)
        #expect(manager.resolve(.server, player: nearby, mission: 1) == .available(.server))
        #expect(manager.resolve(.server, player: LaboratorySessionState.initial.playerTile, mission: 1) == .moveCloser(.server))
        #expect(manager.resolve(.monitoringTerminal, player: nearby, mission: 1) == .disabled(.monitoringTerminal, minimumMission: 5))
        #expect(manager.resolve(.monitoringTerminal, player: try #require(world.object(.monitoringTerminal)?.interactionTiles.first), mission: 5) == .available(.monitoringTerminal))
    }
}

@MainActor
@Suite("Laboratory application bridge")
struct LaboratoryAppModelTests {
    @Test("Every workstation can be reached and opens its corresponding destination")
    func everyWorkstationOpens() throws {
        let model = AppModel(store: LaboratoryMemoryStore())
        model.updateMission(5)
        for object in model.laboratoryWorld.objects {
            model.updatePlayerTile(try #require(object.interactionTiles.first))
            model.requestInteraction(with: object.id)
            #expect(model.presentedPanel == .teaching(object.id))
            model.continueFromTeaching(object.id)
            if object.id == .systemEngineer {
                #expect(model.presentedPanel == .mission)
            } else {
                #expect(model.presentedPanel == object.component.map(AppPanel.system))
            }
            model.closePanel()
        }
    }

    @Test("First discovery teaches once and accessible action opens the same destination")
    func discoveryAndAccessibleRoute() {
        let store = LaboratoryMemoryStore()
        let model = AppModel(store: store)
        let original = model.playerPosition

        model.requestInteraction(with: .server, accessible: true)
        #expect(model.presentedPanel == .teaching(.server))
        #expect(model.laboratoryState.discoveredObjects.contains(.server))
        #expect(model.playerPosition == original)

        model.continueFromTeaching(.server)
        #expect(model.presentedPanel == .system(.server))
        model.closePanel()
        model.requestInteraction(with: .server, accessible: true)
        #expect(model.presentedPanel == .system(.server))
        #expect(model.playerPosition == original)
    }

    @Test("Mission state filters objects and overlay close preserves the confirmed tile")
    func missionFilteringAndPreservation() {
        let model = AppModel(store: LaboratoryMemoryStore())
        let tile = GridPoint(x: 10, y: 6)
        model.updatePlayerTile(tile)
        model.requestInteraction(with: .monitoringTerminal, accessible: true)
        #expect(model.presentedPanel == nil)
        #expect(model.movementMessage == "Monitoring Terminal unlocks in Mission 5.")

        model.updateMission(5)
        model.requestInteraction(with: .monitoringTerminal, accessible: true)
        #expect(model.presentedPanel == .teaching(.monitoringTerminal))
        model.closePanel()
        #expect(model.laboratoryState.playerTile == tile)
    }

    @Test("Discovery and stable position survive a save round trip")
    func persistenceRoundTrip() {
        let store = LaboratoryMemoryStore()
        let first = AppModel(store: store)
        first.enterLaboratory()
        first.acknowledgeEngineerIntroduction()
        first.updatePlayerTile(.init(x: 10, y: 6))
        first.requestInteraction(with: .server, accessible: true)

        let restored = AppModel(store: store)
        #expect(restored.laboratoryState.playerTile == .init(x: 10, y: 6))
        #expect(restored.laboratoryState.discoveredObjects.contains(.server))
        #expect(!restored.shouldShowEngineerIntroduction)
    }
}

private final class LaboratoryMemoryStore: ShellSaving {
    var value: ShellSave?
    var sound = true

    func load() throws -> ShellSave? { value }
    func save(_ value: ShellSave) throws { self.value = value }
    func loadSoundEnabled() -> Bool { sound }
    func saveSoundEnabled(_ enabled: Bool) { sound = enabled }
}
