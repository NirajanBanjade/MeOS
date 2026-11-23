import SpriteKit

/// Event-projected simulation renderer. It never runs the engine or changes mission state.
@MainActor
final class SimulationScene: SKScene {
    private var requestNodes: [RequestID: SKNode] = [:]
    private var workerNodes: [WorkerID: SKNode] = [:]
    private var systemNodes: [NodeID: SKNode] = [:]
    private var lastState = SimulationRenderState()

    override init(size: CGSize = CGSize(width: 900, height: 300)) {
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.045, green: 0.08, blue: 0.14, alpha: 1)
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { nil }

    func render(_ state: SimulationRenderState, reduceMotion: Bool) {
        guard state != lastState else { return }
        if state.presentedEventCount < lastState.presentedEventCount { removeProjectedNodes() }
        lastState = state

        let nodes = state.orderedNodes
        for (index, nodeState) in nodes.enumerated() {
            let node = systemNodes[nodeState.id] ?? makeSystemNode(nodeState)
            systemNodes[nodeState.id] = node
            if node.parent == nil { addChild(node) }
            node.position = CGPoint(x: 105 + CGFloat(index) * 145, y: 220)
            updateSystemNode(node, state: nodeState)
        }

        for (index, workerState) in state.orderedWorkers.enumerated() {
            let node = workerNodes[workerState.id] ?? makeWorkerNode(workerState.id)
            workerNodes[workerState.id] = node
            if node.parent == nil { addChild(node) }
            node.position = CGPoint(x: 120 + CGFloat(index) * 150, y: 125)
            updateWorkerNode(node, state: workerState)
        }

        for requestState in state.orderedRequests {
            let node = requestNodes[requestState.id] ?? makeRequestNode(requestState.id)
            requestNodes[requestState.id] = node
            if node.parent == nil { addChild(node) }
            updateRequestNode(node, state: requestState, allRequests: state.orderedRequests, reduceMotion: reduceMotion)
        }
    }

    private func updateRequestNode(
        _ node: SKNode,
        state: RequestRenderState,
        allRequests: [RequestRenderState],
        reduceMotion: Bool
    ) {
        let index = allRequests.firstIndex(where: { $0.id == state.id }) ?? 0
        var destination = CGPoint(x: 70 + CGFloat(index) * 75, y: 45)
        if let workerID = state.workerID, let worker = workerNodes[workerID], [.assigned, .waiting, .running].contains(state.status) {
            destination = CGPoint(x: worker.position.x, y: worker.position.y - 48)
        } else if let nodeID = state.nodeID, let system = systemNodes[nodeID], state.status == .database {
            destination = CGPoint(x: system.position.x, y: system.position.y - 48)
        }
        node.removeAllActions()
        if reduceMotion {
            node.position = destination
            node.run(.sequence([.fadeAlpha(to: 0.35, duration: 0.04), .fadeAlpha(to: 1, duration: 0.04)]))
        } else {
            node.run(.move(to: destination, duration: 0.2))
        }
        (node.childNode(withName: "status") as? SKLabelNode)?.text = state.status.label.uppercased()
        (node.childNode(withName: "body") as? SKShapeNode)?.fillColor = color(for: state.status)
    }

    private func updateWorkerNode(_ node: SKNode, state: WorkerRenderState) {
        (node.childNode(withName: "status") as? SKLabelNode)?.text = state.isUsingCPU ? "◆ CPU ACTIVE" : (state.requestID == nil ? "◇ IDLE" : "◆ WORKING")
        (node.childNode(withName: "body") as? SKShapeNode)?.strokeColor = state.isUsingCPU ? .systemYellow : .systemCyan
    }

    private func updateSystemNode(_ node: SKNode, state: NodeRenderState) {
        (node.childNode(withName: "status") as? SKLabelNode)?.text = "\(state.activity.label.uppercased()) · \(state.detail)"
        (node.childNode(withName: "body") as? SKShapeNode)?.strokeColor = color(for: state.activity)
    }

