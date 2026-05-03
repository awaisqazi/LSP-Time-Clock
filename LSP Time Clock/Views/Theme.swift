import SwiftUI

enum Theme {
    // Brand palette (from latinasweatproject.com)
    static let gold  = Color(red: 1.000, green: 0.741, blue: 0.349)   // #ffbd59
    static let tan   = Color(red: 0.710, green: 0.631, blue: 0.553)   // #b5a18d
    static let cream = Color(red: 0.953, green: 0.933, blue: 0.918)   // #f3eeea

    // Semantic aliases
    static let accent      = gold
    static let accentSoft  = tan

    // Text colors (warm dark for high contrast on cream)
    static let text        = Color(red: 0.157, green: 0.125, blue: 0.102) // #28201A
    static let textMuted   = Color(red: 0.302, green: 0.255, blue: 0.212) // #4D4136
    static let textFaint   = Color(red: 0.510, green: 0.439, blue: 0.369) // #82705E

    // Surfaces
    static let surface       = Color.white
    static let surfaceSubtle = Color(red: 0.98, green: 0.965, blue: 0.950)
    static let surfaceStroke = Color(red: 0.863, green: 0.820, blue: 0.780)

    // Gradients
    static let brandGradient = LinearGradient(
        colors: [gold, tan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.970, green: 0.955, blue: 0.940),
            cream,
            Color(red: 0.933, green: 0.898, blue: 0.870)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // Status colors (warm-tinted for palette cohesion)
    static let success = Color(red: 0.262, green: 0.557, blue: 0.345) // warm green
    static let warning = gold
    static let danger  = Color(red: 0.780, green: 0.275, blue: 0.235) // warm red
}

struct StudioLogo: View {
    var size: CGFloat = 96
    var showsTitle: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            Image("logo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: Theme.tan.opacity(0.35), radius: 14, y: 6)

            if showsTitle {
                Text("INSTRUCTOR TIME CLOCK")
                    .font(.system(size: size * 0.12, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    func makeBody(configuration: Configuration) -> some View {
        let isCompact = hSizeClass == .compact
        return configuration.label
            .font(.system(size: isCompact ? 18 : 22, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 16 : 22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.brandGradient)
            )
            .shadow(color: Theme.gold.opacity(0.35), radius: 18, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    func makeBody(configuration: Configuration) -> some View {
        let isCompact = hSizeClass == .compact
        return configuration.label
            .font(.system(size: isCompact ? 16 : 18, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 13 : 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.surfaceStroke, lineWidth: 1.5)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct CardBackground: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    func body(content: Content) -> some View {
        let pad: CGFloat = hSizeClass == .compact ? 20 : 28
        return content
            .padding(pad)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Theme.surfaceStroke, lineWidth: 1)
                    )
                    .shadow(color: Theme.tan.opacity(0.15), radius: 20, y: 6)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
