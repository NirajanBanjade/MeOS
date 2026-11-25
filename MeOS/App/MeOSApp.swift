import SwiftUI

@main
struct MeOSApp: App {
    @StateObject private var model: AppModel

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UI_TEST_FRESH_START") {
            AtomicFileShellStore.removeDefaultSave()
            UserDefaults.standard.removeObject(forKey: "meos.shell.save")
            UserDefaults.standard.removeObject(forKey: "meos.sound.enabled")
        }
        if arguments.contains("-UI_TEST_MISSION_3") {
            let progress = MissionProgress(
                currentMissionID: .databaseStorage,
                completedMissionIDs: [.sequentialProcessing, .workerConcurrency],
                titleAwarded: false,
                lifecycle: .completed,
                configuredComponents: []
            )
            try? AtomicFileShellStore().save(ShellSave(
                hasEnteredLaboratory: true,
                playerPosition: .initial,
                engineerIntroductionSeen: true,
                soundEnabled: true,
                missionProgress: progress
            ))
        }
        if arguments.contains("-UI_TEST_MISSION_4") {
            let progress = MissionProgress(
                currentMissionID: .infrastructureScaling,
                completedMissionIDs: [.sequentialProcessing, .workerConcurrency, .databaseStorage],
                titleAwarded: false,
                lifecycle: .completed,
                configuredComponents: []
            )
            try? AtomicFileShellStore().save(ShellSave(
                hasEnteredLaboratory: true,
                playerPosition: .initial,
                engineerIntroductionSeen: true,
                soundEnabled: true,
                missionProgress: progress
            ))
        }
        if arguments.contains("-UI_TEST_MISSION_5") {
            let progress = MissionProgress(
                currentMissionID: .systemDiagnostics,
                completedMissionIDs: [.sequentialProcessing, .workerConcurrency, .databaseStorage, .infrastructureScaling],
                titleAwarded: false,
                lifecycle: .completed,
                configuredComponents: []
            )
            try? AtomicFileShellStore().save(ShellSave(
                hasEnteredLaboratory: true,
                playerPosition: .initial,
                engineerIntroductionSeen: true,
                soundEnabled: true,
                missionProgress: progress
            ))
        }
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