    private func makeRequestNode(_ id: RequestID) -> SKNode {
        let root = SKNode()
        root.name = "request:\(id.rawValue)"
        let body = SKShapeNode(rectOf: CGSize(width: 60, height: 38), cornerRadius: 9)
        body.name = "body"
        body.fillColor = .systemBlue
        body.strokeColor = .white
        body.lineWidth = 2
        root.addChild(body)
        let identity = SKLabelNode(text: id.rawValue)
        identity.fontName = "AvenirNext-Bold"
        identity.fontSize = 11
        identity.fontColor = .white
        identity.verticalAlignmentMode = .center
        root.addChild(identity)
        let status = SKLabelNode(text: "READY")
        status.name = "status"
        status.fontName = "AvenirNext-DemiBold"
        status.fontSize = 7
        status.fontColor = .white
        status.position = CGPoint(x: 0, y: -29)
        root.addChild(status)
        root.zPosition = 10
        return root
    }

    private func makeWorkerNode(_ id: WorkerID) -> SKNode {
        let root = SKNode()
        let body = SKShapeNode(circleOfRadius: 27)
        body.name = "body"
        body.fillColor = .systemIndigo.withAlphaComponent(0.35)
        body.strokeColor = .systemCyan
        body.lineWidth = 3
        root.addChild(body)
        let label = SKLabelNode(text: id.rawValue.uppercased())
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 9
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        root.addChild(label)
        let status = SKLabelNode(text: "◇ IDLE")
        status.name = "status"
        status.fontName = "AvenirNext-DemiBold"
        status.fontSize = 8
        status.fontColor = .white
        status.position = CGPoint(x: 0, y: -40)
        root.addChild(status)
        return root
    }

    private func makeSystemNode(_ state: NodeRenderState) -> SKNode {
        let root = SKNode()
        let body = SKShapeNode(rectOf: CGSize(width: 120, height: 56), cornerRadius: 12)
        body.name = "body"
        body.fillColor = .systemTeal.withAlphaComponent(0.2)
        body.strokeColor = .systemTeal
        body.lineWidth = 3
        root.addChild(body)
        let label = SKLabelNode(text: nodeLabel(state.type).uppercased())
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 10
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        root.addChild(label)
        let status = SKLabelNode(text: "IDLE")
        status.name = "status"
        status.fontName = "AvenirNext-DemiBold"
        status.fontSize = 7
        status.fontColor = .white
        status.position = CGPoint(x: 0, y: -40)
        root.addChild(status)
        return root
    }

    private func removeProjectedNodes() {
        requestNodes.values.forEach { $0.removeFromParent() }
        workerNodes.values.forEach { $0.removeFromParent() }
        systemNodes.values.forEach { $0.removeFromParent() }
        requestNodes.removeAll()
        workerNodes.removeAll()
        systemNodes.removeAll()
        lastState = SimulationRenderState()
    }

    private func color(for status: VisualRequestStatus) -> SKColor {
        switch status {
        case .submitted, .assigned: .systemBlue
        case .queued, .waiting: .systemOrange
        case .running, .database: .systemPurple
        case .completed: .systemGreen
        case .failed, .rejected: .systemRed
        }
    }

    private func color(for activity: VisualNodeActivity) -> SKColor {
        switch activity {
        case .idle: .systemTeal
        case .active, .synchronized: .systemCyan
        case .hit: .systemGreen
        case .miss, .stale: .systemOrange
        case .failed: .systemRed
        }
    }

    private func nodeLabel(_ type: SystemNodeType) -> String {
        switch type {
        case .client: "Client"
        case .loadBalancer: "Router"
        case .applicationServer: "Server"
        case .cpu: "CPU"
        case .primaryDatabase: "Database"
        case .readReplica: "Replica"
        case .cache: "Cache"
        }
    }
}
