import SwiftUI

/// A single timed gesture annotation drawn on top of a tutorial video.
/// Positions are normalized to the video's visible frame (0–1 in both
/// axes) so a single script works regardless of the rendered size.
struct GestureEvent: Identifiable {
    enum Kind {
        case tap
        case swipe(to: CGPoint)
    }

    let id = UUID()
    var start: Double
    var duration: Double
    /// Normalized starting point. For taps this is also the only point.
    var position: CGPoint
    var kind: Kind

    var end: Double { start + duration }

    func progress(at time: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max((time - start) / duration, 0), 1)
    }

    /// Lifecycle progress that includes a short tail past `end` so taps
    /// can finish their fade-out animation cleanly. Ranges 0...1 across
    /// `[start, end + tail]`.
    func tailProgress(at time: Double, tail: Double = 0.25) -> Double {
        let total = duration + tail
        guard total > 0 else { return 0 }
        return min(max((time - start) / total, 0), 1)
    }

    func isActive(at time: Double, tail: Double = 0.25) -> Bool {
        time >= start && time <= end + tail
    }
}

/// Renders the active gesture annotations on top of a video frame. This
/// view is hit-test transparent — it is purely decoration.
struct GestureOverlay: View {
    let elapsed: Double
    let script: [GestureEvent]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(script.filter { $0.isActive(at: elapsed) }) { event in
                    eventView(event, size: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func eventView(_ event: GestureEvent, size: CGSize) -> some View {
        switch event.kind {
        case .tap:
            TapMark(progress: event.tailProgress(at: elapsed))
                .position(
                    x: event.position.x * size.width,
                    y: event.position.y * size.height
                )
        case .swipe(let target):
            SwipeMark(
                progress: event.progress(at: elapsed),
                tailProgress: event.tailProgress(at: elapsed),
                from: event.position,
                to: target,
                bounds: size
            )
        }
    }
}

// MARK: - Tap

/// Concentric ring + filled inner dot, expanding and fading. Reads as
/// "tap here" without obscuring whatever the underlying frame is showing.
private struct TapMark: View {
    /// 0 = just touched, 1 = animation finished. Includes tail fade.
    let progress: Double

    var body: some View {
        let outerScale = 0.45 + progress * 1.55
        let outerOpacity = max(0, 1 - progress) * 0.85
        let innerOpacity = max(0, 1 - progress * 1.4)

        ZStack {
            Circle()
                .stroke(Color.white.opacity(outerOpacity), lineWidth: 3.5)
                .frame(width: 84, height: 84)
                .scaleEffect(outerScale)

            Circle()
                .fill(Color.white.opacity(0.55 * innerOpacity))
                .frame(width: 36, height: 36)

            Circle()
                .stroke(Color.white.opacity(innerOpacity), lineWidth: 2)
                .frame(width: 36, height: 36)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.45), radius: 5, y: 1)
    }
}

// MARK: - Swipe

/// Leading "fingertip" puck plus a fading dot trail. The trail draws
/// from the start point to the puck's current position so the gesture
/// direction reads at a glance.
private struct SwipeMark: View {
    /// 0...1 progress along the swipe path itself.
    let progress: Double
    /// 0...1 progress including a tail fade after the swipe completes.
    let tailProgress: Double
    let from: CGPoint
    let to: CGPoint
    let bounds: CGSize

    private let trailDots = 7

    var body: some View {
        let startPoint = CGPoint(x: from.x * bounds.width, y: from.y * bounds.height)
        let currentX = (from.x + (to.x - from.x) * progress) * bounds.width
        let currentY = (from.y + (to.y - from.y) * progress) * bounds.height
        let leading = CGPoint(x: currentX, y: currentY)

        // Once the swipe is complete, fade the whole annotation.
        let remaining = max(0, 1 - max(0, (tailProgress - progress) * 4))

        ZStack {
            // Trail
            ForEach(0..<trailDots, id: \.self) { i in
                let t = Double(i) / Double(trailDots - 1) * progress
                let x = startPoint.x + (leading.x - startPoint.x) * (t / max(progress, 0.0001))
                let y = startPoint.y + (leading.y - startPoint.y) * (t / max(progress, 0.0001))
                let alpha = Double(i) / Double(trailDots - 1) * 0.55 * remaining

                Circle()
                    .fill(Color.white.opacity(alpha))
                    .frame(width: 12, height: 12)
                    .position(x: x, y: y)
            }

            // Leading puck
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.35 * remaining))
                    .frame(width: 64, height: 64)
                Circle()
                    .fill(Color.white.opacity(0.95 * remaining))
                    .frame(width: 32, height: 32)
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.5 * remaining), radius: 6, y: 2)
            .position(leading)
        }
    }
}

// MARK: - Bundled scripts

enum TutorialGesture {
    /// Synced to `AppRestartTutorial.MP4` (≈9.4s). Two gestures:
    ///   1. Bottom-edge swipe-up (hand-off → app switcher)
    ///   2. Swipe-up on the LSP Time Clock card to dismiss it.
    static let appRestart: [GestureEvent] = [
        GestureEvent(
            start: 0.55,
            duration: 0.85,
            position: CGPoint(x: 0.50, y: 0.97),
            kind: .swipe(to: CGPoint(x: 0.50, y: 0.55))
        ),
        GestureEvent(
            start: 3.55,
            duration: 0.80,
            position: CGPoint(x: 0.78, y: 0.30),
            kind: .swipe(to: CGPoint(x: 0.78, y: -0.05))
        )
    ]

    /// Synced to `AssistiveTouchTutorial.MP4` (≈28.7s). Walks the user
    /// from the time-clock app through Settings → Accessibility → Touch
    /// → AssistiveTouch, then toggles the switch off and back on.
    static let assistiveTouch: [GestureEvent] = [
        // Swipe up to home
        GestureEvent(
            start: 0.55,
            duration: 0.85,
            position: CGPoint(x: 0.50, y: 0.97),
            kind: .swipe(to: CGPoint(x: 0.50, y: 0.55))
        ),
        // Tap Settings — 8th icon in the dock (gear with red badge),
        // sitting just right of center, not at the right edge.
        GestureEvent(
            start: 4.10,
            duration: 0.45,
            position: CGPoint(x: 0.58, y: 0.94),
            kind: .tap
        ),
        // Tap Accessibility in left sidebar
        GestureEvent(
            start: 8.60,
            duration: 0.45,
            position: CGPoint(x: 0.19, y: 0.50),
            kind: .tap
        ),
        // Tap "Touch" row in right panel
        GestureEvent(
            start: 13.50,
            duration: 0.45,
            position: CGPoint(x: 0.58, y: 0.67),
            kind: .tap
        ),
        // Tap "AssistiveTouch" row at top of Touch detail
        GestureEvent(
            start: 15.40,
            duration: 0.45,
            position: CGPoint(x: 0.62, y: 0.15),
            kind: .tap
        ),
        // Tap toggle to OFF
        GestureEvent(
            start: 17.05,
            duration: 0.45,
            position: CGPoint(x: 0.92, y: 0.15),
            kind: .tap
        ),
        // Tap toggle to ON
        GestureEvent(
            start: 18.65,
            duration: 0.45,
            position: CGPoint(x: 0.92, y: 0.15),
            kind: .tap
        )
    ]
}
