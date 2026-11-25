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
                    message: briefingMessage
                )
                section("Current objective", text: model.currentObjective, icon: "scope")
                section("Permitted actions", text: "Inspect the Server, review components, or return to the laboratory.", icon: "hand.tap")
                HStack {
                    ResourceCounter(available: 1, total: 1)
                    Spacer()
                    StatusBadge(text: "Ready to inspect", kind: .ready)
                }
                MeOSPrimaryButton(title: primaryActionTitle, icon: primaryActionIcon) {
                    model.replacePanel(with: missionPanel)
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

    private var briefingMessage: String {
        switch model.activeMission {
        case 1: "Our application server handles requests one at a time. Inspect it to see where new requests wait."
        case 2: "Compare the same workload with one and two workers while keeping CPU capacity fixed."
        case 3: "Install the primary database, connect it to the Server, then store and retrieve a record."
        case 4: "Measure the read-heavy baseline, then choose an infrastructure graph that meets the latency target within three budget."
        default: "System alert: response time is high. Inspect at least two Monitoring Terminal evidence panels, diagnose the bottleneck, and verify a measured repair."
        }
    }

    private var missionPanel: AppPanel {
        switch model.activeMission {
        case 1: .sequentialMission
        case 2: .workerMission
        case 3: .databaseMission
        case 4: .infrastructureMission
        default: .diagnosticMission
        }
    }

    private var primaryActionTitle: String {
        model.activeMission == 5 ? "Open Monitoring Terminal" : "Inspect Server"
    }

    private var primaryActionIcon: String {
        model.activeMission == 5 ? ComponentKind.monitoringTerminal.icon : ComponentKind.server.icon
    }
}

struct SequentialMissionPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                playbackTask?.cancel()
                playbackTask = nil
                model.pauseSequentialPresentation()
            }
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
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                playbackTask?.cancel()
                playbackTask = nil
                model.pauseWorkerPresentation()
            }
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

