import Foundation

protocol ShellSaving {
    func load() throws -> ShellSave?
    func save(_ value: ShellSave) throws
    func loadSoundEnabled() -> Bool
    func saveSoundEnabled(_ enabled: Bool)
}

enum ShellSaveError: Error, Equatable {
    case unsupportedVersion
    case invalidData
}

struct UserDefaultsShellStore: ShellSaving {
    private let defaults: UserDefaults
    private let saveKey = "meos.shell.save"
    private let soundKey = "meos.sound.enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> ShellSave? {
        guard let data = defaults.data(forKey: saveKey) else { return nil }
        guard let value = try? JSONDecoder().decode(ShellSave.self, from: data) else {
            throw ShellSaveError.invalidData
        }
        guard (ShellSave.oldestSupportedVersion...ShellSave.supportedVersion).contains(value.schemaVersion) else {
            throw ShellSaveError.unsupportedVersion
        }
        var migrated = value
        migrated.schemaVersion = ShellSave.supportedVersion
        return migrated
    }

    func save(_ value: ShellSave) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: saveKey)
    }

    func loadSoundEnabled() -> Bool {
        defaults.object(forKey: soundKey) == nil ? true : defaults.bool(forKey: soundKey)
    }

    func saveSoundEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: soundKey)
    }
}

struct AtomicFileShellStore: ShellSaving {
    private let fileURL: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let soundKey = "meos.sound.enabled"
    private let legacySaveKey = "meos.shell.save"

    init(
        fileURL: URL = Self.defaultSaveURL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.fileManager = fileManager
    }

    static var defaultSaveURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeOS", isDirectory: true)
            .appendingPathComponent("progress-v2.json", isDirectory: false)
    }

    static func removeDefaultSave(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: defaultSaveURL)
    }

    func load() throws -> ShellSave? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            guard let legacyData = defaults.data(forKey: legacySaveKey) else { return nil }
            var migrated = try decode(legacyData)
            migrated.schemaVersion = ShellSave.supportedVersion
            try save(migrated)
            return migrated
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ShellSaveError.invalidData
        }
        var value = try decode(data)
        let storedVersion = value.schemaVersion
        value.schemaVersion = ShellSave.supportedVersion
        if storedVersion < ShellSave.supportedVersion {
            try save(value)
        }
        return value
    }

    func save(_ value: ShellSave) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var current = value
        current.schemaVersion = ShellSave.supportedVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(current).write(to: fileURL, options: [.atomic])
    }

    func loadSoundEnabled() -> Bool {
        defaults.object(forKey: soundKey) == nil ? true : defaults.bool(forKey: soundKey)
    }

    func saveSoundEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: soundKey)
    }

    private func decode(_ data: Data) throws -> ShellSave {
        guard let value = try? JSONDecoder().decode(ShellSave.self, from: data) else {
            throw ShellSaveError.invalidData
        }
        guard (ShellSave.oldestSupportedVersion...ShellSave.supportedVersion).contains(value.schemaVersion) else {
            throw ShellSaveError.unsupportedVersion
        }
        return value
    }
}

