import SpriteKit
import SwiftUI

@MainActor
final class SimulationPlaybackModel: ObservableObject {
    @Published private(set) var session: SimulationPresentationSession
    private var playbackTask: Task<Void, Never>?

    init(run: VisualizationRun) {
        session = SimulationPresentationSession(
            events: run.result.orderedEvents,
            workload: run.workload,
            configuration: run.configuration
        )
    }

    deinit { playbackTask?.cancel() }

    func play(reduceMotion: Bool) {
        guard session.play() else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.session.lifecycle == .playing {
                let currentIndex = self.session.eventIndex
                guard currentIndex < self.session.events.count else { break }
                let current = self.session.events[currentIndex]
                let previousTime = currentIndex == 0 ? 0 : self.session.events[currentIndex - 1].timestampMilliseconds
                let simulatedGap = max(current.timestampMilliseconds - previousTime, 0)
                let scaled = reduceMotion ? 0 : min(Int(Double(simulatedGap) / self.session.speed.rawValue), 650)
                if scaled > 0 {
                    try? await Task.sleep(for: .milliseconds(scaled))
                } else {
                    await Task.yield()
                }
                guard !Task.isCancelled else { break }
                _ = self.session.presentNext()
            }
        }
    }

    func pause() {
        playbackTask?.cancel()
        playbackTask = nil
        session.pause()
    }

    func reset() {
        playbackTask?.cancel()
        playbackTask = nil
        session.reset()
    }

    func setSpeed(_ speed: PresentationSpeed) { session.setSpeed(speed) }

    func handleBackgrounding() { pause() }
}

struct SimulationVisualizationView: View {
    let run: VisualizationRun
    let forceReduceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback: SimulationPlaybackModel