struct DatabaseMissionPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var key = "status"
    @State private var value = "online"
    @State private var validationMessage: String?

    private var reduceMotion: Bool { systemReduceMotion || model.forceReduceMotion }

    var body: some View {
        PanelContainer(
            title: "Mission 3 · Database Storage",
            context: "Install and connect a five-record key/value database.",
            onClose: model.closePanel
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                DialogPanel(
                    speaker: "System Engineer",
                    message: "Store status = online, read the same value back, then send a mixed read/write workload through the connected Server."
                )
                architectureState

                if !model.databaseMission.isInstalled {
                    MeOSPrimaryButton(title: "Install Primary Database", icon: "externaldrive.badge.plus") {
                        perform { try model.installDatabase() }
                    }
                    .accessibilityIdentifier("mission3.install")
                } else if !model.databaseMission.isConnected {
                    MeOSPrimaryButton(title: "Connect Server to Database", icon: "cable.connector") {
                        perform { try model.connectDatabase() }
                    }
                    .accessibilityHint("Creates the explicit Server-to-primary-database connection")
                    .accessibilityIdentifier("mission3.connect")
                }

                if model.databaseMission.isInstalled { terminal }

                if let operation = model.databaseMission.feedback {
                    operationFeedback(operation)
                }

                if let run = model.databaseMission.lastOperationRun {
                    databaseVisualization(run)
                }

                if model.databaseMission.didWriteScriptedRecord,
                   model.databaseMission.didReadScriptedRecord,
                   model.activeMission == MissionID.databaseStorage.rawValue {
                    MeOSPrimaryButton(title: "Run Connected Mixed Workload", icon: "play.fill") {
                        perform { _ = try model.runDatabaseWorkload() }
                    }
                    .disabled(!model.databaseMission.isConnected)
                    .accessibilityIdentifier("mission3.runWorkload")
                }

                if model.databaseMission.isComplete {
                    StatusBadge(text: "Mission complete · Infrastructure slots unlocked", kind: .complete)
                        .accessibilityIdentifier("mission3.complete")
                    MeOSPrimaryButton(title: "Continue to Mission 4", icon: "arrow.right.circle.fill") {
                        model.closePanel()
                    }
                    .accessibilityIdentifier("mission3.continue")
                }

                MeOSSecondaryButton(title: "Reset Database Checkpoint", icon: "arrow.counterclockwise") {
                    perform { try model.resetDatabaseMission() }
                }
                .accessibilityHint("Cancels pending presentation work and restores the empty, disconnected Mission 3 baseline")
                .accessibilityIdentifier("mission3.reset")
            }
        }
    }

    private var architectureState: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                HStack {
                    Label(
                        model.databaseMission.isInstalled ? "Primary database installed" : "Database slot empty",
                        systemImage: model.databaseMission.isInstalled ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.plus"
                    )
                    Spacer()
                    StatusBadge(
                        text: model.databaseMission.isConnected ? "Connected" : "Disconnected",
                        kind: model.databaseMission.isConnected ? .complete : .attention
                    )
                }
                Label(
                    model.databaseMission.isConnected ? "Server ─── Primary Database" : "Server     Primary Database · no cable",
                    systemImage: model.databaseMission.isConnected ? "cable.connector" : "cable.connector.slash"
                )
                .font(.headline.monospaced())
                .foregroundStyle(MeOSColor.text)
                Text("Capacity: \(model.databaseMission.capacityUsed) of \(model.databaseMission.capacity) unique keys · reads 300 ms · writes 500 ms")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(MeOSColor.secondaryText)
                    .accessibilityIdentifier("mission3.capacity")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mission3.architecture")
    }

    private var terminal: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Label("Database Terminal · key/value commands", systemImage: "terminal.fill")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.cyan)
                Text("This terminal sends modeled operations; it does not run SQL.")
                    .font(.caption)
                    .foregroundStyle(MeOSColor.secondaryText)
                TextField("Key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Record key")
                    .accessibilityIdentifier("mission3.key")
                TextField("Value", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Record value")
                    .accessibilityIdentifier("mission3.value")
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MeOSColor.amber)
                        .accessibilityIdentifier("mission3.validation")
                }
                HStack {
                    MeOSPrimaryButton(title: "Create / Update", icon: "square.and.pencil") {
                        perform { _ = try model.writeDatabaseRecord(key: key, value: value) }
                    }
                    .accessibilityIdentifier("mission3.write")
                    MeOSSecondaryButton(title: "Read", icon: "doc.text.magnifyingglass") {
                        perform { _ = try model.readDatabaseRecord(key: key) }
                    }
                    .accessibilityIdentifier("mission3.read")
                }
            }
        }
    }

    private func operationFeedback(_ operation: DatabaseOperationFeedback) -> some View {
        MeOSCard {
            HStack(alignment: .top, spacing: MeOSSpace.sm) {
                Image(systemName: operation.icon)
                    .foregroundStyle(operation.succeeded ? MeOSColor.mint : MeOSColor.amber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: MeOSSpace.xs) {
                    Text("\(operation.kind.rawValue) · \(operation.succeeded ? "Succeeded" : "Failed")")
                        .font(.headline)
                    Text(operation.message)
                    Text("Simulated latency: \(operation.latencyMilliseconds) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MeOSColor.secondaryText)
                }
                .foregroundStyle(MeOSColor.text)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mission3.feedback")
    }

    private func databaseVisualization(_ run: VisualizationRun) -> some View {
        let state = SimulationEventProjector().project(
            events: run.result.orderedEvents[...],
            workload: run.workload,
            configuration: run.configuration
        )
        return VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            Text("Engine event flow")
                .font(.headline)
                .foregroundStyle(MeOSColor.text)
            Mission1SpriteView(state: state, reduceMotion: reduceMotion)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: MeOSRadius.card))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Database request event animation")
                .accessibilityValue("\(run.result.metrics.databaseWrites) writes, \(run.result.metrics.databaseReads) reads, \(run.result.metrics.completed) completed, \(run.result.metrics.failed) failed")
                .accessibilityIdentifier("mission3.databaseEvents")
            Text("Engine operations: \(run.result.metrics.databaseWrites) writes · \(run.result.metrics.databaseReads) reads · \(run.result.orderedEvents.count) ordered events")
                .font(.caption.monospacedDigit())
                .foregroundStyle(MeOSColor.secondaryText)
                .accessibilityIdentifier("mission3.operationCounts")
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            validationMessage = nil
        } catch DatabaseMissionError.databaseNotInstalled {
            validationMessage = "Install the primary database before using the terminal."
        } catch DatabaseMissionError.emptyKey {
            validationMessage = "Enter a non-empty key. Spaces alone are not valid."
        } catch DatabaseMissionError.emptyValue {
            validationMessage = "Enter a non-empty value. Spaces alone are not valid."
        } catch {
            validationMessage = "The operation could not be completed. Your database checkpoint is unchanged."
        }
    }
}

