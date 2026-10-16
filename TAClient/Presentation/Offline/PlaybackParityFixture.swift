#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Exercises shipping views, engine selection, transport and controls. Only the
/// metadata repository is synthetic. Release builds cannot enter this harness.
struct PlaybackParityFixtureView: View {
    @State private var fixture: PlaybackParityFixture?
    var body: some View {
        Group {
            if let fixture { PlaybackParityFixtureContent(fixture: fixture) }
            else { LoadingView() }
        }
        .task { if fixture == nil { fixture = PlaybackParityFixture() } }
    }
}

private struct PlaybackParityFixtureContent: View {
    let fixture: PlaybackParityFixture
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Online video") {
                    VideoDetailScreen { fixture.makeOnlinePlayer() }
                }
                Button("Prepare local copy") { fixture.library.enqueue(fixture.video) }
                    .accessibilityLabel("Prepare local copy")
                NavigationLink("Downloads") {
                    OfflineDownloadsView(playbackSettings: fixture.settings)
                }
                Text("Synthetic media · \(fixture.isVLC ? "VP9 / VLC" : "H.264 / AVKit") · 15s seek")
            }
            .navigationTitle("Production playback fixture")
        }
        .environment(fixture.auth)
        .environment(fixture.router)
        .environment(fixture.library)
    }
}

@Observable
private final class PlaybackParityFixture {
    let auth: AuthState
    let router: AppRouter
    let library: OfflineLibrary
    let settings: SponsorBlockSettings
    let video: Video
    let isVLC: Bool
    init() {
        let args = ProcessInfo.processInfo.arguments
        isVLC = args.contains("--playback-fixture-vlc")
        auth = AuthState(keychainService: KeychainService(inMemory: true), loadPersistedCredentials: false)
        let base = URL(string: "http://127.0.0.1:18083")!
        let cookie = HTTPCookie(properties: [.name: "sessionid", .value: "fixture", .domain: "127.0.0.1", .path: "/"])!
        try? auth.setSession(cookies: [cookie], serverURL: base)
        router = AppRouter(authState: auth)
        let defaults = UserDefaults(suiteName: "PlaybackParityFixture")!
        settings = SponsorBlockSettings(defaults: defaults)
        settings.seekInterval = 15; settings.doubleTapToSeek = true
        let filename = isVLC ? "parity-vp9.webm" : "parity-h264.mp4"
        video = Video(youtubeId: isVLC ? "parity-vp9" : "parity-h264", title: "Production Playback Comparison",
            description: "The same generated clip, normal player and settings for streaming and local playback.",
            published: "", publishedShort: "", downloaded: "", downloadedShort: "",
            channelName: "Fixture Studio", channelId: "", channelThumbUrl: nil, thumbUrl: "",
            mediaUrl: base.appendingPathComponent(filename).absoluteString, duration: 12, durationStr: "0:12",
            watched: false, progress: 0, position: 0, viewCount: 0, likeCount: 0, mediaSize: 0,
            vidType: "videos", category: [], tags: [], streams: [StreamInfo(type: "video", codec: isVLC ? "vp9" : "h264", bitrate: 0, width: 640, height: 360)], sponsorblock: [], playlists: [])
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlaybackParityFixture-v1").appendingPathComponent(isVLC ? "vp9" : "h264")
        if args.contains("--playback-fixture-reset") { try? FileManager.default.removeItem(at: root) }
        library = OfflineLibrary(authState: auth, root: root)
    }
    func makeOnlinePlayer() -> VideoDetailViewModel {
        VideoDetailViewModel(videoId: video.youtubeId, videoRepository: PlaybackFixtureRepository(video: video),
            authState: auth, router: router, sponsorBlockSettings: settings)
    }
}

private final class PlaybackFixtureRepository: VideoRepositoryProtocol {
    let video: Video
    init(video: Video) { self.video = video }
    func getVideo(id: String) async throws -> Video { video }
    func updateProgress(videoId: String, position: Double) async throws {}
    func getComments(videoId: String) async throws -> [Comment] { [] }
    func getSimilarVideos(videoId: String) async throws -> [Video] { [] }
    func getVideos(page: Int, sort: String, order: String, watch: String?, channel: String?, vidType: String?) async throws -> VideoListResult { throw OfflineFailure.missingFile }
    func deleteProgress(videoId: String) async throws { throw OfflineFailure.missingFile }
    func deleteVideo(id: String) async throws { throw OfflineFailure.missingFile }
    func ignoreVideo(id: String) async throws { throw OfflineFailure.missingFile }
    func setWatched(videoId: String, isWatched: Bool) async throws { throw OfflineFailure.missingFile }
}
#endif
