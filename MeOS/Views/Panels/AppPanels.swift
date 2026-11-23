import SpriteKit
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
                    model.replacePanel(with: model.activeMission == 1 ? .sequentialMission : (model.activeMission == 2 ? .workerMission : .system(.server)))
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

struct SequentialMissionPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var playbackTask: Task<Void, Never>?

    private var reduceMotion: Bool { systemReduceMotion || model.forceReduceMotion }

    var body: some View {
        PanelContainer(
            title: "Mission 1 · Sequential Server",
            context: "Follow five requests through one worker and identify why they wait.",
            onClose: close
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                DialogPanel(
                    speaker: "System Engineer",
                    message: "Here are five uniquely identified request cards. The Server has one worker, so watch what happens after you start it."
                )

                requestCards

                if model.sequentialMission.stage == .empty {
                    StatusBadge(text: "Queue empty", kind: .attention)
                    MeOSPrimaryButton(title: "Start Server", icon: "play.fill") { }
                        .disabled(true)
                        .accessibilityHint("Queue empty. Receive request cards before starting the server.")
                        .accessibilityIdentifier("mission1.startServer")
                    MeOSPrimaryButton(title: "Receive Five Request Cards", icon: "rectangle.stack.badge.plus") {
                        try? model.receiveSequentialRequestCards()
                    }
                    .accessibilityIdentifier("mission1.receiveCards")
                }

                if model.sequentialMission.stage == .ready {
                    MeOSPrimaryButton(title: "Start Server", icon: "play.fill") {
                        guard (try? model.startSequentialServer()) == true else { return }
                        beginPlayback()
                    }
                    .disabled(model.sequentialMission.isStartDisabled)
                    .accessibilityHint("Runs this set of request cards once; repeated taps cannot duplicate them")
                    .accessibilityIdentifier("mission1.startServer")
                }

                if model.sequentialMission.stage == .running {
                    MeOSPrimaryButton(title: "Start Server", icon: "play.fill") { }
                        .disabled(true)
                        .accessibilityHint("A run is already active; requests cannot be dispatched twice.")
                        .accessibilityIdentifier("mission1.startServer")
                }

                if let run = model.sequentialMission.run {
                    playback(run)
                    measuredMetrics(run.result)
                }

                if model.sequentialMission.stage == .identifyCause {
                    causeQuestion
                }

                if model.sequentialMission.stage == .completed {
                    completionResult
                }

                Label(model.sequentialMission.feedback, systemImage: feedbackIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MeOSColor.text)
                    .accessibilityIdentifier("mission1.feedback")
            }
        }
        .onDisappear {
            playbackTask?.cancel()
            model.pauseSequentialPresentation()
        }
    }

    private var requestCards: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                HStack {
                    Label("Request cards", systemImage: "rectangle.stack.fill")
                        .font(.headline)
                        .foregroundStyle(MeOSColor.cyan)
                    Spacer()
                    StatusBadge(
                        text: model.sequentialMission.workload.isEmpty ? "Empty" : "\(model.sequentialMission.workload.count) ready",
                        kind: model.sequentialMission.workload.isEmpty ? .attention : .ready
                    )
                }
                if model.sequentialMission.workload.isEmpty {
                    Text("Queue empty. Start Server is unavailable until requests exist.")
                        .foregroundStyle(MeOSColor.secondaryText)
                } else {
                    Text(model.sequentialMission.workload.map(\.id.rawValue).joined(separator: "  ·  "))
                        .font(.caption.monospaced())
                        .foregroundStyle(MeOSColor.text)
                        .accessibilityLabel("Request identities: \(model.sequentialMission.workload.map(\.id.rawValue).joined(separator: ", "))")
                        .accessibilityIdentifier("mission1.requestIDs")
                }
            }
        }
    }

    private func playback(_ run: VisualizationRun) -> some View {
        VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            HStack {
                StatusBadge(
                    text: model.sequentialMission.presentation?.lifecycle.rawValue.capitalized ?? "Ready",
                    kind: model.sequentialMission.stage == .identifyCause ? .complete : .ready
                )
                Spacer()
                Text("\(model.sequentialMission.renderState?.timestampMilliseconds ?? 0) ms")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(MeOSColor.text)
            }
            HStack(spacing: MeOSSpace.sm) {
                MeOSSecondaryButton(title: "Play", icon: "play.fill", action: beginPlayback)
                    .disabled(model.sequentialMission.presentation?.lifecycle == .playing || model.sequentialMission.stage != .running)
                    .accessibilityIdentifier("mission1.play")
                MeOSSecondaryButton(title: "Pause", icon: "pause.fill") {
                    playbackTask?.cancel()
                    model.pauseSequentialPresentation()
                }
                .disabled(model.sequentialMission.presentation?.lifecycle != .playing)
                .accessibilityIdentifier("mission1.pause")
                MeOSSecondaryButton(title: "Show Final Event", icon: "forward.end.fill") {
                    playbackTask?.cancel()
                    model.finishSequentialPresentation()
                }
                .disabled(model.sequentialMission.stage != .running)
                .accessibilityIdentifier("mission1.finishPresentation")
                MeOSSecondaryButton(title: "Reset Run", icon: "arrow.counterclockwise") {
                    playbackTask?.cancel()
                    try? model.resetSequentialMission()
                }
                .accessibilityIdentifier("mission1.reset")
            }
            Picker("Presentation speed", selection: Binding(
                get: { model.sequentialMission.presentation?.speed ?? .normal },
                set: model.setSequentialPresentationSpeed
            )) {
                ForEach(PresentationSpeed.allCases, id: \.rawValue) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Changes presentation speed only, never simulation timestamps or results")

            Mission1SpriteView(
                state: model.sequentialMission.renderState ?? SimulationEventProjector().baseline(
                    workload: run.workload,
                    configuration: run.configuration
                ),
                reduceMotion: reduceMotion
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: MeOSRadius.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mission 1 request animation")
            .accessibilityValue(accessibleRequestState)

            SchedulingTimelineView(
                segments: model.sequentialMission.renderState?.timeline ?? [],
                makespan: max(run.result.metrics.completionTimeMilliseconds, 1)
            )
            .frame(height: 220)
        }
    }

    private func measuredMetrics(_ result: SimulationResult) -> some View {
        let currentQueue = model.sequentialMission.renderState?.orderedRequests.filter { $0.status == .queued }.count ?? 0
        return VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            Text("Measured from the event log")
                .font(.headline)
                .foregroundStyle(MeOSColor.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: MeOSSpace.sm) {
                MetricTile(label: "Completed", value: "\(result.metrics.completed)", icon: "checkmark.circle.fill")
                MetricTile(label: "Current queue", value: "\(currentQueue)", icon: "rectangle.stack.fill")
                MetricTile(label: "Queue waiting", value: "\(result.metrics.totalQueueWaitMilliseconds) ms", icon: "hourglass")
                MetricTile(label: "Total time", value: "\(result.metrics.completionTimeMilliseconds) ms", icon: "flag.checkered")
                    .accessibilityIdentifier("mission1.metric.makespan")
                MetricTile(label: "Average latency", value: "\(Int(result.metrics.averageLatencyMilliseconds)) ms", icon: "timer")
                    .accessibilityIdentifier("mission1.metric.latency")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mission 1 measured metrics")
        .accessibilityValue("Completed \(result.metrics.completed), current queue \(currentQueue), queue waiting \(result.metrics.totalQueueWaitMilliseconds) milliseconds, total time \(result.metrics.completionTimeMilliseconds) milliseconds, average latency \(Int(result.metrics.averageLatencyMilliseconds)) milliseconds")
        .accessibilityIdentifier("mission1.metrics")
    }

    private var causeQuestion: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Label("Why did later requests wait?", systemImage: "questionmark.bubble.fill")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.cyan)
                ForEach(SequentialWaitCause.allCases) { cause in
                    MeOSSecondaryButton(title: cause.text, icon: "text.bubble.fill") {
                        _ = try? model.answerSequentialCause(cause)
                    }
                    .accessibilityIdentifier("mission1.cause.\(cause.rawValue)")
                }
            }
        }
    }

    private var completionResult: some View {
        VStack(alignment: .leading, spacing: MeOSSpace.md) {
            StatusBadge(text: "Mission complete · Worker Manager unlocked", kind: .complete)
                .accessibilityIdentifier("mission1.complete")
            section(
                "What happened",
                text: "All five requests completed in FIFO order. With one worker, each later request remained queued until the prior request’s 600 ms wait and 400 ms CPU phases finished.",
                icon: "checkmark.circle.fill"
            )
            section(
                "Why it happened",
                text: "The calculated event history records queue positions, one worker assignment at a time, and completions at 1,000, 2,000, 3,000, 4,000, and 5,000 ms.",
                icon: "lightbulb.fill"
            )
            MeOSPrimaryButton(title: "Continue to Mission 2", icon: "arrow.right.circle.fill") {
                model.closePanel()
            }
            .accessibilityIdentifier("mission1.continue")
        }
    }

    private var feedbackIcon: String {
        switch model.sequentialMission.stage {
        case .empty: "tray"
        case .ready: "rectangle.stack.badge.plus"
        case .running: "server.rack"
        case .identifyCause: "questionmark.circle.fill"
        case .completed: "checkmark.seal.fill"
        }
    }

    private var accessibleRequestState: String {
        let states = model.sequentialMission.renderState?.orderedRequests.map {
            "\($0.id.rawValue) \($0.status.label) at \($0.timestampMilliseconds) milliseconds"
        } ?? []
        return states.isEmpty ? "Five requests ready; no events presented" : states.joined(separator: ", ")
    }

    private func beginPlayback() {
        guard model.playSequentialPresentation() else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            while !Task.isCancelled,
                  model.sequentialMission.presentation?.lifecycle == .playing,
                  let presentation = model.sequentialMission.presentation,
                  presentation.eventIndex < presentation.events.count {
                let index = presentation.eventIndex
                let event = presentation.events[index]
                let previous = index == 0 ? 0 : presentation.events[index - 1].timestampMilliseconds
                let gap = max(event.timestampMilliseconds - previous, 0)
                let delay = reduceMotion ? 0 : min(Int(Double(gap) / presentation.speed.rawValue), 500)
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                else { await Task.yield() }
                guard !Task.isCancelled else { return }
                _ = model.presentNextSequentialEvent()
            }
        }
    }

    private func close() {
        playbackTask?.cancel()
        model.pauseSequentialPresentation()
        model.closePanel()
    }
}

