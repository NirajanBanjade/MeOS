import SwiftUI

enum MeOSColor {
    static let ink = Color(red: 0.05, green: 0.08, blue: 0.14)
    static let panel = Color(red: 0.08, green: 0.13, blue: 0.22)
    static let panelRaised = Color(red: 0.11, green: 0.18, blue: 0.29)
    static let cyan = Color(red: 0.22, green: 0.88, blue: 0.93)
    static let mint = Color(red: 0.38, green: 0.91, blue: 0.65)
    static let amber = Color(red: 1.00, green: 0.72, blue: 0.25)
    static let coral = Color(red: 1.00, green: 0.42, blue: 0.42)
    static let lavender = Color(red: 0.68, green: 0.57, blue: 1.00)
    static let text = Color.white
    static let secondaryText = Color(red: 0.73, green: 0.79, blue: 0.88)
}

enum MeOSSpace {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 36
}

enum MeOSRadius {
    static let button: CGFloat = 14
    static let card: CGFloat = 20
    static let panel: CGFloat = 28
}

enum MeOSMotion {
    static let quick = 0.16
    static let standard = 0.28

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity)
    }
}

struct MeOSPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MeOSColor.panel.opacity(0.98), in: RoundedRectangle(cornerRadius: MeOSRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MeOSRadius.panel, style: .continuous)
                    .stroke(MeOSColor.cyan.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
    }
}

extension View {
    func meOSPanel() -> some View { modifier(MeOSPanelBackground()) }
}