struct InfrastructureMissionPanel: View {
    @ObservedObject var model: AppModel
    @State private var validationMessage: String?

    var body: some View {
        PanelContainer(
            title: "Mission 4 · Infrastructure Scaling",
            context: "Ten catalog reads · target ≤ 1,000 ms average · budget 3",
            onClose: model.closePanel
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                DialogPanel(
                    speaker: "System Engineer",
                    message: "All ten reads arrive at time zero. Measure the serialized primary, then buy a graph change and compare the real engine metrics."
                )

                budgetCard

                if model.infrastructureMission.baselineRun == nil {
                    MeOSPrimaryButton(title: "Run Primary-only Baseline", icon: "play.fill") {
                        perform { _ = try model.runInfrastructureWorkload() }
                    }
                    .accessibilityIdentifier("mission4.runBaseline")
                } else {
                    upgradeChoices
                    if model.infrastructureMission.comparisonRun == nil,
                       !model.infrastructureMission.selectedUpgrades.isEmpty {
                        MeOSPrimaryButton(title: "Run Upgraded Graph", icon: "play.fill") {
                            perform { _ = try model.runInfrastructureWorkload() }
                        }
                        .accessibilityIdentifier("mission4.runUpgrade")
                    }
                }

                StatusBadge(
                    text: model.infrastructureMission.feedback,
                    kind: model.infrastructureMission.isVictorious ? .complete : .ready
                )
                .accessibilityIdentifier("mission4.feedback")

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MeOSColor.amber)
                        .accessibilityIdentifier("mission4.validation")
                }

                if let baseline = model.infrastructureMission.baselineRun {
                    metricSummary(baseline: baseline, comparison: model.infrastructureMission.comparisonRun)
                }

                if let run = model.infrastructureMission.comparisonRun {
                    SimulationVisualizationView(run: run, forceReduceMotion: model.forceReduceMotion)
                        .accessibilityIdentifier("mission4.visualization")
                }

                if model.infrastructureMission.isVictorious {
                    StatusBadge(text: "Mission complete · Monitoring Terminal alert unlocked", kind: .complete)
                        .accessibilityIdentifier("mission4.complete")
                    MeOSPrimaryButton(title: "Continue to Mission 5", icon: "arrow.right.circle.fill") {
                        model.closePanel()
                    }
                    .accessibilityIdentifier("mission4.continue")
                }

