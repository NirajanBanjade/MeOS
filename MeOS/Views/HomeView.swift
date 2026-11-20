import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeOSColor.ink.ignoresSafeArea()
            backgroundGrid
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 54) {
                        premise
                        actionCard.frame(width: 350)
                    }
                    VStack(alignment: .leading, spacing: MeOSSpace.lg) {
                        actionCard.frame(maxWidth: 520)
                        premise
                    }
                }
                .frame(maxWidth: 1250)
                .padding(.horizontal, 64)
                .padding(.vertical, 44)
            }
        }
        .animation((reduceMotion || model.forceReduceMotion) ? nil : .easeOut(duration: MeOSMotion.standard), value: model.hasValidSave)
    }

    private var premise: some View {
        VStack(alignment: .leading, spacing: MeOSSpace.lg) {
            StatusBadge(text: "System needs an engineer", kind: .attention)
            VStack(alignment: .leading, spacing: MeOSSpace.sm) {
                Text("MeOS")
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(MeOSColor.text)
                Text("STEP INSIDE THE SYSTEM")
                    .font(.headline.monospaced().weight(.bold))
                    .tracking(3)
                    .foregroundStyle(MeOSColor.cyan)
            }
            Text("Enter a malfunctioning computer laboratory. Run experiments, find bottlenecks, and rebuild the system by seeing what every decision changes.")
                .font(.title3)
                .foregroundStyle(MeOSColor.secondaryText)
                .lineSpacing(5)
                .frame(maxWidth: 610, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionCard: some View {
        MeOSCard {
            VStack(spacing: MeOSSpace.md) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(MeOSColor.cyan)
                    .accessibilityHidden(true)
                Text("Junior System Engineer")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MeOSColor.text)
                Text("Your first interaction is one tap away.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MeOSColor.secondaryText)
                MeOSPrimaryButton(
                    title: model.primaryActionTitle,
                    icon: model.hasValidSave ? "arrow.right.circle.fill" : "play.fill",
                    accessibilityHint: "Enters the MeOS laboratory",
                    action: model.enterLaboratory
                )
                .accessibilityIdentifier("home.primaryAction")
                ViewThatFits(in: .horizontal) {
                    preferenceActions
                    VStack(alignment: .leading, spacing: MeOSSpace.sm) { preferenceActions }
                }
            }
        }
    }

    private var preferenceActions: some View {
        HStack {
            Button {
                model.soundEnabled.toggle()
            } label: {
                Label(model.soundEnabled ? "Sound On" : "Sound Off", systemImage: model.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .accessibilityLabel(model.soundEnabled ? "Turn sound off" : "Turn sound on")
            .accessibilityHint("Sound is optional and never affects progress")
            .accessibilityIdentifier("home.soundToggle")
            Spacer()
            Button("Credits") { model.present(.credits) }.accessibilityIdentifier("home.credits")
            Button("Settings") { model.present(.settings) }.accessibilityIdentifier("home.settings")
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MeOSColor.cyan)
    }

    private var backgroundGrid: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: 0.0, through: size.width, by: 48) {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0.0, through: size.height, by: 48) {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(MeOSColor.cyan.opacity(0.045)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

