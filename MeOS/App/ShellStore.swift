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
        guard value.schemaVersion == ShellSave.supportedVersion else {
            throw ShellSaveError.unsupportedVersion
        }
        return value
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

