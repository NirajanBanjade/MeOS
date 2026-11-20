import SwiftUI

struct PanelContainer<Content: View>: View {
    let title: String
    let context: String
    let closeTitle: String
    let onClose: () -> Void
    let content: Content

    init(
        title: String,
        context: String,
        closeTitle: String = "Close",
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.context = context
        self.closeTitle = closeTitle
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: MeOSSpace.md) {
                VStack(alignment: .leading, spacing: MeOSSpace.xs) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MeOSColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(context)
                        .font(.subheadline)
                        .foregroundStyle(MeOSColor.secondaryText)
                }
                Spacer()
                Button(action: onClose) {
                    Label(closeTitle, systemImage: "xmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MeOSColor.text)
                        .padding(10)
                        .background(.white.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(closeTitle)
                .accessibilityHint("Returns to the laboratory at the same position")
            }
            .padding(MeOSSpace.lg)

            Divider().overlay(.white.opacity(0.12))

            ScrollView {
                content
                    .padding(MeOSSpace.lg)
            }
            .accessibilityIdentifier("panel.scroll")
        }
        .frame(maxWidth: 720, maxHeight: 650)
        .meOSPanel()
        .padding(MeOSSpace.lg)
    }
}

