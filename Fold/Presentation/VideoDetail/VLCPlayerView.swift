import SwiftUI
import MobileVLCKit
import OSLog

private let logger = Logger(subsystem: "ru.mzhukov.TAClient", category: "VLCPlayer")

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
    var onDoubleTap: ((_ forward: Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTimeChanged: onTimeChanged, onDoubleTap: onDoubleTap, isFullScreen: $isFullScreen, onPlaybackEnded: onPlaybackEnded, onPlaybackResumed: onPlaybackResumed)
    }

    func makeUIViewController(context: Context) -> VLCPlayerContainerVC {
        let vc = VLCPlayerContainerVC(
            mediaURL: mediaURL,
            startPosition: startPosition,
            duration: duration,
            coordinator: context.coordinator
        )
        context.coordinator.containerVC = vc
        return vc
    }

    func updateUIViewController(_ vc: VLCPlayerContainerVC, context: Context) {
        context.coordinator.isFullScreen = $isFullScreen
        context.coordinator.onTimeChanged = onTimeChanged
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.onPlaybackResumed = onPlaybackResumed
        context.coordinator.onDoubleTap = onDoubleTap
        vc.doubleTapRecognizer?.isEnabled = onDoubleTap != nil
        if let target = sponsorBlockSeekTarget, vc.playerState.duration > 0, abs(vc.playerState.currentTime - target) > 0.5 {
            vc.seek(to: target)
        }
        if let delta = seekDelta, vc.playerState.duration > 0 {
            let newTime = max(0, min(vc.playerState.duration, vc.playerState.currentTime + delta))
            vc.seek(to: newTime)
            DispatchQueue.main.async { onSeekDeltaConsumed?() }
        }
    }
}

// MARK: - Coordinator

extension VLCPlayerView {
    class Coordinator: NSObject, VLCMediaPlayerDelegate, UIGestureRecognizerDelegate {
        var isFullScreen: Binding<Bool>
        var onTimeChanged: (Double) -> Void
        var onPlaybackEnded: () -> Void
        var onPlaybackResumed: () -> Void
        var onDoubleTap: ((_ forward: Bool) -> Void)?
        weak var containerVC: VLCPlayerContainerVC?
        private var lastProgressReport: Date = .distantPast

        init(onTimeChanged: @escaping (Double) -> Void, onDoubleTap: ((_ forward: Bool) -> Void)? = nil, isFullScreen: Binding<Bool>, onPlaybackEnded: @escaping () -> Void = {}, onPlaybackResumed: @escaping () -> Void = {}) {
            self.isFullScreen = isFullScreen
            self.onPlaybackEnded = onPlaybackEnded
            self.onPlaybackResumed = onPlaybackResumed
            self.onTimeChanged = onTimeChanged
            self.onDoubleTap = onDoubleTap
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            let forward = location.x >= view.bounds.width / 2
            onDoubleTap?(forward)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private var seekGate = PlaybackSeekGate()
        var isSeekPending: Bool { seekGate.target != nil }
        func setPlaying(_ value: Bool) { seekGate.setPlaying(value) }

        func beginSeek(_ target: Double, report: Bool) {
            seekGate.begin(target)
            containerVC?.playerState.confirmedSeekTarget = -1
            containerVC?.playerState.confirmedSeekTime = -1
            containerVC?.playerState.currentTime = target
            if report { onTimeChanged(target) }
        }

        func reportTime(_ player: VLCMediaPlayer, force: Bool = false) {
            guard containerVC?.mediaPlayer === player else { return }
            // Read on the MainActor at execution time, never a timestamp captured
            // by an older delegate notification before a seek.
            let seconds = Double(player.time.intValue) / 1000
            containerVC?.playerState.engineTime = seconds
            let duration = Double(player.media?.length.intValue ?? 0) / 1000
            if duration > 0 { containerVC?.playerState.duration = duration }
            let requested = seekGate.target
            let elapsed = seekGate.elapsed()
            guard seekGate.accept(seconds) else { return }
            if let requested {
                containerVC?.playerState.confirmedSeekTarget = requested
                containerVC?.playerState.confirmedSeekTime = seconds
                containerVC?.playerState.confirmedSeekElapsed = elapsed
            }
            containerVC?.playerState.currentTime = seconds
            if force || Date().timeIntervalSince(lastProgressReport) >= 1 {
                lastProgressReport = Date()
                onTimeChanged(seconds)
            }
        }

        func mediaPlayerTimeChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            Task { @MainActor [weak self, weak player] in
                guard let self, let player else { return }
                self.reportTime(player)
            }
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.containerVC?.mediaPlayer === player else { return }
                let state = player.state
                self.setPlaying(player.isPlaying)
                self.containerVC?.playerState.isPlaying = player.isPlaying
                if player.isPlaying { self.onPlaybackResumed(); self.containerVC?.scheduleHideControls() }
                else { self.containerVC?.showPausedControls() }
                if state == .paused { self.reportTime(player, force: true) }
                if state == .error {
                    logger.error("Player state: error, attempting restart")
                    self.containerVC?.restartMedia()
                } else if state == .ended {
                    self.onPlaybackEnded()
                    self.containerVC?.exitFullScreenIfNeeded()
                }
            }
        }
    }
}

