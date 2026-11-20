import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MeOSShellCore
#else
@testable import MeOS
#endif

@Suite("Versioned shell persistence")
struct ShellStoreTests {
    @Test("Fresh storage has no Continue progress")
    func freshStorage() throws {
        let defaults = isolatedDefaults()
        let store = UserDefaultsShellStore(defaults: defaults)
        #expect(try store.load() == nil)
        #expect(store.loadSoundEnabled())
    }

    @Test("A valid checkpoint round trips every shell field")
    func roundTrip() throws {
        let defaults = isolatedDefaults()
        let store = UserDefaultsShellStore(defaults: defaults)
        let node = SystemNode(id: "primary", type: .primaryDatabase, connections: ["server"])
        let progress = MissionProgress(
            currentMissionID: .systemDiagnostics,
            completedMissionIDs: Set(MissionID.allCases),
            titleAwarded: true,
            lifecycle: .paused,
            configuredComponents: [node]
        )
        let expected = ShellSave(
            hasEnteredLaboratory: true,
            playerPosition: .init(x: 0.4, y: 0.7),
            discoveredObjectIDs: [.server, .monitoringTerminal],
            engineerIntroductionSeen: true,
            soundEnabled: false,
            missionProgress: progress
        )
        try store.save(expected)
        #expect(try store.load() == expected)
    }

    @Test("Version one data migrates deterministically")
    func migration() throws {
        let defaults = isolatedDefaults()
        let oldJSON: [String: Any] = [
            "schemaVersion": 1,
            "hasEnteredLaboratory": true,
            "playerPosition": ["x": 0.25, "y": 0.75]
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: oldJSON), forKey: "meos.shell.save")
        let migrated = try #require(try UserDefaultsShellStore(defaults: defaults).load())
        #expect(migrated.schemaVersion == ShellSave.supportedVersion)
        #expect(migrated.playerPosition == .init(x: 0.25, y: 0.75))
        #expect(migrated.missionProgress == .initial)
        #expect(migrated.soundEnabled)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let atomicStore = AtomicFileShellStore(fileURL: url, defaults: defaults)
        let atomicallyMigrated = try #require(try atomicStore.load())
        #expect(atomicallyMigrated == migrated)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try JSONDecoder().decode(ShellSave.self, from: Data(contentsOf: url)).schemaVersion == ShellSave.supportedVersion)
    }

    @Test("Atomic file storage replaces a complete versioned checkpoint")
    func atomicFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let defaults = isolatedDefaults()
        let store = AtomicFileShellStore(fileURL: url, defaults: defaults)
        #expect(try store.load() == nil)

        var first = ShellSave(hasEnteredLaboratory: true, playerPosition: .initial)
        try store.save(first)
        #expect(try store.load() == first)

        first.playerPosition = .init(x: 0.8, y: 0.2)
        first.soundEnabled = false
        first.missionProgress.currentMissionID = .databaseStorage
        first.missionProgress.completedMissionIDs = [.sequentialProcessing, .workerConcurrency]
        try store.save(first)
        #expect(try store.load() == first)
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.lastPathComponent) == ["progress.json"])
    }

    @Test("Atomic storage safely handles corrupt and future files")
    func atomicInvalidData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("progress.json")
        let store = AtomicFileShellStore(fileURL: url, defaults: isolatedDefaults())
        try Data("broken".utf8).write(to: url)
        #expect(throws: ShellSaveError.invalidData) { try store.load() }

        let future = ShellSave(schemaVersion: 99, hasEnteredLaboratory: true, playerPosition: .initial)
        try JSONEncoder().encode(future).write(to: url)
        #expect(throws: ShellSaveError.unsupportedVersion) { try store.load() }
    }

    @Test("Corrupt and future saves fail safely")
    func invalidSaves() throws {
        let defaults = isolatedDefaults()
        defaults.set(Data("not json".utf8), forKey: "meos.shell.save")
        let store = UserDefaultsShellStore(defaults: defaults)
        #expect(throws: ShellSaveError.invalidData) { try store.load() }

        let future = ShellSave(schemaVersion: 99, hasEnteredLaboratory: true, playerPosition: .initial)
        defaults.set(try JSONEncoder().encode(future), forKey: "meos.shell.save")
        #expect(throws: ShellSaveError.unsupportedVersion) { try store.load() }
    }

    @Test("Sound can be muted independently")
    func soundPreference() {
        let defaults = isolatedDefaults()
        let store = UserDefaultsShellStore(defaults: defaults)
        store.saveSoundEnabled(false)
        #expect(!store.loadSoundEnabled())
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "MeOSTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

