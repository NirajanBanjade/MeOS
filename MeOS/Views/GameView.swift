import SpriteKit
import SwiftUI

struct GameView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene: LaboratoryScene

    init(model: AppModel) {
        self.model = model
        _scene = State(initialValue: LaboratoryScene(
            playerTile: model.laboratoryState.playerTile,
            activeMission: model.activeMission,
            world: model.laboratoryWorld
        ))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()
                .accessibilityLabel("MeOS laboratory")
                .accessibilityValue("Player at column \(model.laboratoryState.playerTile.x), row \(model.laboratoryState.playerTile.y)")
                .accessibilityHint("Tap a destination to walk, or use Accessible Interactions for a direct route")

            VStack(spacing: MeOSSpace.sm) {
                topBar
                if model.shouldShowEngineerIntroduction {
                    engineerIntroduction
                }
                if let message = model.movementMessage {
                    movementNotice(message)
                }
                if model.activeMission == MissionID.systemDiagnostics.rawValue,
                   !model.missionEngine.progress.completedMissionIDs.contains(.systemDiagnostics) {
                    diagnosticAlert
                }
                Spacer()
                if let nearby = model.nearbyObject {
                    proximityPrompt(nearby)
                }
                bottomBar
            }
            .padding(MeOSSpace.md)
        }
        .onAppear {
            scene.worldDelegate = model
            scene.updateMission(model.activeMission)
            scene.updateDatabaseState(installed: model.databaseMission.isInstalled, connected: model.databaseMission.isConnected)
            scene.setWorldPaused(model.presentedPanel != nil)
        }
        .onChange(of: model.presentedPanel) { _, panel in
            scene.setWorldPaused(panel != nil)
        }
        .onChange(of: model.activeMission) { _, mission in
            scene.updateMission(mission)
        }
        .onChange(of: model.databaseMission) { _, state in
            scene.updateDatabaseState(installed: state.isInstalled, connected: state.isConnected)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                scene.setWorldPaused(model.presentedPanel != nil)
            case .inactive, .background:
                scene.setWorldPaused(true)
            @unknown default:
                scene.setWorldPaused(true)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: MeOSSpace.md) {
            MeOSCard {
                VStack(alignment: .leading, spacing: MeOSSpace.xs) {
                    Text(model.missionTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MeOSColor.text)
                    Label(model.currentObjective, systemImage: "scope")
                        .font(.subheadline)
                        .foregroundStyle(MeOSColor.secondaryText)
                }
            }
            .frame(maxWidth: 610)
            Spacer()
            Button { model.present(.mission) } label: {
                Label("Briefing", systemImage: "scope")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MeOSColor.cyan)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(MeOSColor.panel, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open mission briefing")
            .accessibilityIdentifier("game.mission")
            StatusBadge(text: model.missionProgress, kind: .ready)
            Button { model.present(.pause) } label: {
                Label("Pause", systemImage: "pause.fill")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(MeOSColor.text)
                    .background(MeOSColor.panel, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause game")
            .accessibilityHint("Opens pause options and the Component Glossary")
            .accessibilityIdentifier("game.pause")
        }
    }

    private var engineerIntroduction: some View {
        HStack(spacing: MeOSSpace.sm) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(MeOSColor.cyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("System Engineer").font(.headline)
                Text("Welcome, Junior Engineer. The Server is highlighted first—inspect it to learn why requests wait.")
                    .font(.subheadline)
                    .foregroundStyle(MeOSColor.secondaryText)
            }
            Spacer()
            Button("Got it") { model.acknowledgeEngineerIntroduction() }
                .font(.headline)
                .foregroundStyle(MeOSColor.cyan)
                .accessibilityIdentifier("engineer.introduction.dismiss")
        }
        .foregroundStyle(MeOSColor.text)
        .padding(MeOSSpace.sm)
        .background(MeOSColor.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: MeOSRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("engineer.introduction")
    }

    private func movementNotice(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Dismiss") { model.dismissMovementMessage() }
        }
        .foregroundStyle(MeOSColor.text)
        .padding(MeOSSpace.sm)
        .background(MeOSColor.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: MeOSRadius.card))
        .accessibilityIdentifier("world.message")
    }

    private var diagnosticAlert: some View {
        HStack(spacing: MeOSSpace.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MeOSColor.amber)
                .accessibilityHidden(true)
            Text("SYSTEM ALERT · High response time detected. Open the Monitoring Terminal and inspect measured evidence.")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MeOSColor.text)
            Spacer()
            Button("Investigate") { model.requestInteraction(with: .monitoringTerminal, accessible: true) }
                .font(.headline)
                .foregroundStyle(MeOSColor.cyan)
                .accessibilityIdentifier("mission5.alert.investigate")
        }
        .padding(MeOSSpace.sm)
        .background(MeOSColor.panel.opacity(0.97), in: RoundedRectangle(cornerRadius: MeOSRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mission5.alert")
    }

    private func proximityPrompt(_ object: LaboratoryObject) -> some View {
        Button {
            model.requestInteraction(with: object.id)
        } label: {
            Label("\(object.name) — Tap to inspect", systemImage: object.icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(MeOSColor.text)
                .padding(.horizontal, MeOSSpace.md)
                .padding(.vertical, MeOSSpace.sm)
                .background(MeOSColor.cyan.opacity(0.24), in: Capsule())
                .overlay(Capsule().stroke(MeOSColor.cyan, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(object.name), tap to inspect")
        .accessibilityHint(object.purpose)
        .accessibilityIdentifier("proximity.\(object.id.rawValue)")
    }

    private var bottomBar: some View {
        HStack(spacing: MeOSSpace.sm) {
            MeOSSecondaryButton(title: "Accessible Interactions", icon: "list.bullet.rectangle") {
                model.present(.accessibleInteractions)
            }
            .accessibilityHint("Lists every laboratory object, its purpose, availability, and direct action")
            .accessibilityIdentifier("game.accessibleInteractions")

            Button("Inspect Server") { model.requestInteraction(with: .server, accessible: true) }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MeOSColor.cyan)
                .accessibilityLabel("Inspect Server directly")
                .accessibilityHint(model.laboratoryWorld.object(.server)?.purpose ?? "Inspect the server")
                .accessibilityIdentifier("game.server")

            Spacer()
            Label("Tap open floor to move · machines block travel", systemImage: "figure.walk.motion")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MeOSColor.secondaryText)
        }
        .padding(MeOSSpace.sm)
        .background(MeOSColor.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: MeOSRadius.card))
    }
}
