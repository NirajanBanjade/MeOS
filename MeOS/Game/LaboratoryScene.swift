import SpriteKit
import UIKit

@MainActor
protocol LaboratorySceneWorldDelegate: AnyObject {
    func laboratoryScene(_ scene: LaboratoryScene, didConfirmPlayerTile tile: GridPoint)
    func laboratoryScene(_ scene: LaboratoryScene, didRequestInteraction id: LaboratoryObjectID)
    func laboratoryScene(_ scene: LaboratoryScene, didReport message: String)
}

/// The single reusable laboratory renderer. Routing and interaction decisions come
/// from pure Swift controllers; SpriteKit only interpolates confirmed model states.
@MainActor
final class LaboratoryScene: SKScene {
    private let world: LaboratoryWorld
    private let playerController: PlayerController
    private let interactionManager: InteractionManager
    private var confirmedPlayerTile: GridPoint
    private var activeMission: Int
    private var playerNode: SKNode?
    private var objectNodes: [LaboratoryObjectID: SKNode] = [:]

    weak var worldDelegate: (any LaboratorySceneWorldDelegate)?

    private let tileSize = CGSize(width: 52, height: 50)
    private let gridOrigin = CGPoint(x: 111, y: 84)

    init(playerTile: GridPoint, activeMission: Int, world: LaboratoryWorld = .standard) {
        self.world = world
        playerController = PlayerController(world: world)
        interactionManager = InteractionManager(world: world)
        confirmedPlayerTile = world.isWalkable(playerTile) ? playerTile : LaboratorySessionState.initial.playerTile
        self.activeMission = activeMission
        super.init(size: CGSize(width: 1366, height: 768))
        scaleMode = .aspectFill
        backgroundColor = SKColor(red: 0.035, green: 0.065, blue: 0.11, alpha: 1)
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        isUserInteractionEnabled = true
        buildRoom()
    }

    func updateMission(_ mission: Int) {
        activeMission = min(max(mission, 1), 5)
        world.objects.forEach(updateAppearance)
    }

    func setWorldPaused(_ paused: Bool) {
        isPaused = paused
        view?.isPaused = paused
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPaused, let location = touches.first?.location(in: self) else { return }
        if let objectID = nodes(at: location).compactMap(objectID(for:)).first {
            handleObjectTap(objectID)
            return
        }
        guard let destination = gridPoint(at: location) else {
            worldDelegate?.laboratoryScene(self, didReport: "That destination is outside the laboratory.")
            return
        }
        follow(playerController.route(from: confirmedPlayerTile, to: destination))
    }

    private func handleObjectTap(_ objectID: LaboratoryObjectID) {
        switch interactionManager.resolve(objectID, player: confirmedPlayerTile, mission: activeMission) {
        case .available(let id):
            worldDelegate?.laboratoryScene(self, didRequestInteraction: id)
        case .moveCloser(let id):
            guard let object = world.object(id) else { return }
            follow(playerController.route(from: confirmedPlayerTile, to: object))
        case .disabled(let id, let mission):
            let name = world.object(id)?.name ?? "This component"
            worldDelegate?.laboratoryScene(self, didReport: "\(name) unlocks in Mission \(mission).")
        case .unknown:
            worldDelegate?.laboratoryScene(self, didReport: "That object is not available.")
        }
    }

    private func follow(_ plan: MovementPlan) {
        guard let playerNode else { return }
        playerNode.removeAction(forKey: "player-route")
        playerNode.position = point(for: confirmedPlayerTile)

        switch plan {
        case .rejected(.outsideRoom):
            worldDelegate?.laboratoryScene(self, didReport: "That destination is outside the laboratory.")
        case .rejected(.unreachable):
            worldDelegate?.laboratoryScene(self, didReport: "No safe route reaches that destination.")
        case .route(let route):
            guard !route.isEmpty else { return }
            let actions = route.flatMap { [weak self] tile -> [SKAction] in
                guard let self else { return [] }
                let move = SKAction.move(to: self.point(for: tile), duration: 0.12)
                move.timingMode = .linear
                let confirm = SKAction.run { [weak self] in
                    guard let self else { return }
                    self.confirmedPlayerTile = tile
                    self.worldDelegate?.laboratoryScene(self, didConfirmPlayerTile: tile)
                }
                return [move, confirm]
            }
            playerNode.run(.sequence(actions), withKey: "player-route")
        }
    }

    private func buildRoom() {
        let floorSize = CGSize(width: tileSize.width * CGFloat(LaboratoryWorld.columns), height: tileSize.height * CGFloat(LaboratoryWorld.rows))
        let floor = SKShapeNode(rectOf: floorSize, cornerRadius: 32)
        floor.fillColor = SKColor(red: 0.07, green: 0.12, blue: 0.19, alpha: 1)
        floor.strokeColor = SKColor(red: 0.15, green: 0.55, blue: 0.62, alpha: 0.55)
        floor.lineWidth = 4
        floor.position = CGPoint(x: gridOrigin.x + floorSize.width / 2, y: gridOrigin.y + floorSize.height / 2)
        floor.zPosition = -10
        addChild(floor)

        let grid = SKShapeNode(path: gridPath())
        grid.strokeColor = .white.withAlphaComponent(0.035)
        grid.lineWidth = 1
        grid.zPosition = -9
        addChild(grid)

        for object in world.objects {
            let node = makeObjectNode(object)
            node.position = point(for: object.location)
            objectNodes[object.id] = node
            addChild(node)
            updateAppearance(of: object)
        }

        let player = makeCharacter(color: .systemCyan, label: "YOU")
        player.name = "player"
        player.position = point(for: confirmedPlayerTile)
        player.zPosition = 20
        addChild(player)
        playerNode = player
    }

