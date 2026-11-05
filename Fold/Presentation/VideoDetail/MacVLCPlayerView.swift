#if targetEnvironment(macCatalyst)
import SwiftUI
import SwiftVLC
import UIKit
import OSLog

/// Catalyst uses libVLC's Mac build. iOS keeps its existing MobileVLCKit engine.
/// The controls and the media/progress callbacks are shared with the iOS player.
struct VLCPlayerView: UIViewControllerRepresentable {
    let mediaURL: URL
    let startPosition: Double
    let duration: Double
    let onTimeChanged: (Double) -> Void
    @Binding var isFullScreen: Bool
    var sponsorBlockSeekTarget: Double?
    var seekDelta: Double?
    var onSeekDeltaConsumed: (() -> Void)?
    var onPlaybackEnded: () -> Void = {}
    var onPlaybackResumed: () -> Void = {}
    var onDoubleTap: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> MacVLCPlayerController {
        MacVLCPlayerController(configuration: self)
    }

    func updateUIViewController(_ controller: MacVLCPlayerController, context: Context) {
        controller.configuration = self
        if let target = sponsorBlockSeekTarget, abs(controller.state.currentTime - target) > 0.5 {
            controller.seek(to: target)
        }
        if let delta = seekDelta, controller.state.duration > 0 {
            controller.seek(to: controller.state.currentTime + delta)
            DispatchQueue.main.async { onSeekDeltaConsumed?() }
        }
    }

    static func dismantleUIViewController(_ controller: MacVLCPlayerController, coordinator: ()) {
        controller.cleanup()
    }
}

final class MacVLCPlayerController: UIViewController {
    var configuration: VLCPlayerView
    let player = SwiftVLC.Player()
    let state = VLCPlayerState()
    private var host: UIHostingController<MacVLCSurface>?
    private var events: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var seekGate = PlaybackSeekGate()
    private var pendingResume: Double?
    private var lastReport: Date = .distantPast
    private var closed = false

    init(configuration: VLCPlayerView) {
        self.configuration = configuration
        state.duration = configuration.duration
        pendingResume = configuration.startPosition > 0 ? configuration.startPosition : nil
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let host = UIHostingController(rootView: MacVLCSurface(controller: self))
        self.host = host
        addChild(host)
        attachSurface(to: view)
        host.didMove(toParent: self)
        let stream = player.events
        events = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled, !self.closed else { return }
                self.receive(event)
            }
        }
        do {
            let media = try SwiftVLC.Media(url: configuration.mediaURL)
            media.addOption(":network-caching=3000")
            try player.play(media)
        } catch { report(error) }
    }

    private func receive(_ event: PlayerEvent) {
        switch event {
        case .timeChanged:
            reportTime()
        case .lengthChanged(let duration): state.duration = seconds(duration)
        case .seekableChanged(true):
            if let pendingResume {
                self.pendingResume = nil
                seek(to: pendingResume)
            }
        case .stateChanged(let playback):
            state.isPlaying = playback == .playing
            seekGate.setPlaying(state.isPlaying)
            if state.isPlaying { configuration.onPlaybackResumed(); showControls() }
            else { reportTime(force: true); showControls() }
        case .endReached:
            configuration.onPlaybackEnded()
            presentedViewController?.dismiss(animated: true)
        case .encounteredError:
            state.isPlaying = false
            showControls()
        default: break
        }
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func reportTime(force: Bool = false) {
        let time = seconds(player.currentTime)
        state.engineTime = time
        guard pendingResume == nil else { return }
        let target = seekGate.target
        let elapsed = seekGate.elapsed()
        guard seekGate.accept(time) else { return }
        if let target {
            state.confirmedSeekTarget = target
            state.confirmedSeekTime = time
            state.confirmedSeekElapsed = elapsed
        }
        state.currentTime = time
        if force || Date().timeIntervalSince(lastReport) >= 1 {
            lastReport = Date()
            configuration.onTimeChanged(time)
        }
    }

    func seek(to seconds: Double) {
        guard state.duration > 0, seconds.isFinite, !closed else { return }
        let target = max(0, min(state.duration, seconds))
        do {
            try player.seek(to: .seconds(target))
            seekGate.begin(target)
            state.currentTime = target
            configuration.onTimeChanged(target)
            showControls()
        } catch { report(error) }
    }

    func togglePlayback() {
        if player.isPlaybackRequestedActive {
            player.pause()
            seekGate.setPlaying(false)
            reportTime(force: true)
        } else if player.didReachEnd || player.state == .error {
            do { try player.play() } catch { report(error) }
        } else { player.resume() }
        showControls()
    }

    func showControls() {
        hideTask?.cancel()
        state.controlsVisible = true
        guard player.isPlaybackRequestedActive, !UIAccessibility.isVoiceOverRunning else { return }
        hideTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.player.isPlaybackRequestedActive else { return }
            self.state.controlsVisible = false
        }
    }

    func toggleControls() {
        if state.controlsVisible { hideTask?.cancel(); state.controlsVisible = false }
        else { showControls() }
    }

    func setFullScreenState(_ value: Bool) { configuration.isFullScreen = value }

    func toggleFullscreen() {
        if let presentedViewController { presentedViewController.dismiss(animated: true) }
        else {
            // Keep the detail screen's playback lifecycle alive during presentation.
            setFullScreenState(true)
            let screen = MacVLCFullscreenController(owner: self)
            screen.modalPresentationStyle = .fullScreen
            present(screen, animated: true)
        }
        showControls()
    }

    func attachSurface(to target: UIView) {
        guard let surface = host?.view else { return }
        surface.removeFromSuperview()
        surface.backgroundColor = .black
        target.addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            surface.topAnchor.constraint(equalTo: target.topAnchor),
            surface.bottomAnchor.constraint(equalTo: target.bottomAnchor)
        ])
    }

    func cleanup() {
        guard !closed else { return }
        reportTime(force: true)
        closed = true
        events?.cancel(); events = nil
        hideTask?.cancel(); hideTask = nil
        // Break the hosting view's reference back to this controller.
        host?.willMove(toParent: nil)
        host?.view.removeFromSuperview()
        host?.removeFromParent()
        host = nil
        let player = player
        Task { await player.shutdown() }
    }

    private func report(_ error: Error) {
        Logger(subsystem: "com.jacobcampbell.ta-client", category: "MacVLC")
            .error("VLC operation failed: \(error.localizedDescription, privacy: .public)")
    }
}

private struct MacVLCSurface: View {
    let controller: MacVLCPlayerController
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SwiftVLC.VideoView(controller.player)
                VLCPlayerControls(state: controller.state,
                    onPlayPause: { controller.togglePlayback() },
                    onSeek: { controller.seek(to: $0) },
                    onToggleFullScreen: { controller.toggleFullscreen() },
                    onTapToggle: { controller.toggleControls() })
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in
                        controller.configuration.onDoubleTap?(tap.location.x >= geometry.size.width / 2)
                    })
            }
        }
    }
}

private final class MacVLCFullscreenController: UIViewController {
    private weak var owner: MacVLCPlayerController?
    init(owner: MacVLCPlayerController) { self.owner = owner; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        owner?.attachSurface(to: view)
        // Escape provides a reliable keyboard exit, including when controls hide.
        addKeyCommand(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(exitFullscreen)))
    }
    @objc private func exitFullscreen() { dismiss(animated: true) }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let owner { owner.attachSurface(to: owner.view) }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        owner?.setFullScreenState(false)
    }
}
#endif