                if !model.infrastructureMission.isVictorious {
                    MeOSSecondaryButton(title: "Reset Mission 4", icon: "arrow.counterclockwise") {
                        perform { try model.resetInfrastructureMission() }
                    }
                    .accessibilityHint("Restores the same ten request IDs, catalog value, seed, empty upgrade graph, and budget")
                    .accessibilityIdentifier("mission4.reset")
                }
            }
        }
    }

    private var budgetCard: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                HStack {
                    ResourceCounter(
                        available: model.infrastructureMission.availableBudget,
                        total: InfrastructureMissionRun.budget
                    )
                    Spacer()
                    Text("Cost \(model.infrastructureMission.resourceCost) / \(InfrastructureMissionRun.budget)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(MeOSColor.text)
                }
                Text("Primary DB: 300 ms serialized reads · Replica lag: 1,000 ms · Cache hit: 50 ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MeOSColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mission4.budget")
    }

    private var upgradeChoices: some View {
        VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            Text("Choose graph additions")
                .font(.headline)
                .foregroundStyle(MeOSColor.text)
            ForEach(InfrastructureUpgrade.allCases) { upgrade in
                let selected = model.infrastructureMission.selectedUpgrades.contains(upgrade)
                MeOSCard {
                    VStack(alignment: .leading, spacing: MeOSSpace.xs) {
                        HStack {
                            Label(upgrade.title, systemImage: icon(for: upgrade))
                                .font(.headline)
                            Spacer()
                            Text("Cost \(upgrade.cost)").font(.subheadline.monospacedDigit())
                        }
                        .foregroundStyle(MeOSColor.text)
                        Text(upgrade.explanation)
                            .font(.subheadline)
                            .foregroundStyle(MeOSColor.secondaryText)
                        if let reason = model.infrastructureMission.unavailableReason(for: upgrade), !selected {
                            Text(reason)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MeOSColor.amber)
                                .accessibilityIdentifier("mission4.reason.\(upgrade.rawValue)")
                        }
                        MeOSSecondaryButton(
                            title: selected ? "Added" : "Add \(upgrade.title)",
                            icon: selected ? "checkmark.circle.fill" : "plus.circle.fill"
                        ) {
                            perform { try model.selectInfrastructureUpgrade(upgrade) }
                        }
                        .disabled(selected || model.infrastructureMission.unavailableReason(for: upgrade) != nil)
                        .accessibilityIdentifier("mission4.upgrade.\(upgrade.rawValue)")
                    }
                }
            }
        }
    }

    private func metricSummary(baseline: VisualizationRun, comparison: VisualizationRun?) -> some View {
        let before = baseline.result.metrics
        let after = comparison?.result.metrics
        return MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Text("Measured before / after")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.cyan)
                metricRow("Average latency", before: "\(Int(before.averageLatencyMilliseconds)) ms", after: after.map { "\(Int($0.averageLatencyMilliseconds)) ms" })
                metricRow("Completion time", before: "\(before.completionTimeMilliseconds) ms", after: after.map { "\($0.completionTimeMilliseconds) ms" })
                metricRow("Database operations", before: "\(before.databaseReads + before.databaseWrites)", after: after.map { "\($0.databaseReads + $0.databaseWrites)" })
                metricRow("Cache hits / misses", before: "\(before.cacheHits) / \(before.cacheMisses)", after: after.map { "\($0.cacheHits) / \($0.cacheMisses)" })
                metricRow("Replica reads", before: "\(before.replicaReads)", after: after.map { "\($0.replicaReads)" })
                metricRow("Resource cost", before: "0", after: comparison == nil ? nil : "\(model.infrastructureMission.resourceCost)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mission4.metrics")
    }

    private func metricRow(_ label: String, before: String, after: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(before) → \(after ?? "—")")
                .monospacedDigit()
        }
        .font(.subheadline)
        .foregroundStyle(MeOSColor.text)
    }

    private func icon(for upgrade: InfrastructureUpgrade) -> String {
        switch upgrade {
        case .readReplica: ComponentKind.readReplica.icon
        case .cache: ComponentKind.cache.icon
        case .secondServer: ComponentKind.server.icon
        case .routing: ComponentKind.router.icon
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            validationMessage = nil
        } catch InfrastructureMissionError.baselineRequired {
            validationMessage = "Run the primary-only baseline first."
        } catch InfrastructureMissionError.upgradeRequired {
            validationMessage = "Choose an affordable upgrade before running the comparison."
        } catch InfrastructureMissionError.insufficientBudget(let required, let available) {
            validationMessage = "That addition costs \(required), but only \(available) budget remains."
        } catch InfrastructureMissionError.routingRequiresSecondServer {
            validationMessage = "A routing connection needs a second app server destination."
        } catch {
            validationMessage = "The graph could not be changed. The last measured checkpoint is unchanged."
        }
    }
}

struct DiagnosticMissionPanel: View {
    @ObservedObject var model: AppModel
    @State private var validationMessage: String?

