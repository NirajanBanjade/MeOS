import SwiftUI

struct MissionPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelContainer(
            title: "Mission Briefing",
            context: "Understand the system before changing it.",
            onClose: model.closePanel
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                DialogPanel(
                    speaker: "System Engineer",
                    message: "Our application server handles requests one at a time. Inspect it to see where new requests wait."
                )
                section("Current objective", text: model.currentObjective, icon: "scope")
                section("Permitted actions", text: "Inspect the Server, review components, or return to the laboratory.", icon: "hand.tap")
                HStack {
                    ResourceCounter(available: 1, total: 1)
                    Spacer()
                    StatusBadge(text: "Ready to inspect", kind: .ready)
                }
                MeOSPrimaryButton(title: "Inspect Server", icon: ComponentKind.server.icon) {
                    model.replacePanel(with: .system(.server))
                }
                .accessibilityIdentifier("mission.primaryAction")
                if !model.completedMissionDefinitions.isEmpty {
                    section("Replay completed missions", text: "Replays use each mission’s clean baseline without changing achievements or later progress.", icon: "arrow.counterclockwise")
                    ForEach(model.completedMissionDefinitions) { definition in
                        MeOSSecondaryButton(title: "Replay Mission \(definition.id.rawValue): \(definition.title)", icon: "play.circle.fill") {
                            try? model.replayMission(definition.id)
                        }
                        .accessibilityHint("Starts a clean replay and preserves all completed missions and unlocks")
                        .accessibilityIdentifier("mission.replay.\(definition.id.rawValue)")
                    }
                }
            }
        }
    }
}

struct SystemPanel: View {
    @ObservedObject var model: AppModel
    let component: ComponentKind

    var body: some View {
        PanelContainer(
            title: component.name,
            context: "Component inspection",
            onClose: model.closePanel
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                MeOSCard {
                    HStack(alignment: .top, spacing: MeOSSpace.md) {
                        Image(systemName: component.icon)
                            .font(.system(size: 44))
                            .foregroundStyle(MeOSColor.cyan)
                            .frame(width: 64)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                            Text(component.name).font(.title3.weight(.bold)).foregroundStyle(MeOSColor.text)
                            Text(component.purpose).foregroundStyle(MeOSColor.secondaryText)
                            Text(component.missionRole).font(.subheadline).foregroundStyle(MeOSColor.text)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                section("Permitted actions", text: "Preview this component’s configuration context or review its glossary entry.", icon: "slider.horizontal.3")
                HStack {
                    ResourceCounter(available: component == .server ? 1 : 0, total: 3)
                    Spacer()
                    StatusBadge(text: component == .server ? "Available" : "Locked for a later mission", kind: component == .server ? .ready : .attention)
                }
                HStack {
                    MeOSSecondaryButton(title: "Open Glossary", icon: "books.vertical.fill") {
                        model.replacePanel(with: .glossary)
                    }
                    Spacer()
                }
                MeOSPrimaryButton(title: "Preview System Result", icon: "chart.bar.fill") {
                    model.replacePanel(with: .results)
                }
                .accessibilityHint("Shows the reusable results presentation without completing a mission")
                .accessibilityIdentifier("system.primaryAction")
            }
        }
    }
}

struct ResultsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelContainer(
            title: "System Results",
            context: "Preview data · no mission progress awarded",
            onClose: model.closePanel
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                HStack(spacing: MeOSSpace.sm) {
                    MetricTile(label: "Completed", value: "0", icon: "checkmark.circle")
                    MetricTile(label: "Queue", value: "Ready", icon: "rectangle.stack")
                    MetricTile(label: "Latency", value: "—", icon: "timer")
                }
                StatusBadge(text: "Preview only", kind: .attention)
                section("What happened", text: "No workload has run yet, so the engine has produced no metrics.", icon: "info.circle")
                section("Why it happened", text: "Results are calculated from simulation events. Empty input remains an explicit empty state.", icon: "lightbulb")
                section("Permitted actions", text: "Return to the laboratory or retry when a mission workload is available.", icon: "arrow.triangle.2.circlepath")
                MeOSPrimaryButton(title: "Return to Laboratory", icon: "arrow.uturn.backward") {
                    model.closePanel()
                }
                .accessibilityIdentifier("results.primaryAction")
            }
        }
    }
}