    init(run: VisualizationRun, forceReduceMotion: Bool = false) {
        self.run = run
        self.forceReduceMotion = forceReduceMotion
        _playback = StateObject(wrappedValue: SimulationPlaybackModel(run: run))
    }

    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: MeOSSpace.md) {
            playbackHeader
            SimulationSpriteView(state: playback.session.renderState, reduceMotion: reduceMotion)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: MeOSRadius.card))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Event-driven system animation")
                .accessibilityValue(accessibleStateSummary)

            requestLegend
            liveMetrics

            Group {
                Text("Scheduling timeline").font(.headline).foregroundStyle(MeOSColor.text)
                SchedulingTimelineView(
                    segments: playback.session.renderState.timeline,
                    makespan: max(run.result.metrics.completionTimeMilliseconds, 1)
                )
                .frame(height: max(150, CGFloat(Set(playback.session.renderState.timeline.map(\.requestID)).count) * 34 + 42))

                Text("System architecture").font(.headline).foregroundStyle(MeOSColor.text)
                ArchitectureDiagramView(state: playback.session.renderState)
                    .frame(height: 220)

                Text(run.baselineResult == nil ? "Measured metrics" : "Before and after").font(.headline).foregroundStyle(MeOSColor.text)
                MetricComparisonChart(result: run.result, baseline: run.baselineResult)
                    .frame(height: 230)
            }

            resultExplanation
            accessibleSequence
        }
        .onDisappear { playback.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.handleBackgrounding() }
        }
    }

    private var playbackHeader: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                HStack {
                    StatusBadge(text: playback.session.lifecycle.rawValue.capitalized, kind: playback.session.lifecycle == .completed ? .complete : .ready)
                    Spacer()
                    Text("\(playback.session.renderState.timestampMilliseconds) ms")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(MeOSColor.text)
                        .accessibilityLabel("Simulation time \(playback.session.renderState.timestampMilliseconds) milliseconds")
                }
                HStack(spacing: MeOSSpace.sm) {
                    MeOSSecondaryButton(
                        title: playback.session.lifecycle == .paused ? "Resume" : "Play",
                        icon: "play.fill"
                    ) { playback.play(reduceMotion: reduceMotion) }
                    .disabled(playback.session.lifecycle == .playing || playback.session.lifecycle == .completed)
                    .accessibilityIdentifier("visualization.play")
                    MeOSSecondaryButton(title: "Pause", icon: "pause.fill") { playback.pause() }
                        .disabled(playback.session.lifecycle != .playing)
                        .accessibilityIdentifier("visualization.pause")
                    MeOSSecondaryButton(title: "Reset", icon: "arrow.counterclockwise") { playback.reset() }
                        .accessibilityIdentifier("visualization.reset")
                }
                Picker("Presentation speed", selection: Binding(
                    get: { playback.session.speed },
                    set: playback.setSpeed
                )) {
                    ForEach(PresentationSpeed.allCases, id: \.rawValue) { speed in Text(speed.label).tag(speed) }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Changes animation duration only. Simulation timestamps and results do not change.")
                .accessibilityIdentifier("visualization.speed")
                if reduceMotion {
                    Label("Reduced Motion: travel is replaced by highlights; event order and outcomes are unchanged.", systemImage: "accessibility")
                        .font(.caption)
                        .foregroundStyle(MeOSColor.secondaryText)
                }
            }
        }
    }

    private var requestLegend: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Text("State legend").font(.headline).foregroundStyle(MeOSColor.text)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], alignment: .leading, spacing: MeOSSpace.sm) {
                    ForEach([VisualRequestStatus.queued, .running, .waiting, .completed, .failed], id: \.rawValue) { status in
                        Label(status.label, systemImage: status.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MeOSColor.text)
                    }
                    Label("Stale", systemImage: "clock.badge.exclamationmark").font(.caption.weight(.semibold))
                    Label("Hit", systemImage: "bolt.fill").font(.caption.weight(.semibold))
                    Label("Miss", systemImage: "arrow.down.to.line").font(.caption.weight(.semibold))
                }
                .foregroundStyle(MeOSColor.text)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var liveMetrics: some View {
        let metrics = SimulationMetricFormatter.metrics(from: run.result)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: MeOSSpace.sm) {
            ForEach(metrics) { metric in
                MetricTile(label: metric.label, value: metric.value, icon: metric.icon)
            }
        }
    }

    private var resultExplanation: some View {
        VStack(alignment: .leading, spacing: MeOSSpace.md) {
            StatusBadge(
                text: run.result.metrics.failed == 0 && run.result.metrics.rejected == 0 ? "Run completed" : "Run completed with issues",
                kind: run.result.metrics.failed == 0 && run.result.metrics.rejected == 0 ? .complete : .attention
            )
            explanationSection(
                title: "What happened",
                icon: "waveform.path.ecg",
                text: "The engine recorded \(run.result.orderedEvents.count) ordered events. \(run.result.metrics.completed) completed, \(run.result.metrics.failed) failed, and \(run.result.metrics.rejected) were rejected."
            )
            explanationSection(
                title: "Why it happened",
                icon: "lightbulb.fill",
                text: run.result.explanationIDs.isEmpty
                    ? "The event log contains no exceptional condition. Every displayed value is formatted directly from the engine result."
                    : run.result.explanationIDs.map(SimulationExplanationCatalog.text).joined(separator: " ")
            )
            explanationSection(
                title: "Next actions",
                icon: "arrow.triangle.2.circlepath",
                text: "Reset replays the same immutable result. Retry and Continue remain mission-owned actions and cannot be triggered by animation completion."
            )
        }
    }

    private var accessibleSequence: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Label("Accessible event sequence", systemImage: "list.number")
                    .font(.headline)
                    .foregroundStyle(MeOSColor.cyan)
                if playback.session.renderState.announcements.isEmpty {
                    Text("No events presented yet.")
                        .foregroundStyle(MeOSColor.secondaryText)
                } else {
                    ForEach(playback.session.renderState.announcements.suffix(12)) { announcement in
                        Text(announcement.text)
                            .font(.caption)
                            .foregroundStyle(MeOSColor.text)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var accessibleStateSummary: String {
        let requests = playback.session.renderState.orderedRequests
            .map { "\($0.id.rawValue) \($0.status.label)" }
            .joined(separator: ", ")
        return requests.isEmpty ? "Empty simulation state" : requests
    }

    private func explanationSection(title: String, icon: String, text: String) -> some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.xs) {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(MeOSColor.cyan)
                Text(text).foregroundStyle(MeOSColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SimulationSpriteView: View {
    let state: SimulationRenderState
    let reduceMotion: Bool
    @State private var scene = SimulationScene()

    var body: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .onAppear { scene.render(state, reduceMotion: reduceMotion) }
            .onChange(of: state) { _, newState in scene.render(newState, reduceMotion: reduceMotion) }
            .onChange(of: reduceMotion) { _, value in scene.render(state, reduceMotion: value) }
    }
}

struct SchedulingTimelineView: View {
    let segments: [TimelineSegment]
    let makespan: SimulationTime

    var body: some View {
        let requestIDs = Array(Set(segments.map(\.requestID))).sorted()
        Canvas { context, size in
            let left: CGFloat = 74
            let width = max(size.width - left - 12, 1)
            let rowHeight = max((size.height - 28) / CGFloat(max(requestIDs.count, 1)), 24)
            for tick in 0...5 {
                let x = left + width * CGFloat(tick) / 5
                var line = Path()
                line.move(to: CGPoint(x: x, y: 18))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.1)), lineWidth: 1)
                context.draw(Text("\(Int(Double(makespan) * Double(tick) / 5))").font(.caption2).foregroundStyle(MeOSColor.secondaryText), at: CGPoint(x: x, y: 7), anchor: .center)
            }
            for (row, requestID) in requestIDs.enumerated() {
                let y = 28 + CGFloat(row) * rowHeight
                context.draw(Text(requestID.rawValue).font(.caption.weight(.bold)).foregroundStyle(MeOSColor.text), at: CGPoint(x: 6, y: y + rowHeight / 2), anchor: .leading)
                for segment in segments where segment.requestID == requestID {
                    let x = left + width * CGFloat(segment.startMilliseconds) / CGFloat(makespan)
                    let segmentWidth = max(width * CGFloat(segment.durationMilliseconds) / CGFloat(makespan), 2)
                    let rect = CGRect(x: x, y: y + 4, width: segmentWidth, height: rowHeight - 8)
                    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(segment.kind == .cpu ? MeOSColor.lavender : MeOSColor.amber))
                }
            }
        }
        .background(MeOSColor.panelRaised, in: RoundedRectangle(cornerRadius: MeOSRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scheduling timeline")
        .accessibilityValue(segments.map { "\($0.requestID.rawValue) \($0.kind.rawValue) from \($0.startMilliseconds) for \($0.durationMilliseconds) milliseconds" }.joined(separator: ", "))
    }
}

