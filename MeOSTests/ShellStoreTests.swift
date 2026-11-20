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
        let expected = ShellSave(hasEnteredLaboratory: true, playerPosition: .init(x: 0.4, y: 0.7))
        try store.save(expected)
        #expect(try store.load() == expected)
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

