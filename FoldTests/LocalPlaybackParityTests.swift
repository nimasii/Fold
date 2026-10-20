import Foundation
import AVFoundation
import SwiftUI
import Testing
@testable import Fold

private final class ParityFixtureBundle: NSObject {}

@MainActor @Suite(.serialized) struct LocalPlaybackParityTests {
    @Test(arguments: ["h264", "hevc", "av1", "vp9", "VP09", "vp8"])
    func localAndOnlineUseTheSameCodecSelectorIncludingLegacyWebM(codec: String) throws {
        let video = TestData.video(streams: [StreamInfo(type: "video", codec: codec, bitrate: 0, width: 640, height: 360)])
        var record = OfflineRecord(video: video, origin: "https://example.com", mediaPath: "/video.webm")
        record.kind = .webm
        #expect(CodecSupport.requiredPlayer(for: record.displayVideo.streams) == CodecSupport.requiredPlayer(for: video.streams))
        record.metadata = nil
        #expect(CodecSupport.requiredPlayer(for: record.displayVideo.streams) == CodecSupport.requiredPlayer(for: video.streams))
        #expect(record.displayVideo.mediaUrl.isEmpty && record.displayVideo.thumbUrl.isEmpty)
    }

    @Test func missingStreamMetadataUsesOneConservativeWebMFallback() {
        #expect(CodecSupport.requiredPlayer(for: [], fileExtension: "webm") == .vlcPlayer)
        #expect(CodecSupport.requiredPlayer(for: [], fileExtension: "mp4") == .avPlayer)
    }

    @Test func vlcFullscreenOwnershipIsPublishedToNormalDetailLifecycle() {
        var fullScreen = false
        let coordinator = VLCPlayerView.Coordinator(onTimeChanged: { _ in },
            isFullScreen: .init(get: { fullScreen }, set: { fullScreen = $0 }))
        let container = VLCPlayerContainerVC(mediaURL: URL(fileURLWithPath: "/fixture.webm"), startPosition: 0,
            duration: 12, coordinator: coordinator)
        container.setFullScreenState(true)
        #expect(fullScreen)
        container.setFullScreenState(false)
        #expect(!fullScreen)
    }

    private func make(codec: String = "h264", position: Double = 0) throws -> (VideoDetailViewModel, OfflineLibrary, AuthState, URL) {
        let auth = AuthState(keychainService: KeychainService(inMemory: true), loadPersistedCredentials: false)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalPlaybackParity-" + UUID().uuidString)
        let disk = try OfflineDiskStore(root: root)
        var record = OfflineRecord(video: TestData.video(position: position, duration: 2,
            streams: [StreamInfo(type: "video", codec: codec, bitrate: 0, width: 320, height: 180)]),
            origin: "https://example.com", mediaPath: "/clip.mp4")
        record.kind = .mp4; record.status = .ready; record.position = position
        let clip = try #require(Bundle(for: ParityFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4"))
        try FileManager.default.copyItem(at: clip, to: #require(disk.file(for: record)))
        record.bytes = Int64(try Data(contentsOf: clip).count)
        try disk.save([record])
        let library = OfflineLibrary(authState: auth, root: root)
        let source = LocalVideoPlayback(record: record, library: library)
        let defaults = UserDefaults(suiteName: "LocalPlaybackParity-" + UUID().uuidString)!
        let settings = SponsorBlockSettings(defaults: defaults); settings.seekInterval = 15; settings.doubleTapToSeek = false
        let vm = VideoDetailViewModel(videoId: record.id.uuidString, videoRepository: LocalVideoRepository(source: source),
            authState: auth, router: AppRouter(authState: auth), sponsorBlockSettings: settings, localPlayback: source)
        return (vm, library, auth, root)
    }

    @Test func localVLCUsesNormalControllerPreferencesAndPersistsOnlyPrivateProgress() async throws {
        let (vm, library, auth, root) = try make(codec: "vp9")
        defer { vm.stopPlayback(); try? FileManager.default.removeItem(at: root) }
        await vm.loadVideo(); vm.startPlayback()
        for _ in 0..<100 where vm.vlcMediaURL == nil { await Task.yield() }
        #expect(vm.playerType == .vlcPlayer && vm.vlcMediaURL?.isFileURL == true)
        #expect(vm.seekInterval == 15 && !vm.doubleTapToSeek)
        vm.seekByInterval(forward: true)
        #expect(vm.vlcSeekDelta == 15)
        vm.clearVLCSeekDelta(); #expect(vm.vlcSeekDelta == nil)
        vm.onVLCTimeChanged(seconds: 1)
        _ = await vm.saveProgress(position: 1)
        #expect(library.records.first?.position == 1)
        #expect(!auth.isAuthenticated)
        #expect(vm.installedProxyForTests == nil && !vm.pendingProxyStartForTests)
        vm.stopPlayback()
        #expect(vm.vlcMediaURL == nil && vm.player == nil && !vm.isBuffering)
    }

    @Test func localAVUsesNormalItemConfigurationAndEndReplayController() async throws {
        let (vm, library, _, root) = try make(position: 2)
        defer { vm.stopPlayback(); try? FileManager.default.removeItem(at: root) }
        await vm.loadVideo()
        #expect(vm.startPosition == 0)
        vm.startPlayback()
        let player = try #require(vm.player)
        #expect((player.currentItem?.asset as? AVURLAsset)?.url.isFileURL == true)
        #expect(!player.allowsExternalPlayback)
        #expect(player.currentItem?.preferredForwardBufferDuration == 10)
        #expect(vm.installedProxyForTests == nil && !vm.pendingProxyStartForTests)
        vm.handleDidPlayToEnd()
        _ = await vm.saveProgress(position: 2)
        #expect(library.records.first?.position == 2)
        vm.handlePlaybackFailure(message: "Fixture failure")
        #expect(vm.player == nil && vm.playbackError == "Fixture failure")
        vm.playbackError = nil; vm.startPlayback()
        #expect(vm.player != nil)
    }

    @Test func missingPrivateFileFailsWithoutNetworkFallback() async throws {
        let (vm, library, _, root) = try make()
        defer { vm.stopPlayback(); try? FileManager.default.removeItem(at: root) }
        let record = try #require(library.records.first)
        try FileManager.default.removeItem(at: #require(library.localURL(for: record)))
        await vm.loadVideo(); vm.startPlayback()
        #expect(vm.player == nil && vm.vlcMediaURL == nil)
        #expect(vm.playbackError == OfflineFailure.missingFile.message)
        #expect(vm.installedProxyForTests == nil && !vm.pendingProxyStartForTests)
    }
}