struct ArchitectureDiagramView: View {
    let state: SimulationRenderState

    var body: some View {
        Canvas { context, size in
            let nodes = state.orderedNodes
            guard !nodes.isEmpty else {
                context.draw(Text("No configured architecture nodes").foregroundStyle(MeOSColor.secondaryText), at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let radius = min(size.width, size.height) * 0.34
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let positions = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { index, node in
                let angle = Double(index) / Double(nodes.count) * .pi * 2 - .pi / 2
                return (node.id, CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
            })
            for connection in state.connections {
                guard let from = positions[connection.from], let to = positions[connection.to] else { continue }
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(MeOSColor.cyan.opacity(0.65)), lineWidth: 3)
            }
            for node in nodes {
                guard let point = positions[node.id] else { continue }
                let rect = CGRect(x: point.x - 52, y: point.y - 25, width: 104, height: 50)
                context.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(MeOSColor.panel))
                context.stroke(Path(roundedRect: rect, cornerRadius: 12), with: .color(node.activity == .failed ? MeOSColor.coral : MeOSColor.cyan), lineWidth: 2)
                context.draw(Text(node.id.rawValue).font(.caption.weight(.bold)).foregroundStyle(MeOSColor.text), at: point)
            }
        }
        .background(MeOSColor.panelRaised, in: RoundedRectangle(cornerRadius: MeOSRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System architecture")
        .accessibilityValue(architectureAccessibilityValue)
    }

    private var architectureAccessibilityValue: String {
        let nodes = state.orderedNodes.map { "\($0.id.rawValue), \($0.activity.label)" }.joined(separator: "; ")
        let connections = state.connections.map { "\($0.from.rawValue) to \($0.to.rawValue)" }.joined(separator: "; ")
        return "Nodes: \(nodes). Connections: \(connections)."
    }
}

struct MetricComparisonChart: View {
    let result: SimulationResult
    let baseline: SimulationResult?

    var body: some View {
        let current = selectedMetrics(result)
        let previous = baseline.map(selectedMetrics) ?? []
        let maximum = max((current + previous).map(\.numericValue).max() ?? 1, 1)
        Canvas { context, size in
            let groupWidth = size.width / CGFloat(max(current.count, 1))
            let chartHeight = size.height - 52
            for (index, metric) in current.enumerated() {
                let centerX = groupWidth * (CGFloat(index) + 0.5)
                if let old = previous.first(where: { $0.id == metric.id }) {
                    let oldHeight = chartHeight * CGFloat(old.numericValue / maximum)
                    let oldRect = CGRect(x: centerX - 22, y: chartHeight - oldHeight + 8, width: 18, height: oldHeight)
                    context.fill(Path(roundedRect: oldRect, cornerRadius: 4), with: .color(MeOSColor.secondaryText.opacity(0.55)))
                }
                let height = chartHeight * CGFloat(metric.numericValue / maximum)
                let rect = CGRect(x: centerX + (baseline == nil ? -10 : 4), y: chartHeight - height + 8, width: 20, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(MeOSColor.cyan))
                context.draw(Text(metric.label).font(.caption2).foregroundStyle(MeOSColor.text), at: CGPoint(x: centerX, y: size.height - 25))
                context.draw(Text(metric.value).font(.caption2.weight(.bold)).foregroundStyle(MeOSColor.text), at: CGPoint(x: centerX, y: size.height - 9))
            }
        }
        .background(MeOSColor.panelRaised, in: RoundedRectangle(cornerRadius: MeOSRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(baseline == nil ? "Measured metric chart" : "Before and after metric chart")
        .accessibilityValue(current.map { "\($0.label), \($0.value)" }.joined(separator: ", "))
    }

    private func selectedMetrics(_ result: SimulationResult) -> [DisplayMetric] {
        let metrics = SimulationMetricFormatter.metrics(from: result)
        return metrics.filter { ["queue-wait", "makespan", "latency", "database", "cpu"].contains($0.id) }
    }
}
