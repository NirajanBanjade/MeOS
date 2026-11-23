import Foundation

struct PlayerPosition: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    static let initial = PlayerPosition(x: 3.0 / 21.0, y: 6.0 / 11.0)
}

struct ShellSave: Codable, Equatable, Sendable {
    static let supportedVersion = 2
    static let oldestSupportedVersion = 1

    var schemaVersion: Int = supportedVersion
    var hasEnteredLaboratory: Bool
    var playerPosition: PlayerPosition
    var discoveredObjectIDs: Set<LaboratoryObjectID> = []
    var engineerIntroductionSeen = false
    var soundEnabled = true
    var missionProgress: MissionProgress = .initial

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hasEnteredLaboratory, playerPosition, discoveredObjectIDs, engineerIntroductionSeen
        case soundEnabled, missionProgress
    }

    init(
        schemaVersion: Int = supportedVersion,
        hasEnteredLaboratory: Bool,
        playerPosition: PlayerPosition,
        discoveredObjectIDs: Set<LaboratoryObjectID> = [],
        engineerIntroductionSeen: Bool = false,
        soundEnabled: Bool = true,
        missionProgress: MissionProgress = .initial
    ) {
        self.schemaVersion = schemaVersion
        self.hasEnteredLaboratory = hasEnteredLaboratory
        self.playerPosition = playerPosition
        self.discoveredObjectIDs = discoveredObjectIDs
        self.engineerIntroductionSeen = engineerIntroductionSeen
        self.soundEnabled = soundEnabled
        self.missionProgress = missionProgress
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        hasEnteredLaboratory = try values.decode(Bool.self, forKey: .hasEnteredLaboratory)
        playerPosition = try values.decode(PlayerPosition.self, forKey: .playerPosition)
        discoveredObjectIDs = try values.decodeIfPresent(Set<LaboratoryObjectID>.self, forKey: .discoveredObjectIDs) ?? []
        engineerIntroductionSeen = try values.decodeIfPresent(Bool.self, forKey: .engineerIntroductionSeen) ?? false
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        missionProgress = try values.decodeIfPresent(MissionProgress.self, forKey: .missionProgress) ?? .initial
    }
}

enum AppScreen: Equatable, Sendable {
    case home
    case laboratory
}

enum AppPanel: Identifiable, Equatable, Sendable {
    case mission
    case sequentialMission
    case workerMission
    case system(ComponentKind)
    case results
    case pause
    case glossary
    case credits
    case settings
    case teaching(LaboratoryObjectID)
    case accessibleInteractions

    var id: String {
        switch self {
        case .mission: "mission"
        case .sequentialMission: "sequential-mission"
        case .workerMission: "worker-mission"
        case .system(let component): "system-\(component.rawValue)"
        case .results: "results"
        case .pause: "pause"
        case .glossary: "glossary"
        case .credits: "credits"
        case .settings: "settings"
        case .teaching(let id): "teaching-\(id.rawValue)"
        case .accessibleInteractions: "accessible-interactions"
        }
    }
}

enum ComponentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case server
    case cpu
    case worker
    case database
    case requestGenerator
    case monitoringTerminal
    case cache
    case readReplica
    case router

    var id: String { rawValue }

    var name: String {
        switch self {
        case .server: "Server"
        case .cpu: "CPU Station"
        case .worker: "Worker"
        case .database: "Database"
        case .requestGenerator: "Request Generator"
        case .monitoringTerminal: "Monitoring Terminal"
        case .cache: "Cache"
        case .readReplica: "Read Replica"
        case .router: "Router"
        }
    }

    var icon: String {
        switch self {
        case .server: "server.rack"
        case .cpu: "cpu"
        case .worker: "person.fill.gearshape"
        case .database: "cylinder.split.1x2"
        case .requestGenerator: "rectangle.stack.badge.plus"
        case .monitoringTerminal: "waveform.path.ecg.rectangle"
        case .cache: "bolt.horizontal.circle"
        case .readReplica: "cylinder.split.1x2.fill"
        case .router: "point.3.connected.trianglepath.dotted"
        }
    }

    var purpose: String {
        switch self {
        case .server: "Accepts requests and gives each one to an available worker."
        case .cpu: "Provides the processing capacity workers share for CPU-heavy work."
        case .worker: "Handles one request at a time through its waiting and processing phases."
        case .database: "Stores key-and-value records so information can be retrieved later."
        case .requestGenerator: "Creates a repeatable workload for testing the system."
        case .monitoringTerminal: "Shows measured system evidence such as latency, load, and queue pressure."
        case .cache: "Keeps recently read data close to the server for faster repeat reads."
        case .readReplica: "Copies primary database data and serves eligible read requests."
        case .router: "Directs incoming requests toward connected application servers."
        }
    }

    var missionRole: String {
        switch self {
        case .server: "Mission 1 uses the Server to reveal why a single busy worker creates a queue."
        case .cpu: "Later missions use the CPU Station to show why more workers do not create unlimited processing capacity."
        case .worker: "Mission 2 compares worker counts while keeping the workload identical."
        case .database: "Mission 3 installs and connects the Database to store persistent records."
        case .requestGenerator: "Missions use the Request Generator to replay identical inputs for fair comparisons."
        case .monitoringTerminal: "Mission 5 asks you to inspect evidence here before choosing a repair."
        case .cache: "Mission 4 offers the Cache as one measured way to improve repeated reads."
        case .readReplica: "Mission 4 offers the Read Replica to spread eligible read traffic."
        case .router: "Mission 4 requires routing before a second server can receive traffic."
        }
    }

    var visualStates: String {
        switch self {
        case .server: "Offline, ready, busy, or attention needed."
        case .cpu: "Available, processing, or capacity limited."
        case .worker: "Idle, waiting, processing, or complete."
        case .database: "Empty slot, disconnected, connected, reading, writing, or full."
        case .requestGenerator: "Empty, prepared, or dispatching requests."
        case .monitoringTerminal: "Normal, alert, or showing evidence."
        case .cache: "Empty, cache miss, cache hit, or invalidated."
        case .readReplica: "Synchronizing, current, stale, or unavailable."
        case .router: "Disconnected, connected, or routing traffic."
        }
    }
}

