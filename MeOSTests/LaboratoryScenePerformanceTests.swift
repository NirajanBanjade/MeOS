import SpriteKit
import XCTest
@testable import MeOS

@MainActor
final class LaboratoryScenePerformanceTests: XCTestCase {
    func testRepresentativeSceneTargetsSixtyFramesPerSecond() {
        let scene = LaboratoryScene(playerTile: LaboratorySessionState.initial.playerTile, activeMission: 5)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1366, height: 768))
        view.presentScene(scene)

        XCTAssertEqual(view.preferredFramesPerSecond, 60)
        XCTAssertFalse(scene.children.isEmpty)
        XCTAssertNil(scene.physicsWorld.contactDelegate)
    }

    func testRoutingCostAndResultsDoNotDependOnRenderFrameRate() {
        let world = LaboratoryWorld.standard
        let controller = PlayerController(world: world)
        let start = LaboratorySessionState.initial.playerTile
        let expected = world.objects.map { controller.route(from: start, to: $0) }

        for simulatedFPS in [15, 30, 60, 120] {
            _ = simulatedFPS
            XCTAssertEqual(world.objects.map { controller.route(from: start, to: $0) }, expected)
        }

        measure {
            for _ in 0..<250 {
                for object in world.objects {
                    _ = controller.route(from: start, to: object)
                }
            }
        }
    }
}
