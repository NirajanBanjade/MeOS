import Foundation

struct GridPoint: Codable, Equatable, Hashable, Sendable {
    let x: Int
    let y: Int

    func manhattanDistance(to other: GridPoint) -> Int {
        abs(x - other.x) + abs(y - other.y)
    }
}

enum LaboratoryObjectID: String, CaseIterable, Codable, Identifiable, Sendable {
    case systemEngineer
    case server
    case cpuStation
    case databaseSlotA
    case databaseSlotB
    case infrastructureSlotA
    case infrastructureSlotB
    case requestGenerator
    case monitoringTerminal

    var id: String { rawValue }
}

struct LaboratoryObject: Identifiable, Equatable, Sendable {
    let id: LaboratoryObjectID
    let name: String
    let icon: String
    let purpose: String
    let missionRole: String
    let component: ComponentKind?
    let location: GridPoint
    let interactionTiles: [GridPoint]
    let minimumMission: Int

    func isEnabled(in mission: Int) -> Bool {
        mission >= minimumMission
    }
}

struct LaboratoryWorld: Equatable, Sendable {
    static let columns = 22
    static let rows = 12

    let blockedTiles: Set<GridPoint>
    let objects: [LaboratoryObject]

    static let standard: LaboratoryWorld = {
        let objects = [
            LaboratoryObject(
                id: .systemEngineer,
                name: "System Engineer",
                icon: "person.crop.circle.badge.questionmark",
                purpose: "Guides your investigation and explains what the current mission is asking you to learn.",
                missionRole: "The System Engineer points out the Server before you begin Mission 1.",
                component: nil,
                location: .init(x: 8, y: 5),
                interactionTiles: [.init(x: 7, y: 5), .init(x: 9, y: 5), .init(x: 8, y: 4), .init(x: 8, y: 6)],
                minimumMission: 1
            ),
            LaboratoryObject(
                id: .server,
                name: "Server",
                icon: ComponentKind.server.icon,
                purpose: ComponentKind.server.purpose,
                missionRole: ComponentKind.server.missionRole,
                component: .server,
                location: .init(x: 17, y: 8),
                interactionTiles: [.init(x: 15, y: 8), .init(x: 16, y: 7), .init(x: 17, y: 6), .init(x: 18, y: 7)],
                minimumMission: 1
            ),
            LaboratoryObject(
                id: .cpuStation,
                name: "CPU Station",
                icon: ComponentKind.cpu.icon,
                purpose: ComponentKind.cpu.purpose,
                missionRole: ComponentKind.cpu.missionRole,
                component: .cpu,
                location: .init(x: 13, y: 3),
                interactionTiles: [.init(x: 11, y: 3), .init(x: 12, y: 4), .init(x: 13, y: 5), .init(x: 14, y: 4)],
                minimumMission: 2
            ),
            LaboratoryObject(
                id: .databaseSlotA,
                name: "Database Slot A",
                icon: ComponentKind.database.icon,
                purpose: "An installation bay for the primary database that stores key-and-value records.",
                missionRole: ComponentKind.database.missionRole,
                component: .database,
                location: .init(x: 17, y: 3),
                interactionTiles: [.init(x: 15, y: 3), .init(x: 16, y: 4), .init(x: 17, y: 5), .init(x: 18, y: 4)],
                minimumMission: 3
            ),
            LaboratoryObject(
                id: .databaseSlotB,
                name: "Database Slot B",
                icon: ComponentKind.readReplica.icon,
                purpose: "A second database bay reserved for a read replica in later experiments.",
                missionRole: ComponentKind.readReplica.missionRole,
                component: .readReplica,
                location: .init(x: 19, y: 3),
                interactionTiles: [.init(x: 19, y: 5), .init(x: 20, y: 4)],
                minimumMission: 4
            ),
            LaboratoryObject(
                id: .infrastructureSlotA,
                name: "Infrastructure Slot A",
                icon: ComponentKind.cache.icon,
                purpose: "An expansion bay where an architecture upgrade such as a cache can be installed.",
                missionRole: ComponentKind.cache.missionRole,
                component: .cache,
                location: .init(x: 5, y: 8),
                interactionTiles: [.init(x: 3, y: 8), .init(x: 4, y: 7), .init(x: 5, y: 6), .init(x: 6, y: 7)],
                minimumMission: 4
            ),
            LaboratoryObject(
                id: .infrastructureSlotB,
                name: "Infrastructure Slot B",
                icon: ComponentKind.router.icon,
                purpose: "An expansion bay for routing or additional application-server equipment.",
                missionRole: ComponentKind.router.missionRole,
                component: .router,
                location: .init(x: 8, y: 8),
                interactionTiles: [.init(x: 7, y: 7), .init(x: 8, y: 6), .init(x: 9, y: 7), .init(x: 10, y: 7)],
                minimumMission: 4
            ),
            LaboratoryObject(
                id: .requestGenerator,
                name: "Request Generator",
                icon: ComponentKind.requestGenerator.icon,
                purpose: ComponentKind.requestGenerator.purpose,
                missionRole: ComponentKind.requestGenerator.missionRole,
                component: .requestGenerator,
                location: .init(x: 4, y: 3),
                interactionTiles: [.init(x: 2, y: 3), .init(x: 3, y: 4), .init(x: 4, y: 5), .init(x: 5, y: 4)],
                minimumMission: 1
            ),
            LaboratoryObject(
                id: .monitoringTerminal,
                name: "Monitoring Terminal",
                icon: ComponentKind.monitoringTerminal.icon,
                purpose: ComponentKind.monitoringTerminal.purpose,
                missionRole: ComponentKind.monitoringTerminal.missionRole,
                component: .monitoringTerminal,
                location: .init(x: 11, y: 9),
                interactionTiles: [.init(x: 10, y: 7), .init(x: 11, y: 7), .init(x: 12, y: 7), .init(x: 13, y: 9)],
                minimumMission: 5
            )
        ]

        var blocked = Set<GridPoint>()
        for x in 0..<columns {
            blocked.insert(.init(x: x, y: 0))
            blocked.insert(.init(x: x, y: rows - 1))
        }
        for y in 0..<rows {
            blocked.insert(.init(x: 0, y: y))
            blocked.insert(.init(x: columns - 1, y: y))
        }
        let footprints: [[GridPoint]] = [
            [.init(x: 16, y: 8), .init(x: 17, y: 8), .init(x: 18, y: 8), .init(x: 16, y: 9), .init(x: 17, y: 9), .init(x: 18, y: 9)],
            [.init(x: 12, y: 2), .init(x: 13, y: 2), .init(x: 14, y: 2), .init(x: 12, y: 3), .init(x: 13, y: 3), .init(x: 14, y: 3)],
            [.init(x: 16, y: 2), .init(x: 17, y: 2), .init(x: 18, y: 2), .init(x: 16, y: 3), .init(x: 17, y: 3), .init(x: 18, y: 3)],
            [.init(x: 19, y: 2), .init(x: 20, y: 2), .init(x: 19, y: 3), .init(x: 20, y: 3)],
            [.init(x: 4, y: 8), .init(x: 5, y: 8), .init(x: 6, y: 8), .init(x: 4, y: 9), .init(x: 5, y: 9), .init(x: 6, y: 9)],
            [.init(x: 7, y: 8), .init(x: 8, y: 8), .init(x: 9, y: 8), .init(x: 7, y: 9), .init(x: 8, y: 9), .init(x: 9, y: 9)],
            [.init(x: 3, y: 2), .init(x: 4, y: 2), .init(x: 5, y: 2), .init(x: 3, y: 3), .init(x: 4, y: 3), .init(x: 5, y: 3)],
            [.init(x: 10, y: 8), .init(x: 11, y: 8), .init(x: 12, y: 8), .init(x: 10, y: 9), .init(x: 11, y: 9), .init(x: 12, y: 9)]
        ]
        footprints.flatMap { $0 }.forEach { blocked.insert($0) }
        return LaboratoryWorld(blockedTiles: blocked, objects: objects)
    }()

