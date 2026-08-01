import SwiftUI
import SwiftData
import Combine

struct IdleView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var now = Date()

    @Query(sort: [SortDescriptor(\KioskMessage.sortOrder)])
    private var cachedMessages: [KioskMessage]

    /// Only everyone-messages are shown here — nobody has scanned a card
    /// yet, so anything role-specific or personally targeted would be
    /// broadcast to the wrong audience (or to the whole lobby).
    private var studioWideMessages: [KioskMessage] {
        cachedMessages.filter { $0.isStudioWide(on: now) }
    }

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

                if !studioWideMessages.isEmpty {
                    announcementBanner
                        .padding(.horizontal, hPad)
                }

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
        // The Idle screen is where the kiosk spends most of its life, so
        // it owns the slow background poll that keeps portal-side edits
        // trickling in even when nobody touches the iPad all afternoon.
        .onAppear { syncEngine.startIdlePolling() }
        .onDisappear { syncEngine.stopIdlePolling() }
    }

    /// Deliberately understated: a lobby screen shouldn't shout, and this
    /// sits between the clock and the primary action, so it must never
    /// compete with either.
    private var announcementBanner: some View {
        VStack(spacing: isCompact ? 8 : 10) {
            ForEach(studioWideMessages.prefix(2)) { message in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: isCompact ? 12 : 14, weight: .bold))
                        .foregroundStyle(Theme.gold)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        if !message.title.isEmpty {
                            Text(message.title)
                                .font(.system(size: isCompact ? 13 : 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.text)
                        }
                        if !message.body.isEmpty {
                            Text(message.body)
                                .font(.system(size: isCompact ? 11 : 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, isCompact ? 14 : 18)
        .padding(.vertical, isCompact ? 10 : 14)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.gold.opacity(0.45), lineWidth: 1)
                )
        )
    }
}
