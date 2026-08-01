import SwiftUI
import AVKit

/// Silent, autoplaying, controls-free looping video. Wraps an
/// `AVPlayerLayer` directly because SwiftUI's `VideoPlayer` always
/// renders system playback controls and `AVPlayerViewController` only
/// hides them on the parent's command, with sketchy results when the
/// view is small. Doing it at the layer level gives a clean inline
/// playback surface that fits the tutorial-card aesthetic.
struct LoopingVideoPlayer: UIViewRepresentable {
    let videoName: String
    var videoExtension: String = "MP4"
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    /// Called once after the asset loads, with the *display* size — i.e.
    /// the natural size with the preferred transform applied, so a video
    /// shot in portrait reports portrait dimensions even though the
    /// underlying buffer is encoded landscape with a rotation transform.
    var onNaturalSize: ((CGSize) -> Void)? = nil
    /// Periodic callback (~30 Hz) with the *current item's* elapsed time
    /// in seconds. AVQueuePlayer + AVPlayerLooper resets per-item time on
    /// each loop iteration, so this is a 0-based clock within one cycle —
    /// exactly what gesture overlays need to sync with the video content.
    var onTime: ((Double) -> Void)? = nil

    func makeUIView(context: Context) -> LoopingVideoUIView {
        let view = LoopingVideoUIView()
        view.videoGravity = videoGravity
        view.onNaturalSize = onNaturalSize
        view.onTime = onTime
        let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension)
            ?? Bundle.main.url(forResource: videoName, withExtension: videoExtension.lowercased())
        if let url {
            view.configure(url: url)
        }
        return view
    }

    func updateUIView(_ uiView: LoopingVideoUIView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.onNaturalSize = onNaturalSize
        uiView.onTime = onTime
    }

    static func dismantleUIView(_ uiView: LoopingVideoUIView, coordinator: ()) {
        uiView.tearDown()
    }
}

final class LoopingVideoUIView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var willEnterForegroundObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var didReportSize = false

    var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet { playerLayer?.videoGravity = videoGravity }
    }
    var onNaturalSize: ((CGSize) -> Void)?
    var onTime: ((Double) -> Void)?

    func configure(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true
        queuePlayer.allowsExternalPlayback = false
        queuePlayer.actionAtItemEnd = .advance

        // AVPlayerLooper handles seamless looping by feeding the queue
        // continuously — smoother than seeking to .zero on every end.
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = videoGravity
        self.layer.addSublayer(layer)

        self.player = queuePlayer
        self.looper = looper
        self.playerLayer = layer

        // Probe the display size asynchronously. Portrait recordings
        // typically come through as 1920x1080 with a 90° transform, so
        // we apply the preferred transform to get the size as it'll
        // actually render on screen.
        Task { [weak self] in
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { return }
                let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
                let applied = natural.applying(transform)
                let display = CGSize(width: abs(applied.width), height: abs(applied.height))
                await MainActor.run {
                    guard let self, !self.didReportSize, display.width > 0, display.height > 0 else { return }
                    self.didReportSize = true
                    self.onNaturalSize?(display)
                }
            } catch {
                // Non-fatal: caller falls back to its default aspect ratio.
            }
        }

        // Autoplay routes audio through the silent default; even though
        // we mute, configure the session to .ambient so we never duck or
        // interrupt other audio if the device's policy ever changes.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])

        // ~30 Hz time observer for syncing gesture overlays. Per-item
        // time resets on loop, which is what we want.
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = queuePlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.onTime?(CMTimeGetSeconds(time))
        }

        queuePlayer.play()

        // Pause when backgrounded; AVPlayer can't render off-screen and
        // some iPad firmware throws errors that re-enter the foreground
        // with the player in a bad state. Resume on foreground.
        let nc = NotificationCenter.default
        didEnterBackgroundObserver = nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak queuePlayer] _ in
            queuePlayer?.pause()
        }
        willEnterForegroundObserver = nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak queuePlayer] _ in
            queuePlayer?.play()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func tearDown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        looper = nil
        playerLayer?.removeFromSuperlayer()
        if let didEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(didEnterBackgroundObserver)
        }
        if let willEnterForegroundObserver {
            NotificationCenter.default.removeObserver(willEnterForegroundObserver)
        }
    }

    deinit { tearDown() }
}
