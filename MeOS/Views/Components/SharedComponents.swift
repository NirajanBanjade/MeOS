import SwiftUI

struct MeOSCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(MeOSSpace.md)
            .background(MeOSColor.panelRaised, in: RoundedRectangle(cornerRadius: MeOSRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MeOSRadius.card, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

struct MeOSPrimaryButton: View {
    let title: String
    let icon: String
    var accessibilityHint: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(MeOSColor.ink)
                .background(MeOSColor.cyan, in: RoundedRectangle(cornerRadius: MeOSRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}

struct MeOSSecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .foregroundStyle(MeOSColor.text)
                .background(MeOSColor.panelRaised, in: RoundedRectangle(cornerRadius: MeOSRadius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MeOSRadius.button, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        MeOSCard {
            VStack(alignment: .leading, spacing: MeOSSpace.xs) {
                Label(label, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MeOSColor.secondaryText)
                Text(value)
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(MeOSColor.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    enum Kind { case ready, attention, complete }
    let text: String
    let kind: Kind

    private var icon: String {
        switch kind { case .ready: "checkmark.circle.fill"; case .attention: "exclamationmark.triangle.fill"; case .complete: "checkmark.seal.fill" }
    }

    private var color: Color {
        switch kind { case .ready: MeOSColor.cyan; case .attention: MeOSColor.amber; case .complete: MeOSColor.mint }
    }

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.13), in: Capsule())
            .accessibilityLabel("Status: \(text)")
    }
}

struct ResourceCounter: View {
    let available: Int
    let total: Int

    var body: some View {
        Label("Resources \(available) of \(total)", systemImage: "shippingbox.fill")
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(MeOSColor.amber)
            .accessibilityLabel("\(available) of \(total) resources available")
    }
}

struct DialogPanel: View {
    let speaker: String
    let message: String

    var body: some View {
        MeOSCard {
            HStack(alignment: .top, spacing: MeOSSpace.md) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.largeTitle)
                    .foregroundStyle(MeOSColor.lavender)
                VStack(alignment: .leading, spacing: MeOSSpace.xs) {
                    Text(speaker).font(.headline).foregroundStyle(MeOSColor.text)
                    Text(message).font(.body).foregroundStyle(MeOSColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