    func object(_ id: LaboratoryObjectID) -> LaboratoryObject? {
        objects.first { $0.id == id }
    }

    func isWalkable(_ point: GridPoint) -> Bool {
        (0..<Self.columns).contains(point.x) &&
        (0..<Self.rows).contains(point.y) &&
        !blockedTiles.contains(point)
    }
}

enum MovementRejection: Equatable, Sendable {
    case outsideRoom
    case unreachable
}

enum MovementPlan: Equatable, Sendable {
    case route([GridPoint])
    case rejected(MovementRejection)
}

struct PlayerController: Sendable {
    let world: LaboratoryWorld

    init(world: LaboratoryWorld = .standard) {
        self.world = world
    }

    func route(from start: GridPoint, to requestedDestination: GridPoint) -> MovementPlan {
        guard (0..<LaboratoryWorld.columns).contains(requestedDestination.x),
              (0..<LaboratoryWorld.rows).contains(requestedDestination.y) else {
            return .rejected(.outsideRoom)
        }
        guard world.isWalkable(start) else { return .rejected(.unreachable) }

        let destinations: Set<GridPoint>
        if world.isWalkable(requestedDestination) {
            destinations = [requestedDestination]
        } else {
            destinations = Set(neighbors(of: requestedDestination).filter(world.isWalkable))
        }
        guard !destinations.isEmpty else { return .rejected(.unreachable) }
        return shortestRoute(from: start, destinations: destinations)
    }

