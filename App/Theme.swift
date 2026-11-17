import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let accentDeep = Color(red: 0.15, green: 0.39, blue: 0.92)
    static let safe = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let warn = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let danger = Color(red: 0.97, green: 0.32, blue: 0.36)

    static let bgTop = Theme.adaptive(light: 0xEAF4FF, dark: 0x0F2347)
    static let bgBottom = Theme.adaptive(light: 0xD6E6FA, dark: 0x060D1F)
    static let card = Theme.adaptive(light: 0xFFFFFF, dark: 0x16284A)

    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.22, green: 0.74, blue: 0.97), Color(red: 0.15, green: 0.39, blue: 0.92)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        let provider: (UITraitCollection) -> UIColor = { (trait: UITraitCollection) -> UIColor in
            if trait.userInterfaceStyle == .dark {
                return Theme.uiColor(dark)
            }
            return Theme.uiColor(light)
        }
        return Color(UIColor(dynamicProvider: provider))
    }

    static func uiColor(_ hex: UInt32) -> UIColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var colors: [Color] = [Theme.accent, Theme.accentDeep]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                Theme.accent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct InfoCard: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.primaryGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }
}

struct StatusChip: View {
    let risk: Risk
    var text: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: risk.symbol)
                .font(.caption2.weight(.bold))
            Text(text ?? risk.label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(risk.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(risk.color.opacity(0.15), in: Capsule())
    }
}