private struct Mission1SpriteView: View {
    let state: SimulationRenderState
    let reduceMotion: Bool
    @State private var scene = SimulationScene()

    var body: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .onAppear { scene.render(state, reduceMotion: reduceMotion) }
            .onChange(of: state) { _, newState in scene.render(newState, reduceMotion: reduceMotion) }
            .onChange(of: reduceMotion) { _, newValue in scene.render(state, reduceMotion: newValue) }
    }
}

struct WorkerMissionPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var playbackTask: Task<Void, Never>?

    private var reduceMotion: Bool { systemReduceMotion || model.forceReduceMotion }

    var body: some View {
        PanelContainer(
            title: "Mission 2 · Worker Concurrency",
            context: "Overlap waiting work without exceeding the two-unit worker budget.",
            onClose: close
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                DialogPanel(
                    speaker: "System Engineer",
                    message: "Run the saved one-worker workload, then give the same five requests to two workers. Waiting can overlap, but both workers share one modeled CPU."
                )
                section(
                    "Target",
                    text: "Complete all five requests with exactly two workers, spend no more than two resource units, and finish in 3,200 ms or less.",
                    icon: "scope"
                )
                workloadIdentity

                if model.workerMission.baselineRun == nil {
                    MeOSPrimaryButton(title: "Run One-Worker Baseline", icon: "play.fill") {
                        guard (try? model.startWorkerRun()) == true else { return }
                        beginPlayback()
                    }
                    .accessibilityIdentifier("mission2.runBaseline")
                } else {
                    workerManager
                }

                if let baseline = model.workerMission.baselineRun {
                    baselineResults(baseline)
                }

                if let run = model.workerMission.currentRun,
                   model.workerMission.presentation != nil {
                    currentPlayback(run)
                }

                if let comparison = model.workerMission.comparisonRun,
                   let baseline = model.workerMission.baselineRun {
                    comparisonResults(comparison, baseline: baseline)
                }

                if model.workerMission.stage == .completed {
                    StatusBadge(text: "Mission complete · Database installation unlocked", kind: .complete)
                        .accessibilityIdentifier("mission2.complete")
                    MeOSPrimaryButton(title: "Continue to Mission 3", icon: "arrow.right.circle.fill") {
                        model.closePanel()
                    }
                    .accessibilityIdentifier("mission2.continue")
                }

                Label(model.workerMission.feedback, systemImage: feedbackIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MeOSColor.text)
                    .accessibilityIdentifier("mission2.feedback")

                MeOSSecondaryButton(title: "Retry Exact Baseline", icon: "arrow.counterclockwise") {
                    playbackTask?.cancel()
                    try? model.resetWorkerMission()
                }
                .accessibilityHint("Restores the same five request identities, arrivals, phases, and seed")
                .accessibilityIdentifier("mission2.retry")
            }
        }
        .onDisappear {
            playbackTask?.cancel()
            model.pauseWorkerPresentation()
        }
    }

    private var workloadIdentity: some View {
        let workload = MissionCatalog.standard.definition(for: .workerConcurrency)?.workload ?? []
        return MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Label("Identical comparison workload", systemImage: "equal.circle.fill")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.cyan)
                Text(workload.map(\.id.rawValue).joined(separator: "  ·  "))
                    .font(.caption.monospaced())
                    .foregroundStyle(MeOSColor.text)
                Text("Each request: 600 ms waiting, then 400 ms CPU · seed 42001")
                    .font(.caption)
                    .foregroundStyle(MeOSColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mission2.workload")
    }

    private var workerManager: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                HStack {
                    Label("Worker Manager", systemImage: "person.3.fill")
                        .font(.headline)
                        .foregroundStyle(MeOSColor.cyan)
                    Spacer()
                    ResourceCounter(available: max(2 - model.workerMission.resourceCost, 0), total: 2)
                }
                Text("Each worker costs one unit. Counts 0–4 are observable; only two stays within the victory budget.")
                    .font(.subheadline)
                    .foregroundStyle(MeOSColor.secondaryText)
                HStack(spacing: MeOSSpace.sm) {
                    ForEach(0...4, id: \.self) { count in
                        Button("\(count)") { try? model.selectWorkerCount(count) }
                            .buttonStyle(MeOSCompactChoiceStyle(selected: model.workerMission.selectedWorkerCount == count))
                            .disabled(!model.workerMission.canConfigure)
                            .accessibilityLabel("Select \(count) workers")
                            .accessibilityValue(model.workerMission.selectedWorkerCount == count ? "Selected" : "Not selected")
                            .accessibilityIdentifier("mission2.worker.\(count)")
                    }
                }
                MeOSPrimaryButton(title: "Run Identical Workload", icon: "play.fill") {
                    guard (try? model.startWorkerRun()) == true else { return }
                    beginPlayback()
                }
                .disabled(!model.workerMission.canRun || model.workerMission.stage == .completed)
                .accessibilityIdentifier("mission2.runComparison")
            }
        }
    }

    private func baselineResults(_ baseline: VisualizationRun) -> some View {
        VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            Text("One-worker baseline timeline")
                .font(.headline)
                .foregroundStyle(MeOSColor.text)
            SchedulingTimelineView(
                segments: projectedState(for: baseline).timeline,
                makespan: max(baseline.result.metrics.completionTimeMilliseconds, 1)
            )
            .frame(height: 220)
            .accessibilityIdentifier("mission2.timeline.baseline")
        }
    }

    private func currentPlayback(_ run: VisualizationRun) -> some View {
        VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            HStack {
                StatusBadge(text: model.workerMission.presentation?.lifecycle.rawValue.capitalized ?? "Ready", kind: model.workerMission.stage == .completed ? .complete : .ready)
                Spacer()
                Text("\(model.workerMission.renderState?.timestampMilliseconds ?? 0) ms")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(MeOSColor.text)
            }
            HStack(spacing: MeOSSpace.sm) {
                MeOSSecondaryButton(title: "Play", icon: "play.fill", action: beginPlayback)
                    .disabled(model.workerMission.presentation?.lifecycle == .playing || model.workerMission.stage != .running)
                MeOSSecondaryButton(title: "Pause", icon: "pause.fill") {
                    playbackTask?.cancel()
                    model.pauseWorkerPresentation()
                }
                .disabled(model.workerMission.presentation?.lifecycle != .playing)
                MeOSSecondaryButton(title: "Show Final Event", icon: "forward.end.fill") {
                    playbackTask?.cancel()
                    _ = try? model.finishWorkerPresentation()
                }
                .disabled(model.workerMission.stage != .running)
                .accessibilityIdentifier("mission2.finishPresentation")
            }
            Mission1SpriteView(
                state: model.workerMission.renderState ?? SimulationEventProjector().baseline(workload: run.workload, configuration: run.configuration),
                reduceMotion: reduceMotion
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: MeOSRadius.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Worker assignment animation")
            .accessibilityValue(workerAccessibilityValue)
            .accessibilityIdentifier("mission2.workers")
        }
    }

    private func comparisonResults(_ comparison: VisualizationRun, baseline: VisualizationRun) -> some View {
        let current = comparison.result.metrics
        let previous = baseline.result.metrics
        return VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            Text("Before and after comparison")
                .font(.headline)
                .foregroundStyle(MeOSColor.text)
            Text("Workers: 1 → \(comparison.configuration.workerCount) · Makespan: \(previous.completionTimeMilliseconds) → \(current.completionTimeMilliseconds) ms · Average latency: \(Int(previous.averageLatencyMilliseconds)) → \(Int(current.averageLatencyMilliseconds)) ms · Queue waiting: \(previous.totalQueueWaitMilliseconds) → \(current.totalQueueWaitMilliseconds) ms · CPU use: \(Int(previous.cpuUtilization * 100))% → \(Int(current.cpuUtilization * 100))%")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(MeOSColor.text)
                .accessibilityIdentifier("mission2.comparisonValues")
            MetricComparisonChart(result: comparison.result, baseline: baseline.result)
                .frame(height: 230)
                .accessibilityIdentifier("mission2.comparisonChart")
            Text("\(comparison.configuration.workerCount)-worker comparison timeline")
                .font(.headline)
                .foregroundStyle(MeOSColor.text)
            SchedulingTimelineView(
                segments: projectedState(for: comparison).timeline,
                makespan: max(comparison.result.metrics.completionTimeMilliseconds, 1)
            )
            .frame(height: 220)
            .accessibilityIdentifier("mission2.timeline.comparison")
        }
    }

    private func projectedState(for run: VisualizationRun) -> SimulationRenderState {
        SimulationEventProjector().project(events: run.result.orderedEvents[...], workload: run.workload, configuration: run.configuration)
    }

    private var workerAccessibilityValue: String {
        let workers = model.workerMission.renderState?.orderedWorkers.map { worker in
            "\(worker.id.rawValue), \(worker.requestID?.rawValue ?? "idle"), \(worker.isUsingCPU ? "using CPU" : "not using CPU")"
        } ?? []
        return workers.joined(separator: "; ")
    }

    private var feedbackIcon: String {
        switch model.workerMission.stage {
        case .baselineReady: "timer"
        case .running: "person.2.wave.2.fill"
        case .configure: "slider.horizontal.3"
        case .completed: "checkmark.seal.fill"
        }
    }

    private func beginPlayback() {
        guard model.playWorkerPresentation() else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            while !Task.isCancelled,
                  model.workerMission.presentation?.lifecycle == .playing,
                  let presentation = model.workerMission.presentation,
                  presentation.eventIndex < presentation.events.count {
                let index = presentation.eventIndex
                let event = presentation.events[index]
                let previous = index == 0 ? 0 : presentation.events[index - 1].timestampMilliseconds
                let delay = reduceMotion ? 0 : min(max(event.timestampMilliseconds - previous, 0), 500)
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                else { await Task.yield() }
                guard !Task.isCancelled else { return }
                _ = model.presentNextWorkerEvent()
            }
            if !Task.isCancelled { _ = try? model.finishWorkerPresentation() }
        }
    }

    private func close() {
        playbackTask?.cancel()
        model.pauseWorkerPresentation()
        model.closePanel()
    }
}