    func route(from start: GridPoint, to object: LaboratoryObject) -> MovementPlan {
        shortestRoute(from: start, destinations: Set(object.interactionTiles.filter(world.isWalkable)))
    }

    private func shortestRoute(from start: GridPoint, destinations: Set<GridPoint>) -> MovementPlan {
        if destinations.contains(start) { return .route([]) }
        var queue = [start]
        var cursor = 0
        var previous: [GridPoint: GridPoint] = [:]
        var visited: Set<GridPoint> = [start]

        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for next in neighbors(of: current) where world.isWalkable(next) && visited.insert(next).inserted {
                previous[next] = current
                if destinations.contains(next) {
                    var route = [next]
                    var step = next
                    while let parent = previous[step], parent != start {
                        route.append(parent)
                        step = parent
                    }
                    return .route(route.reversed())
                }
                queue.append(next)
            }
        }
        return .rejected(.unreachable)
    }

    private func neighbors(of point: GridPoint) -> [GridPoint] {
        [
            .init(x: point.x, y: point.y + 1),
            .init(x: point.x + 1, y: point.y),
            .init(x: point.x, y: point.y - 1),
            .init(x: point.x - 1, y: point.y)
        ]
    }
}

enum InteractionResolution: Equatable, Sendable {
    case available(LaboratoryObjectID)
    case moveCloser(LaboratoryObjectID)
    case disabled(LaboratoryObjectID, minimumMission: Int)
    case unknown
}

struct InteractionManager: Sendable {
    let world: LaboratoryWorld

    init(world: LaboratoryWorld = .standard) {
        self.world = world
    }

    func resolve(_ id: LaboratoryObjectID, player: GridPoint, mission: Int) -> InteractionResolution {
        guard let object = world.object(id) else { return .unknown }
        guard object.isEnabled(in: mission) else {
            return .disabled(id, minimumMission: object.minimumMission)
        }
        return isInRange(player: player, of: object) ? .available(id) : .moveCloser(id)
    }

    func isInRange(player: GridPoint, of object: LaboratoryObject) -> Bool {
        object.interactionTiles.contains(player) || player.manhattanDistance(to: object.location) <= 2
    }

    func nearestEnabledObject(to player: GridPoint, mission: Int) -> LaboratoryObject? {
        world.objects
            .filter { $0.isEnabled(in: mission) && isInRange(player: player, of: $0) }
            .sorted {
                let lhsDistance = player.manhattanDistance(to: $0.location)
                let rhsDistance = player.manhattanDistance(to: $1.location)
                return lhsDistance == rhsDistance ? $0.id.rawValue < $1.id.rawValue : lhsDistance < rhsDistance
            }
            .first
    }
}

struct LaboratorySessionState: Equatable, Sendable {
    var playerTile: GridPoint
    var discoveredObjects: Set<LaboratoryObjectID>
    var engineerIntroductionSeen: Bool

    static let initial = LaboratorySessionState(
        playerTile: .init(x: 3, y: 6),
        discoveredObjects: [],
        engineerIntroductionSeen: false
    )
}
