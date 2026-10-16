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

    func load(_ record: OfflineRecord, library: OfflineLibrary) async {
        stop()
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
                Task { @MainActor [weak self] in self?.error = OfflineFailure.invalidMedia.message }
            })
            timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self, weak library] time in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.seconds = time.seconds.isFinite ? time.seconds : 0
                    if Date().timeIntervalSince(self.lastSave) >= 10 {
                        self.lastSave = .now; library?.savePosition(record.id, seconds: self.seconds)
                    }
                }
            }
            if record.position > 0 { await avPlayer.seek(to: CMTime(seconds: record.position, preferredTimescale: 600)) }
            guard generation == loadGeneration else { return }
            startAudioSession(); avPlayer.play(); isLoading = false
        } catch {
            if generation == loadGeneration { isLoading = false; self.error = OfflineFailure.invalidMedia.message }
        }
    }
    func vlcPosition(_ value: Double) { if value.isFinite { seconds = max(0, value) } }
    private func startAudioSession() {
        let coordinator = PlayerSessionCoordinator()
        coordinator.onInterruptionBegan = { [weak self] in self?.player?.pause() }
        coordinator.onHeadphonesUnplugged = { [weak self] in self?.player?.pause() }
        coordinator.onMediaServicesReset = { [weak self] in self?.stop() }
        sessionCoordinator = coordinator; coordinator.start()
    }
    func stop() {
        loadGeneration += 1
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver); self.timeObserver = nil }
        observations.tearDown()
        player?.replaceCurrentItem(with: nil); player = nil; vlcURL = nil
        sessionCoordinator?.stop(); sessionCoordinator = nil; isLoading = false
    }
}
