import SwiftUI

@main
struct MeOSApp: App {
    @StateObject private var model: AppModel

    init() {
        if ProcessInfo.processInfo.arguments.contains("-UI_TEST_FRESH_START") {
            AtomicFileShellStore.removeDefaultSave()
            UserDefaults.standard.removeObject(forKey: "meos.shell.save")
            UserDefaults.standard.removeObject(forKey: "meos.sound.enabled")
        }
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

