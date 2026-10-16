import AVFoundation
import Foundation

/// Local-file-only playback. No server repositories, URLSession, cache or auth proxy.
@Observable
final class OfflinePlayback {
    private(set) var player: AVPlayer?
    private(set) var vlcURL: URL?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var seconds: Double = 0
    private var sessionCoordinator: PlayerSessionCoordinator?
    private let observations = ObserverBag()
    private var timeObserver: Any?
    private var loadGeneration = 0
    private var lastSave: Date = .distantPast
    private var nowPlaying: NowPlayingController?
    @ObservationIgnored private var settings: SponsorBlockSettings?
    @ObservationIgnored private weak var library: OfflineLibrary?
    private var recordID: UUID?
    private(set) var vlcSeekDelta: Double?
    private(set) var seekFeedback: PlayerSeekFeedback?
    private var feedbackTask: Task<Void, Never>?
    var seekInterval: Int { settings?.seekInterval ?? 10 }
    var doubleTapToSeek: Bool { settings?.doubleTapToSeek ?? true }

    func load(_ record: OfflineRecord, library: OfflineLibrary) async {
        stop()
        self.library = library; recordID = record.id
        settings = SponsorBlockSettings()
        seconds = 0; lastSave = .distantPast
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true; error = nil
        guard let url = library.localURL(for: record), url.isFileURL else {
            isLoading = false; error = OfflineFailure.missingFile.message; return
        }
        if record.requiresVLC {
            vlcURL = url; isLoading = false; startAudioSession(); return
        }
        do {
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable) else { throw OfflineFailure.invalidMedia }
            guard generation == loadGeneration, !Task.isCancelled else { return }
            let item = AVPlayerItem(asset: asset)
            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            avPlayer.allowsExternalPlayback = false // A local private file is played on this device.
            player = avPlayer
            observations.addKVO(item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in self?.failPlayback() }
            })
            timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self, weak library] time in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.seconds = time.seconds.isFinite ? time.seconds : 0
                    self.nowPlaying?.refresh()
                    if Date().timeIntervalSince(self.lastSave) >= 10 {
                        self.lastSave = .now; library?.savePosition(record.id, seconds: self.seconds)
                    }
                }
            }
            let duration = try await asset.load(.duration).seconds
            let end = duration.isFinite ? max(0, duration - 0.25) : .infinity
            let position = record.position >= end ? 0 : record.position
            if position > 0 { await avPlayer.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
            guard generation == loadGeneration else { return }
            startAudioSession()
            let controller = NowPlayingController(player: avPlayer, video: record.displayVideo, imageCache: .shared,
                seekInterval: seekInterval, localArtworkURL: library.thumbnailURL(record.id),
                onPlay: { [weak self] in self?.player?.play(); self?.nowPlaying?.refresh() },
                onPause: { [weak self] in self?.player?.pause(); self?.nowPlaying?.refresh() },
                onSeek: { [weak self] value in self?.player?.seek(to: CMTime(seconds: value, preferredTimescale: 600)); self?.nowPlaying?.refresh() })
            controller.start(); nowPlaying = controller
            avPlayer.play(); isLoading = false
        } catch {
            if generation == loadGeneration { failPlayback() }
        }
    }
    private func failPlayback() {
        stop()
        error = OfflineFailure.invalidMedia.message
    }
    func vlcPosition(_ value: Double) {
        if value.isFinite { seconds = max(0, value) }
        if Date().timeIntervalSince(lastSave) >= 10, let recordID {
            lastSave = .now; library?.savePosition(recordID, seconds: seconds)
        }
    }
    func seekByInterval(forward: Bool) {
        let delta = Double(seekInterval) * (forward ? 1 : -1)
        if let player, player.currentTime().seconds.isFinite {
            player.seek(to: CMTime(seconds: max(0, player.currentTime().seconds + delta), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else if vlcURL != nil { vlcSeekDelta = delta }
        feedbackTask?.cancel()
        seekFeedback = PlayerSeekFeedback(direction: forward ? .forward : .backward)
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { self?.seekFeedback = nil }
        }
    }
    func clearVLCSeekDelta() { vlcSeekDelta = nil }
    private func startAudioSession() {
        let coordinator = PlayerSessionCoordinator()
        coordinator.onInterruptionBegan = { [weak self] in self?.player?.pause() }
        coordinator.onInterruptionEnded = { [weak self] resume in
            if resume { self?.player?.play() }; self?.nowPlaying?.refresh()
        }
        coordinator.onHeadphonesUnplugged = { [weak self] in self?.player?.pause() }
        coordinator.onMediaServicesReset = { [weak self] in self?.stop() }
        sessionCoordinator = coordinator; coordinator.start()
    }
    func stop() {
        loadGeneration += 1
        player?.pause()
        if let recordID { library?.savePosition(recordID, seconds: seconds) }
        recordID = nil
        feedbackTask?.cancel(); feedbackTask = nil; seekFeedback = nil; vlcSeekDelta = nil
        nowPlaying?.stop(); nowPlaying = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver); self.timeObserver = nil }
        observations.tearDown()
        player?.replaceCurrentItem(with: nil); player = nil; vlcURL = nil
        sessionCoordinator?.stop(); sessionCoordinator = nil; isLoading = false
    }
}