struct PausePanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelContainer(
            title: "Paused",
            context: "The laboratory is waiting exactly where you left it.",
            closeTitle: "Resume",
            onClose: model.closePanel
        ) {
            VStack(spacing: MeOSSpace.md) {
                StatusBadge(text: "World paused safely", kind: .ready)
                Text("Permitted actions")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MeOSPrimaryButton(title: "Resume Laboratory", icon: "play.fill") { model.closePanel() }
                    .accessibilityIdentifier("pause.resume")
                pauseAction("Component Glossary", icon: "books.vertical.fill", id: "pause.glossary", panel: .glossary)
                pauseAction("Settings", icon: "gearshape.fill", id: "pause.settings", panel: .settings)
                pauseAction("Credits", icon: "person.3.fill", id: "pause.credits", panel: .credits)
                MeOSSecondaryButton(title: "Return to Home", icon: "house.fill") { model.returnHome() }
                    .accessibilityIdentifier("pause.home")
            }
        }
    }

    private func pauseAction(_ title: String, icon: String, id: String, panel: AppPanel) -> some View {
        MeOSSecondaryButton(title: title, icon: icon) { model.replacePanel(with: panel) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(id)
    }
}

struct GlossaryPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelContainer(
            title: "Component Glossary",
            context: "Replayable beginner guide to every system component.",
            onClose: model.closePanel
        ) {
            LazyVStack(spacing: MeOSSpace.md) {
                ForEach(ComponentKind.allCases) { component in
                    MeOSCard {
                        HStack(alignment: .top, spacing: MeOSSpace.md) {
                            Image(systemName: component.icon)
                                .font(.title)
                                .foregroundStyle(MeOSColor.cyan)
                                .frame(width: 42)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: MeOSSpace.xs) {
                                Text(component.name).font(.headline).foregroundStyle(MeOSColor.text)
                                Text("What it is: \(component.purpose)")
                                Text("In MeOS: \(component.missionRole)")
                                Label("Visual states: \(component.visualStates)", systemImage: "eye.fill")
                                    .font(.caption)
                                    .foregroundStyle(MeOSColor.secondaryText)
                            }
                            .font(.subheadline)
                            .foregroundStyle(MeOSColor.text)
                            Spacer()
                            Button("Inspect") { model.replacePanel(with: .system(component)) }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(MeOSColor.cyan)
                                .accessibilityLabel("Inspect \(component.name)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                MeOSCard {
                    VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                        Label("Laboratory teaching cards", systemImage: "map.fill")
                            .font(.headline)
                            .foregroundStyle(MeOSColor.cyan)
                        Text("Replay the first-discovery explanation for any object in the shared room.")
                            .font(.subheadline)
                            .foregroundStyle(MeOSColor.secondaryText)
                        ForEach(model.laboratoryWorld.objects) { object in
                            Button {
                                model.replacePanel(with: .teaching(object.id))
                            } label: {
                                Label("Replay \(object.name) teaching card", systemImage: object.icon)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(MeOSColor.text)
                            .accessibilityHint(object.purpose)
                            .accessibilityIdentifier("glossary.replay.\(object.id.rawValue)")
                        }
                    }
                }
            }
        }
    }
}

struct TeachingCardPanel: View {
    @ObservedObject var model: AppModel
    let objectID: LaboratoryObjectID

    private var object: LaboratoryObject? { model.laboratoryWorld.object(objectID) }