// MARK: - Container ViewController

class VLCPlayerContainerVC: UIViewController {
    let drawableView = UIView()
    let playerState: VLCPlayerState
    var mediaPlayer: VLCMediaPlayer?

    private let mediaURL: URL
    private let startPosition: Double
    private let initialDuration: Double
    private weak var coordinator: VLCPlayerView.Coordinator?

    fileprivate var controlsHost: UIHostingController<VLCPlayerControls>?
    fileprivate weak var doubleTapRecognizer: UITapGestureRecognizer?
    private var hideTimer: Timer?
    private var seekConfirmationTask: Task<Void, Never>?

    init(mediaURL: URL, startPosition: Double, duration: Double, coordinator: VLCPlayerView.Coordinator) {
        let state = VLCPlayerState()
        state.duration = duration
        self.playerState = state
        self.mediaURL = mediaURL
        self.startPosition = startPosition
        self.initialDuration = duration
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupDrawable()
        setupControls()
        setupPlayer()
        setupDoubleTapRecognizer()
    }

    private func setupDoubleTapRecognizer() {
        guard let coordinator else { return }
        let tap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(VLCPlayerView.Coordinator.handleDoubleTap(_:))
        )
        tap.numberOfTapsRequired = 2
        tap.cancelsTouchesInView = false
        tap.delegate = coordinator
        view.addGestureRecognizer(tap)
        self.doubleTapRecognizer = tap
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            cleanup()
        }
    }

    func cleanup() {
        seekConfirmationTask?.cancel(); seekConfirmationTask = nil
        hideTimer?.invalidate()
        hideTimer = nil
        mediaPlayer?.stop()
        mediaPlayer = nil
    }

    func restartMedia() {
        let resumePosition = playerState.currentTime
        mediaPlayer?.stop()

        let media = VLCMedia(url: mediaURL)
        media.addOptions(["network-caching": 3000])
        mediaPlayer?.media = media
        if resumePosition > 0 { coordinator?.beginSeek(resumePosition, report: false) }
        coordinator?.setPlaying(true)
        mediaPlayer?.play()

        if resumePosition > 0, playerState.duration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let player = self.mediaPlayer else { return }
                player.time = VLCTime(int: Int32(min(resumePosition * 1000, Double(Int32.max))))
            }
        }
    }

    // MARK: - Setup

    private func setupDrawable() {
        drawableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(drawableView)
        NSLayoutConstraint.activate([
            drawableView.topAnchor.constraint(equalTo: view.topAnchor),
            drawableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            drawableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupPlayer() {
        let media = VLCMedia(url: mediaURL)
        media.addOptions(["network-caching": 3000])

        let player = VLCMediaPlayer()
        player.delegate = coordinator
        player.drawable = drawableView
        player.media = media
        self.mediaPlayer = player
        if startPosition > 0 { coordinator?.beginSeek(startPosition, report: false) }
        coordinator?.setPlaying(true)
        player.play()

        if startPosition > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let player = self.mediaPlayer else { return }
                player.time = VLCTime(int: Int32(min(self.startPosition * 1000, Double(Int32.max))))
            }
        }

        scheduleHideControls()
    }

    // MARK: - Controls

    private func setupControls() {
        let controls = VLCPlayerControls(
            state: playerState,
            onPlayPause: { [weak self] in self?.togglePlayPause() },
            onSeek: { [weak self] seconds in self?.seek(to: seconds) },
            onToggleFullScreen: { [weak self] in self?.toggleFullScreen() },
            onTapToggle: { [weak self] in self?.handleTap() }
        )
        let host = UIHostingController(rootView: controls)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
        host.didMove(toParent: self)
        controlsHost = host
    }

    func exitFullScreenIfNeeded() {
        if let presented = presentedViewController as? VLCFullScreenVC {
            presented.dismiss(animated: true)
        }
    }

    // MARK: - Actions

    private func togglePlayPause() {
        guard let player = mediaPlayer else { return }
        if player.isPlaying { coordinator?.setPlaying(false); player.pause(); coordinator?.reportTime(player, force: true); showPausedControls() }
        else { coordinator?.setPlaying(true); player.play(); scheduleHideControls() }
    }

    fileprivate func seek(to seconds: Double) {
        guard let player = mediaPlayer, playerState.duration > 0 else { return }
        let target = min(max(seconds, 0), playerState.duration)
        coordinator?.beginSeek(target, report: true)
        player.time = VLCTime(int: Int32(min(target * 1000, Double(Int32.max))))
        // VLC 3 caches its clock while paused. Keep the requested bookmark;
        // actual clock callbacks confirm it after the player resumes.
        seekConfirmationTask?.cancel()
        seekConfirmationTask = Task { @MainActor [weak self, weak player] in
            for _ in 0..<30 {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, let player, self.mediaPlayer === player else { return }
                self.coordinator?.reportTime(player, force: true)
                if self.coordinator?.isSeekPending == false { return }
            }
        }
        if player.isPlaying { scheduleHideControls() } else { showPausedControls() }
    }

    private func toggleFullScreen() {
        if let presented = presentedViewController as? VLCFullScreenVC {
            presented.dismiss(animated: true)
        } else {
            // The detail screen disappears during full-screen presentation. Publish
            // ownership first so its normal onDisappear cannot stop the live player.
            setFullScreenState(true)
            let fullScreenVC = VLCFullScreenVC(containerVC: self)
            fullScreenVC.modalPresentationStyle = .fullScreen
            present(fullScreenVC, animated: true)
        }
    }

    func setFullScreenState(_ value: Bool) {
        coordinator?.isFullScreen.wrappedValue = value
    }

    func reparentDrawable(to targetView: UIView) {
        drawableView.removeFromSuperview()
        drawableView.translatesAutoresizingMaskIntoConstraints = false
        targetView.insertSubview(drawableView, at: 0)
        NSLayoutConstraint.activate([
            drawableView.topAnchor.constraint(equalTo: targetView.topAnchor),
            drawableView.bottomAnchor.constraint(equalTo: targetView.bottomAnchor),
            drawableView.leadingAnchor.constraint(equalTo: targetView.leadingAnchor),
            drawableView.trailingAnchor.constraint(equalTo: targetView.trailingAnchor),
        ])
        mediaPlayer?.drawable = drawableView
    }

    private func handleTap() {
        playerState.controlsVisible.toggle()
        if playerState.controlsVisible {
            scheduleHideControls()
        } else {
            hideTimer?.invalidate()
        }
    }

    fileprivate func showPausedControls() {
        hideTimer?.invalidate()
        playerState.controlsVisible = true
    }

    fileprivate func scheduleHideControls() {
        hideTimer?.invalidate()
        playerState.controlsVisible = true
        guard mediaPlayer?.isPlaying == true, !UIAccessibility.isVoiceOverRunning else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard self?.mediaPlayer?.isPlaying == true, !UIAccessibility.isVoiceOverRunning else { return }
            self?.playerState.controlsVisible = false
        }
    }
}

// MARK: - Full Screen ViewController

private class VLCFullScreenVC: UIViewController {
    private weak var containerVC: VLCPlayerContainerVC?

    init(containerVC: VLCPlayerContainerVC) {
        self.containerVC = containerVC
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        containerVC?.reparentDrawable(to: view)
        reparentControls(to: view)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let containerVC else { return }
        containerVC.reparentDrawable(to: containerVC.view)
        reparentControls(to: containerVC.view)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Clear after the presenting detail screen has reappeared, matching AVKit.
        containerVC?.setFullScreenState(false)
    }

    private func reparentControls(to targetView: UIView) {
        guard let controlsView = containerVC?.controlsHost?.view else { return }
        controlsView.removeFromSuperview()
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        targetView.addSubview(controlsView)
        let guide = targetView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            controlsView.topAnchor.constraint(equalTo: guide.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            controlsView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
    }
}
