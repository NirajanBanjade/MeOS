import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MeOSShellCore
#else
@testable import MeOS
#endif

@MainActor
@Suite("App shell state")
struct AppModelTests {
    @Test("Start enters once and subsequent launch offers Continue")
    func startAndContinue() {
        let store = MemoryStore()
        let model = AppModel(store: store)
        #expect(model.primaryActionTitle == "Start")

        model.enterLaboratory()
        model.enterLaboratory()
        #expect(model.screen == .laboratory)
        #expect(model.primaryActionTitle == "Continue")
        #expect(store.saveCount == 1)

        let restored = AppModel(store: store)
        #expect(restored.primaryActionTitle == "Continue")
    }

    @Test("Rapid panel commands do not replace an open panel")
    func serializesPresentation() {
        let model = AppModel(store: MemoryStore())
        model.present(.mission)
        model.present(.credits)
        #expect(model.presentedPanel == .mission)
        model.closePanel()
        #expect(model.presentedPanel == nil)
    }

    @Test("Corrupt progress explains recovery and stays on Start")
    func recovery() {
        let model = AppModel(store: FailingStore())
        #expect(model.primaryActionTitle == "Start")
        #expect(model.recoveryMessage != nil)
    }

    @Test("Every component provides beginner identity and state copy")
    func glossaryCompleteness() {
        for component in ComponentKind.allCases {
            #expect(!component.name.isEmpty)
            #expect(!component.purpose.isEmpty)
            #expect(!component.missionRole.isEmpty)
            #expect(!component.visualStates.isEmpty)
            #expect(!component.icon.isEmpty)
        }
    }

    @Test("Every presentation state can be selected without changing player position")
    func presentationReachabilityAndPositionPreservation() {
        let model = AppModel(store: MemoryStore())
        let originalPosition = model.playerPosition
        let states: [AppPanel] = [
            .mission, .system(.server), .results, .pause, .glossary, .credits, .settings,
            .teaching(.server), .accessibleInteractions
        ]
        for state in states {
            model.present(state)
            #expect(model.presentedPanel == state)
            model.closePanel()
            #expect(model.playerPosition == originalPosition)
        }
    }
}

private final class MemoryStore: ShellSaving {
    var value: ShellSave?
    var sound = true
    var saveCount = 0

    func load() throws -> ShellSave? { value }
    func save(_ value: ShellSave) throws { self.value = value; saveCount += 1 }
    func loadSoundEnabled() -> Bool { sound }
    func saveSoundEnabled(_ enabled: Bool) { sound = enabled }
}

private struct FailingStore: ShellSaving {
    func load() throws -> ShellSave? { throw ShellSaveError.invalidData }
    func save(_ value: ShellSave) throws { }
    func loadSoundEnabled() -> Bool { true }
    func saveSoundEnabled(_ enabled: Bool) { }
}