    var body: some View {
        PanelContainer(
            title: "Mission 5 · System Diagnostics",
            context: "Investigate evidence, repair the actual bottleneck, and verify the result.",
            onClose: model.closePanel
        ) {
            VStack(alignment: .leading, spacing: MeOSSpace.md) {
                DialogPanel(
                    speaker: "System Alert",
                    message: "Response time is above target. Do not guess: capture the baseline and inspect at least two distinct evidence panels before changing the system."
                )

                if model.diagnosticMission.baselineRun == nil {
                    MeOSPrimaryButton(title: "Capture Diagnostic Baseline", icon: "waveform.path.ecg") {
                        perform { _ = try model.measureDiagnosticBaseline() }
                    }
                    .accessibilityIdentifier("mission5.captureBaseline")
                }

                if let run = model.diagnosticMission.baselineRun {
                    evidenceGrid(result: run.result, architecture: run.configuration.nodes)
                }

                if model.diagnosticMission.canChooseInterventions {
                    interventionChoices
                } else if model.diagnosticMission.baselineRun != nil {
                    Label(
                        "Inspect \(max(0, 2 - model.diagnosticMission.inspectedEvidence.count)) more distinct evidence panel\(model.diagnosticMission.inspectedEvidence.count == 1 ? "" : "s") to unlock interventions.",
                        systemImage: "lock.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MeOSColor.amber)
                    .accessibilityIdentifier("mission5.evidenceGate")
                }

                if !model.diagnosticMission.selectedInterventions.isEmpty {
                    MeOSPrimaryButton(title: "Run Verification Workload", icon: "play.fill") {
                        perform { _ = try model.verifyDiagnosticRepair() }
                    }
                    .accessibilityHint("Measures the complete active configuration against the unchanged ten-read workload")
                    .accessibilityIdentifier("mission5.verify")
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MeOSColor.amber)
                        .accessibilityIdentifier("mission5.validation")
                }

                Label(model.diagnosticMission.feedback, systemImage: model.diagnosticMission.isVictorious ? "checkmark.seal.fill" : "stethoscope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MeOSColor.text)
                    .accessibilityIdentifier("mission5.feedback")

                if let baseline = model.diagnosticMission.baselineRun {
                    measuredComparison(baseline: baseline, verification: model.diagnosticMission.verificationRun)
                }

                if model.diagnosticMission.stage == .results {
                    MeOSSecondaryButton(title: "Retry from Diagnostic Checkpoint", icon: "arrow.counterclockwise") {
                        perform { try model.resetDiagnosticInterventions() }
                    }
                    .accessibilityHint("Keeps inspected evidence, clears interventions, and applies no penalty")
                    .accessibilityIdentifier("mission5.retry")
                }

                if model.diagnosticMission.isVictorious {
                    finalSummary
                }

                if let verification = model.diagnosticMission.verificationRun {
                    SimulationVisualizationView(run: verification, forceReduceMotion: model.forceReduceMotion)
                }
            }
        }
    }

    private func evidenceGrid(result: SimulationResult, architecture: [SystemNode]) -> some View {
        let snapshot = DiagnosticSnapshot(result: result, architecture: architecture)
        return VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            HStack {
                Text("Measured evidence")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.cyan)
                Spacer()
                StatusBadge(text: "\(model.diagnosticMission.inspectedEvidence.count) of 2 required", kind: model.diagnosticMission.canChooseInterventions ? .complete : .attention)
            }
            ForEach(DiagnosticEvidence.allCases) { evidence in
                let inspected = model.diagnosticMission.inspectedEvidence.contains(evidence)
                MeOSSecondaryButton(title: "\(inspected ? "Reviewed" : "Inspect") · \(evidence.title)", icon: inspected ? "checkmark.circle.fill" : evidenceIcon(evidence)) {
                    perform { try model.inspectDiagnosticEvidence(evidence) }
                }
                .accessibilityIdentifier("mission5.evidence.\(evidence.rawValue)")
                if inspected {
                    Text(evidenceText(evidence, snapshot: snapshot))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(MeOSColor.secondaryText)
                        .padding(.leading, MeOSSpace.sm)
                        .accessibilityIdentifier("mission5.evidenceDetail.\(evidence.rawValue)")
                }
            }
        }
    }

    private var interventionChoices: some View {
        VStack(alignment: .leading, spacing: MeOSSpace.sm) {
            HStack {
                Text("Active configuration")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.cyan)
                Spacer()
                Text("Cost \(model.diagnosticMission.resourceCost)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(MeOSColor.text)
            }
            Text("Select any combination. MeOS measures the whole graph, not the most recent button.")
                .font(.subheadline)
                .foregroundStyle(MeOSColor.secondaryText)
            ForEach(DiagnosticIntervention.allCases) { intervention in
                let selected = model.diagnosticMission.selectedInterventions.contains(intervention)
                MeOSSecondaryButton(
                    title: "\(selected ? "Remove" : "Add") · \(intervention.title) · Cost \(intervention.cost)",
                    icon: selected ? "minus.circle.fill" : interventionIcon(intervention)
                ) {
                    perform { try model.toggleDiagnosticIntervention(intervention) }
                }
                .accessibilityValue(selected ? "Active" : "Inactive")
                .accessibilityIdentifier("mission5.intervention.\(intervention.rawValue)")
            }
        }
    }

    private func measuredComparison(baseline: VisualizationRun, verification: VisualizationRun?) -> some View {
        let before = baseline.result.metrics
        let after = verification?.result.metrics
        return MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Text("Same-result monitoring summary")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.cyan)
                diagnosticRow("CPU utilization", before: percent(before.cpuUtilization), after: after.map { percent($0.cpuUtilization) })
                diagnosticRow("Worker queue / wait", before: "\(before.queued) / \(before.totalQueueWaitMilliseconds) ms", after: after.map { "\($0.queued) / \($0.totalQueueWaitMilliseconds) ms" })
                diagnosticRow("Database load", before: "\(before.databaseReads + before.databaseWrites) ops", after: after.map { "\($0.databaseReads + $0.databaseWrites) ops" })
                diagnosticRow("Database / response latency", before: "\(Int(before.averageLatencyMilliseconds)) ms", after: after.map { "\(Int($0.averageLatencyMilliseconds)) ms" })
                diagnosticRow("Failures", before: "\(before.failed + before.rejected)", after: after.map { "\($0.failed + $0.rejected)" })
                diagnosticRow("Architecture nodes", before: "\(baseline.configuration.nodes.count)", after: verification.map { "\($0.configuration.nodes.count)" })
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mission5.metrics")
    }

    private var finalSummary: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Label("MeOS System Architect", systemImage: "medal.star.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MeOSColor.cyan)
                Text("Evidence chain: low CPU utilization + no limiting worker queue + high serialized primary-database latency → relieve database reads → verify average response at or below 1,000 ms.")
                    .foregroundStyle(MeOSColor.text)
                Text("Concepts learned: request queues, concurrency, persistent storage, scalable read paths, caching, replicas, and evidence-based bottleneck diagnosis.")
                    .foregroundStyle(MeOSColor.secondaryText)
                Text("All five missions are complete. Replay is unlocked from the Mission Briefing without duplicating achievements or this title.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MeOSColor.text)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mission5.complete")
    }

    private func evidenceText(_ evidence: DiagnosticEvidence, snapshot: DiagnosticSnapshot) -> String {
        switch evidence {
        case .cpu:
            "CPU utilization: \(percent(snapshot.cpuUtilization)). Low CPU pressure means processing capacity is not saturated."
        case .workerQueue:
            "Queued now: \(snapshot.queuedRequests); queue wait: \(snapshot.queueWaitMilliseconds) ms. Worker pressure is not the limiting factor."
        case .database:
            "Primary database: \(snapshot.databaseOperations) serialized operations; measured latency: \(Int(snapshot.databaseLatencyMilliseconds)) ms."
        case .responseAndArchitecture:
            "Average response: \(Int(snapshot.averageResponseMilliseconds)) ms; failures: \(snapshot.failures); architecture: \(snapshot.architecture.map(\.id.rawValue).joined(separator: ", "))."
        }
    }

    private func evidenceIcon(_ evidence: DiagnosticEvidence) -> String {
        switch evidence {
        case .cpu: "cpu"
        case .workerQueue: "person.2.fill"
        case .database: "cylinder.split.1x2"
        case .responseAndArchitecture: "point.3.connected.trianglepath.dotted"
        }
    }

    private func interventionIcon(_ intervention: DiagnosticIntervention) -> String {
        switch intervention {
        case .increasedWorkers: ComponentKind.worker.icon
        case .increasedServerCapacity: ComponentKind.server.icon
        case .readReplica: ComponentKind.readReplica.icon
        case .cache: ComponentKind.cache.icon
        }
    }

    private func diagnosticRow(_ label: String, before: String, after: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(before) → \(after ?? "—")").monospacedDigit()
        }
        .font(.subheadline)
        .foregroundStyle(MeOSColor.text)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            validationMessage = nil
        } catch DiagnosticMissionError.baselineRequired {
            validationMessage = "Capture the baseline first."
        } catch DiagnosticMissionError.evidenceRequired {
            validationMessage = "Inspect at least two distinct evidence panels first."
        } catch DiagnosticMissionError.interventionRequired {
            validationMessage = "Choose at least one intervention to verify."
        } catch {
            validationMessage = "The diagnostic action could not be completed. The stable checkpoint is unchanged."
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
                section("Visual resources", text: "The MeOS app icon is original project artwork. Interface symbols use Apple SF Symbols; the laboratory is drawn in code with Apple-native fonts.", icon: "paintpalette")
                section("Technology", text: "Built with Swift, SwiftUI, SpriteKit, Foundation, XCTest, and XCUITest. No third-party runtime packages or remote resources.", icon: "hammer")
                section("Packaged notice", text: "A matching Credits.txt notice is included in the application bundle for release inspection.", icon: "doc.text.fill")
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