    private func makeObjectNode(_ object: LaboratoryObject) -> SKNode {
        let root = SKNode()
        root.name = "object:\(object.id.rawValue)"
        root.zPosition = 5

        if object.id == .systemEngineer {
            let character = makeCharacter(color: .systemIndigo, label: object.name.uppercased())
            character.name = root.name
            root.addChild(character)
            return root
        }

        let machine = SKShapeNode(rectOf: CGSize(width: 128, height: 82), cornerRadius: 16)
        machine.name = root.name
        machine.fillColor = .systemTeal.withAlphaComponent(0.2)
        machine.strokeColor = .systemTeal
        machine.lineWidth = 3
        root.addChild(machine)

        if let image = UIImage(systemName: object.icon) {
            let icon = SKSpriteNode(texture: SKTexture(image: image))
            icon.name = root.name
            icon.color = .white
            icon.colorBlendFactor = 1
            icon.size = CGSize(width: 28, height: 28)
            icon.position = CGPoint(x: 0, y: 9)
            root.addChild(icon)
        }

        let nameplate = SKLabelNode(text: object.name.uppercased())
        nameplate.name = root.name
        nameplate.fontName = "AvenirNext-Bold"
        nameplate.fontSize = 10
        nameplate.fontColor = .white
        nameplate.verticalAlignmentMode = .center
        nameplate.position = CGPoint(x: 0, y: -23)
        root.addChild(nameplate)

        let status = SKLabelNode(text: "")
        status.name = "status"
        status.fontName = "AvenirNext-DemiBold"
        status.fontSize = 9
        status.fontColor = .white
        status.position = CGPoint(x: 0, y: -54)
        root.addChild(status)
        return root
    }

    private func updateAppearance(of object: LaboratoryObject) {
        guard let root = objectNodes[object.id] else { return }
        let enabled = object.isEnabled(in: activeMission)
        root.alpha = enabled ? 1 : 0.48
        if let status = root.childNode(withName: "status") as? SKLabelNode {
            status.text = enabled ? "◆ AVAILABLE" : "◇ MISSION \(object.minimumMission)"
        }
    }

    private func makeCharacter(color: SKColor, label: String) -> SKNode {
        let root = SKNode()
        let body = SKShapeNode(circleOfRadius: 24)
        body.fillColor = color
        body.strokeColor = .white.withAlphaComponent(0.8)
        body.lineWidth = 3
        root.addChild(body)

        let name = SKLabelNode(text: label)
        name.fontName = "AvenirNext-DemiBold"
        name.fontSize = 11
        name.fontColor = .white
        name.position = CGPoint(x: 0, y: 34)
        root.addChild(name)
        return root
    }

    private func objectID(for node: SKNode) -> LaboratoryObjectID? {
        var candidate: SKNode? = node
        while let current = candidate {
            if let name = current.name, name.hasPrefix("object:") {
                return LaboratoryObjectID(rawValue: String(name.dropFirst("object:".count)))
            }
            candidate = current.parent
        }
        return nil
    }

    private func point(for tile: GridPoint) -> CGPoint {
        CGPoint(x: gridOrigin.x + (CGFloat(tile.x) + 0.5) * tileSize.width, y: gridOrigin.y + (CGFloat(tile.y) + 0.5) * tileSize.height)
    }

    private func gridPoint(at point: CGPoint) -> GridPoint? {
        let x = Int((point.x - gridOrigin.x) / tileSize.width)
        let y = Int((point.y - gridOrigin.y) / tileSize.height)
        guard (0..<LaboratoryWorld.columns).contains(x), (0..<LaboratoryWorld.rows).contains(y) else { return nil }
        return GridPoint(x: x, y: y)
    }

    private func gridPath() -> CGPath {
        let path = CGMutablePath()
        for x in 0...LaboratoryWorld.columns {
            let coordinate = gridOrigin.x + CGFloat(x) * tileSize.width
            path.move(to: CGPoint(x: coordinate, y: gridOrigin.y))
            path.addLine(to: CGPoint(x: coordinate, y: gridOrigin.y + CGFloat(LaboratoryWorld.rows) * tileSize.height))
        }
        for y in 0...LaboratoryWorld.rows {
            let coordinate = gridOrigin.y + CGFloat(y) * tileSize.height
            path.move(to: CGPoint(x: gridOrigin.x, y: coordinate))
            path.addLine(to: CGPoint(x: gridOrigin.x + CGFloat(LaboratoryWorld.columns) * tileSize.width, y: coordinate))
        }
        return path
    }
}

extension AppModel: LaboratorySceneWorldDelegate {
    func laboratoryScene(_ scene: LaboratoryScene, didConfirmPlayerTile tile: GridPoint) {
        updatePlayerTile(tile)
    }

    func laboratoryScene(_ scene: LaboratoryScene, didRequestInteraction id: LaboratoryObjectID) {
        requestInteraction(with: id)
    }

    func laboratoryScene(_ scene: LaboratoryScene, didReport message: String) {
        reportMovementIssue(message)
    }
}
