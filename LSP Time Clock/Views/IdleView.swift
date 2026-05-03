import SwiftUI
import Combine

struct IdleView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()
    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let logoSize: CGFloat = isCompact ? min(140, w * 0.35) : 180
            let clockSize: CGFloat = isCompact ? min(68, w * 0.17) : 96
            let dateSize: CGFloat = isCompact ? 14 : 20
            let subtitleSize: CGFloat = isCompact ? 13 : 16
            let buttonIconSize: CGFloat = isCompact ? 26 : 32
            let buttonTextSize: CGFloat = isCompact ? 18 : 22
            let hPad: CGFloat = isCompact ? 24 : 48

            VStack(spacing: isCompact ? 24 : 36) {
                Spacer(minLength: 0)

                Image("logo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: logoSize, height: logoSize)
                    .shadow(color: Theme.tan.opacity(0.35), radius: 14, y: 6)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3) {
                        Feedback.tap()
                        coordinator.go(to: .adminPIN)
                    }

                Text("INSTRUCTOR TIME CLOCK")
                    .font(.system(size: subtitleSize, weight: .heavy, design: .rounded))
                    .tracking(isCompact ? 4 : 6)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                VStack(spacing: isCompact ? 6 : 10) {
                    Text(timeFmt.string(from: now))
                        .font(.system(size: clockSize, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    Text(dateFmt.string(from: now).uppercased())
                        .font(.system(size: dateSize, weight: .semibold, design: .rounded))
                        .tracking(isCompact ? 2 : 4)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, hPad)

                Spacer(minLength: 0)

                Button {
                    Feedback.tap()
                    coordinator.go(to: .scanning(.punch))
                } label: {
                    HStack(spacing: isCompact ? 10 : 14) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: buttonIconSize, weight: .bold))
                        Text("CLOCK IN / OUT")
                            .font(.system(size: buttonTextSize, weight: .bold, design: .rounded))
                            .tracking(isCompact ? 2 : 3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 520)

                Text("Tap the button and scan your card")
                    .font(.system(size: isCompact ? 13 : 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, isCompact ? 12 : 20)
            }
            .padding(.horizontal, hPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .onReceive(clock) { now = $0 }
    }
}