    var body: some View {
        PanelContainer(
            title: object?.name ?? "Laboratory component",
            context: "First-discovery teaching card",
            onClose: model.closePanel
        ) {
            if let object {
                VStack(alignment: .leading, spacing: MeOSSpace.md) {
                    MeOSCard {
                        HStack(alignment: .top, spacing: MeOSSpace.md) {
                            Image(systemName: object.icon)
                                .font(.system(size: 42))
                                .foregroundStyle(MeOSColor.cyan)
                                .frame(width: 58)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                                Text("What it is").font(.headline).foregroundStyle(MeOSColor.cyan)
                                Text(object.purpose).foregroundStyle(MeOSColor.text)
                                Text("Why this mission uses it").font(.headline).foregroundStyle(MeOSColor.cyan)
                                Text(object.missionRole).foregroundStyle(MeOSColor.secondaryText)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Label("Replay this card any time from the Component Glossary.", systemImage: "arrow.counterclockwise.circle")
                        .font(.subheadline)
                        .foregroundStyle(MeOSColor.secondaryText)
                    MeOSPrimaryButton(
                        title: object.id == .systemEngineer ? "Continue Conversation" : "Inspect \(object.name)",
                        icon: "hand.tap.fill"
                    ) {
                        model.continueFromTeaching(object.id)
                    }
                    .accessibilityIdentifier("teaching.continue.\(object.id.rawValue)")
                }
            } else {
                Text("This teaching card is unavailable.")
            }
        }
    }
}

struct AccessibleInteractionsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelContainer(
            title: "Accessible Interactions",
            context: "Direct route to the same objects and actions available in the laboratory.",
            onClose: model.closePanel
        ) {
            LazyVStack(spacing: MeOSSpace.md) {
                ForEach(model.laboratoryWorld.objects) { object in
                    let enabled = object.isEnabled(in: model.activeMission)
                    MeOSCard {
                        VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                            HStack {
                                Label(object.name, systemImage: object.icon)
                                    .font(.headline)
                                    .foregroundStyle(MeOSColor.text)
                                    .accessibilityIdentifier("accessible.name.\(object.id.rawValue)")
                                Spacer()
                                StatusBadge(
                                    text: enabled ? "Available" : "Unlocks in Mission \(object.minimumMission)",
                                    kind: enabled ? .ready : .attention
                                )
                            }
                            Text(object.purpose)
                                .font(.subheadline)
                                .foregroundStyle(MeOSColor.secondaryText)
                            Text(object.missionRole)
                                .font(.caption)
                                .foregroundStyle(MeOSColor.text)
                            MeOSSecondaryButton(title: enabled ? "Inspect \(object.name)" : "Unavailable", icon: enabled ? "hand.tap.fill" : "lock.fill") {
                                model.requestInteraction(with: object.id, accessible: true)
                            }
                            .disabled(!enabled)
                            .accessibilityLabel(enabled ? "Inspect \(object.name) directly" : "\(object.name) unavailable")
                            .accessibilityValue(enabled ? "Available" : "Unlocks in Mission \(object.minimumMission)")
                            .accessibilityHint(object.purpose)
                            .accessibilityIdentifier("accessible.\(object.id.rawValue)")
                        }
                    }
                }
            }
        }
    }
}

struct CreditsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelContainer(
            title: "Credits",
            context: "People, tools, and bundled resources",
            onClose: model.closePanel
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                section("MeOS", text: "Designed as an offline educational adventure for learning how computer systems work.", icon: "cpu")
                section("Visual resources", text: "Interface symbols use Apple SF Symbols. Feature 1 uses programmatically drawn laboratory placeholders and Apple-native fonts.", icon: "paintpalette")
                section("Technology", text: "Built with Swift, SwiftUI, SpriteKit, Foundation, XCTest, and XCUITest. No third-party runtime packages or remote resources.", icon: "hammer")
            }
        }
    }
}

struct SettingsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelContainer(
            title: "Settings",
            context: "Preferences never block progress.",
            onClose: model.closePanel
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                MeOSCard {
                    Toggle(isOn: $model.soundEnabled) {
                        Label("Sound effects", systemImage: model.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.headline)
                            .foregroundStyle(MeOSColor.text)
                    }
                    .tint(MeOSColor.cyan)
                    .accessibilityLabel("Sound effects")
                    .accessibilityValue(model.soundEnabled ? "On" : "Off")
                    .accessibilityHint("Optional sound never affects mission progress")
                    .accessibilityIdentifier("settings.soundToggle")
                }
                section("Motion", text: "MeOS follows the iPad Reduce Motion setting. Nonessential travel transitions become fades while state and outcome feedback remain visible.", icon: "figure.walk.motion")
                section("Offline play", text: "All shell content and resources are bundled. MeOS does not make network requests.", icon: "wifi.slash")
            }
        }
    }
}

@ViewBuilder
@MainActor
private func section(_ title: String, text: String, icon: String) -> some View {
    MeOSCard {
        VStack(alignment: .leading, spacing: MeOSSpace.xs) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(MeOSColor.cyan)
            Text(text)
                .font(.body)
                .foregroundStyle(MeOSColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
}