private struct MeOSCompactChoiceStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.monospacedDigit())
            .foregroundStyle(MeOSColor.text)
            .frame(minWidth: 44, minHeight: 44)
            .background(selected ? MeOSColor.cyan.opacity(0.45) : MeOSColor.panelRaised)
            .overlay(RoundedRectangle(cornerRadius: MeOSRadius.button).stroke(selected ? MeOSColor.cyan : MeOSColor.secondaryText, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: MeOSRadius.button))
            .opacity(configuration.isPressed ? 0.75 : 1)
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
                    model.prepareVisualizationPreview()
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
                if let run = model.visualizationRun {
                    SimulationVisualizationView(run: run, forceReduceMotion: model.forceReduceMotion)
                } else {
                    HStack(spacing: MeOSSpace.sm) {
                        MetricTile(label: "Completed", value: "0", icon: "checkmark.circle")
                        MetricTile(label: "Queue", value: "Empty", icon: "rectangle.stack")
                        MetricTile(label: "Latency", value: "—", icon: "timer")
                    }
                    StatusBadge(text: "Stable empty state", kind: .ready)
                    section("What happened", text: "No workload has run yet, so the engine has produced no events or metrics.", icon: "info.circle")
                    section("Why it happened", text: "Empty input remains explicit; the visualizer never invents request activity.", icon: "lightbulb")
                }
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
                                .accessibilityIdentifier("glossary.inspect.\(component.rawValue)")
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

