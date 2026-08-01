import SwiftUI

/// Self-help sheet shown from the "Waiting for Card" screen when an
/// employee can't get a scan to register. Three swipeable pages: a video
/// walkthrough for restarting the kiosk, a video walkthrough for forcing
/// the on-screen keyboard back via AssistiveTouch, and a written tips
/// page for everything else.
struct TroubleshootingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int = 0

    private let pageCount = 3

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                TabView(selection: $page) {
                    restartGuide
                        .tag(0)
                    keyboardGuide
                        .tag(1)
                    additionalTips
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .navigationTitle("Having Trouble?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    // MARK: - Guide 1

    private var restartGuide: some View {
        GuidePage(
            badge: "Step 1",
            title: "Restart the Scanner & App",
            videoName: "AppRestartTutorial",
            gestureScript: TutorialGesture.appRestart,
            steps: [
                "Unplug the USB-C device connected to the iPad, then plug it back in.",
                "Drag up from the bottom of the screen and fully swipe the app away to close it out.",
                "Re-open the app and try scanning again."
            ]
        )
    }

    // MARK: - Guide 2

    private var keyboardGuide: some View {
        GuidePage(
            badge: "Step 2",
            title: "Bring Back the On-Screen Keyboard",
            subtitle: "Because the scanner acts as a hardware keyboard, the iPad hides the on-screen keyboard. Toggling AssistiveTouch forces it to reappear.",
            videoName: "AssistiveTouchTutorial",
            gestureScript: TutorialGesture.assistiveTouch,
            steps: [
                "Open the iPad's Settings app.",
                "Go to Accessibility ▸ Touch ▸ AssistiveTouch.",
                "Turn AssistiveTouch OFF, then ON again."
            ]
        )
    }

    // MARK: - Guide 3

    private var additionalTips: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("STEP 3")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Theme.gold)

                Text("Additional Tips")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.text)

                tipCard(
                    icon: "hand.tap.fill",
                    title: "Wake up the scanner",
                    body: "Tap anywhere on the \"Waiting for Card\" screen to wake up the scanner and ensure the app is actively listening."
                )

                tipCard(
                    icon: "battery.50",
                    title: "Check the battery",
                    body: "Make sure the iPad has battery and the charger is working. If the battery dies, the USB-C port stops receiving data from the scanner."
                )

                tipCard(
                    icon: "power",
                    title: "Hard restart the iPad",
                    body: "If all else fails, hold down the power button and restart the iPad entirely."
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 72)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tipCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.gold.opacity(0.18)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(body)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.surfaceStroke, lineWidth: 1)
                )
                .shadow(color: Theme.tan.opacity(0.10), radius: 10, y: 4)
        )
    }
}

// MARK: - Reusable page layout

private struct GuidePage: View {
    let badge: String
    let title: String
    var subtitle: String? = nil
    let videoName: String
    var gestureScript: [GestureEvent] = []
    let steps: [String]

    /// Probed asynchronously from the bundled video. Defaults to a
    /// reasonable landscape ratio while the asset is still loading.
    @State private var videoAspect: CGFloat = 16.0 / 9.0
    @State private var elapsed: Double = 0

    private var isPortraitVideo: Bool { videoAspect < 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(badge.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Theme.gold)

                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                videoCard

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        stepRow(number: index + 1, text: step)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            // Bottom inset clears the page-indicator dots from
            // .tabViewStyle(.page) so step text never sits underneath
            // the dot strip.
            .padding(.bottom, 72)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var videoCard: some View {
        // Portrait videos get clamped to a phone-screenshot-sized column
        // and centered. Landscape videos fill the available width.
        let card = ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)

            LoopingVideoPlayer(
                videoName: videoName,
                onNaturalSize: { size in
                    let ratio = size.height > 0 ? size.width / size.height : 16.0 / 9.0
                    if abs(ratio - videoAspect) > 0.01 {
                        videoAspect = ratio
                    }
                },
                onTime: { t in elapsed = t }
            )

            // Hand-drawn gesture annotations sit on top of the video,
            // matched to the player's per-loop elapsed time.
            if !gestureScript.isEmpty {
                GestureOverlay(elapsed: elapsed, script: gestureScript)
            }
        }
        .aspectRatio(videoAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.surfaceStroke, lineWidth: 1)
        )
        .shadow(color: Theme.tan.opacity(0.18), radius: 18, y: 8)

        if isPortraitVideo {
            HStack {
                Spacer()
                card.frame(maxWidth: 320)
                Spacer()
            }
        } else {
            card
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.gold))

            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
