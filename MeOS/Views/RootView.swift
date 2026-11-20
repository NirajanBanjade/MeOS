import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                switch model.screen {
                case .home:
                    HomeView(model: model)
                case .laboratory:
                    GameView(model: model)
                }
            }
            .accessibilityHidden(model.presentedPanel != nil)

            if let panel = model.presentedPanel {
                MeOSColor.ink.opacity(0.72)
                    .ignoresSafeArea()
                    .onTapGesture { }
                    .accessibilityHidden(true)
                panelView(panel)
                    .transition(MeOSMotion.transition(reduceMotion: reduceMotion || model.forceReduceMotion))
                    .zIndex(2)
            }
        }
        .animation((reduceMotion || model.forceReduceMotion) ? .linear(duration: 0.01) : .easeOut(duration: MeOSMotion.standard), value: model.presentedPanel?.id)
        .alert("Progress recovery", isPresented: Binding(
            get: { model.recoveryMessage != nil },
            set: { if !$0 { model.dismissRecoveryMessage() } }
        )) {
            Button("OK", role: .cancel) { model.dismissRecoveryMessage() }
        } message: {
            Text(model.recoveryMessage ?? "")
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func panelView(_ panel: AppPanel) -> some View {
        switch panel {
        case .mission: MissionPanel(model: model)
        case .system(let component): SystemPanel(model: model, component: component)
        case .results: ResultsPanel(model: model)
        case .pause: PausePanel(model: model)
        case .glossary: GlossaryPanel(model: model)
        case .credits: CreditsPanel(model: model)
        case .settings: SettingsPanel(model: model)
        case .teaching(let id): TeachingCardPanel(model: model, objectID: id)
        case .accessibleInteractions: AccessibleInteractionsPanel(model: model)
        }
    }
}

