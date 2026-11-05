#if DEBUG && targetEnvironment(simulator) && !UI_REVIEW_PREVIEW
import Foundation

/// Simulator-only illustrative data. All mutations are in memory; media/artwork are loopback fixtures.
@MainActor
final class StreamingFixtureRepository: VideoRepositoryProtocol, AuthRepositoryProtocol,
    DownloadRepositoryProtocol, PlaylistRepositoryProtocol, SearchRepositoryProtocol,
    ChannelRepositoryProtocol {

    private var scenario: String { ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--cinema-state=") }?.components(separatedBy: "=").last ?? "ready" }
    private func prepareState() async throws {
        if scenario == "loading" { try await Task.sleep(for: .seconds(30)) }
        if scenario == "error" { throw AppError.unknown(message: "Fixture connection unavailable") }
    }

    static let base = "http://127.0.0.1:18084"
    private(set) var videos: [Video] = {
        let names = [
            ("earthrise", "The Earth, from here", "Orbital Journal", 34.0),
            ("orbit", "On the edge of daylight", "Orbital Journal", 0.0),
            ("moon", "A world of ancient shadows", "Lunar Notes", 62.0),
            ("apollo", "The first Earthrise", "Lunar Notes", 0.0),
            ("earthrise", "A quiet kind of vast", "Orbital Journal", 0.0),
            ("moon", "Reading the lunar landscape", "Lunar Notes", 0.0)
        ]
        let count = ProcessInfo.processInfo.arguments.contains("--streaming-fixture-long-list") ? 60 : 6
        return (0..<count).map { index in
            let item = names[index % names.count]
            let id = index < 4 ? item.0 : item.0 + "-" + String(index)
            return video(id, title: item.1, channel: item.2, duration: 12, progress: item.3)
        }
    }()
    private(set) var playlists: [Playlist] = [
        Playlist(playlistId: "orbital", playlistName: "Above the atmosphere", playlistChannel: "Orbital Journal", playlistChannelId: "channel-orbital-journal", playlistType: .regular, playlistSubscribed: true, playlistThumbnail: base + "/art/orbit.jpg", playlistDescription: "An illustrative collection in the preview library.", playlistEntries: [PlaylistEntry(youtubeId: "earthrise", title: "The Earth, from here", uploader: "Orbital Journal", idx: 0, downloaded: true), PlaylistEntry(youtubeId: "orbit", title: "On the edge of daylight", uploader: "Orbital Journal", idx: 1, downloaded: true)]),
        Playlist(playlistId: "lunar", playlistName: "Quiet worlds", playlistChannel: "Personal collection", playlistChannelId: "", playlistType: .custom, playlistSubscribed: false, playlistThumbnail: base + "/art/moon.jpg", playlistDescription: "An illustrative collection in the preview library.", playlistEntries: [PlaylistEntry(youtubeId: "moon", title: "A world of ancient shadows", uploader: "Lunar Notes", idx: 0, downloaded: true)])
    ]
    private(set) var downloads: [DownloadItem] = [
        DownloadItem(youtubeId: "earthrise", title: "The Earth, from here", channelName: "Orbital Journal", channelId: "channel-orbital-journal", duration: "0:12", published: "Oct 17", status: "pending", message: nil, thumbUrl: base + "/art/earthrise.jpg", vidType: "videos", timestamp: 1),
        DownloadItem(youtubeId: "moon", title: "A world of ancient shadows", channelName: "Lunar Notes", channelId: "channel-lunar-notes", duration: "0:12", published: "Oct 17", status: "pending", message: nil, thumbUrl: base + "/art/moon.jpg", vidType: "videos", timestamp: 2),
        DownloadItem(youtubeId: "apollo", title: "The first Earthrise", channelName: "Lunar Notes", channelId: "channel-lunar-notes", duration: "0:12", published: "Oct 17", status: "ignore", message: nil, thumbUrl: base + "/art/apollo.jpg", vidType: "videos", timestamp: 3)
    ]
    private var subscriptions: [String: Bool] = [:]

    func getVideos(page: Int, sort: String, order: String, watch: String?, channel: String?, vidType: String?) async throws -> VideoListResult {
        try await prepareState()
        let filtered = scenario == "empty" ? [] : videos.filter { video in
            (channel == nil || video.channelId == channel)
            && (watch != "watched" || video.watched)
            && (watch != "unwatched" || !video.watched)
            && (watch != "continue" || (video.progress > 0 && !video.watched))
            && (vidType == nil || video.vidType == vidType)
        }
        return VideoListResult(videos: filtered, currentPage: 1, lastPage: 1, totalHits: filtered.count)
    }

    func getVideo(id: String) async throws -> Video {
        try await prepareState()
        return videos.first(where: { $0.youtubeId == id }) ?? videos[0]
    }

    func updateProgress(videoId: String, position: Double) async throws {}
    func deleteProgress(videoId: String) async throws {}

    func deleteVideo(id: String) async throws {
        videos.removeAll { $0.youtubeId == id }
    }

    func ignoreVideo(id: String) async throws {}

    func getComments(videoId: String) async throws -> [Comment] {
        [
            Comment(id: "comment-1", author: "Mira", authorId: "user-mira", authorThumbnailUrl: Self.base + "/art/moon.jpg", isUploader: false, text: "The light in this one is beautiful.", timeText: "2 days ago", likeCount: 18, isFavorited: false, parentId: "", replies: []),
            Comment(id: "comment-2", author: "Field Notes", authorId: "channel-field-notes", authorThumbnailUrl: Self.base + "/art/orbit.jpg", isUploader: true, text: "Thank you for watching.", timeText: "1 day ago", likeCount: 6, isFavorited: false, parentId: "", replies: [])
        ]
    }

    func setWatched(videoId: String, isWatched: Bool) async throws {
        guard let index = videos.firstIndex(where: { $0.youtubeId == videoId }) else { return }
        videos[index].watched = isWatched
    }

    func getSimilarVideos(videoId: String) async throws -> [Video] {
        Array(videos.filter { $0.youtubeId != videoId }.prefix(3))
    }

    func login(serverURL: String, username: String, password: String) async throws {}
    func ping() async throws -> Bool { true }
    func fetchUserAccount() async throws {}
    func logout() {}

    func getDownloads(page: Int, filter: String) async throws -> DownloadListResult {
        try await prepareState()
        let filtered = scenario == "empty" ? [] : filter == "all" ? downloads : downloads.filter { $0.status == filter }
        return DownloadListResult(items: filtered, currentPage: 1, lastPage: 1)
    }

    func updateStatus(videoId: String, status: String) async throws {
        guard let i = downloads.firstIndex(where: { $0.id == videoId }) else { return }
        let item = downloads[i]
        downloads[i] = DownloadItem(youtubeId: item.id, title: item.title, channelName: item.channelName, channelId: item.channelId, duration: item.duration, published: item.published, status: status, message: item.message, thumbUrl: item.thumbUrl, vidType: item.vidType, timestamp: item.timestamp)
    }

    func deleteDownload(videoId: String) async throws {
        downloads.removeAll { $0.youtubeId == videoId }
    }

    func addToQueue(videoId: String) async throws {}
    func startDownload() async throws {
        if ProcessInfo.processInfo.arguments.contains("--streaming-fixture-slow-queue") { try await Task.sleep(for: .seconds(3)) }
    }
    func getNotifications() async throws -> [TaskNotification] { [] }
    func killTask(id: String) async throws {}
    func rescanSubscriptions() async throws {
        if ProcessInfo.processInfo.arguments.contains("--streaming-fixture-slow-queue") { try await Task.sleep(for: .seconds(3)) }
    }

    func getPlaylists(page: Int, type: String?) async throws -> PlaylistListResult {
        try await prepareState()
        let filtered = scenario == "empty" ? [] : playlists.filter { type == nil || $0.playlistType.rawValue == type }
        return PlaylistListResult(playlists: filtered, currentPage: 1, lastPage: 1)
    }

    func getPlaylist(id: String) async throws -> Playlist {
        try await prepareState()
        return playlists.first(where: { $0.playlistId == id }) ?? playlists[0]
    }

    func getPlaylistVideos(playlistId: String, page: Int) async throws -> VideoListResult {
        try await prepareState()
        let ids = Set((playlists.first(where: { $0.playlistId == playlistId })?.playlistEntries ?? []).map(\.youtubeId))
        let result = scenario == "empty" ? [] : videos.filter { ids.contains($0.youtubeId) }
        return VideoListResult(videos: result, currentPage: 1, lastPage: 1, totalHits: result.count)
    }

    func createCustomPlaylist(name: String) async throws -> Playlist {
        let newPlaylist = Playlist(playlistId: UUID().uuidString, playlistName: name, playlistChannel: "Personal playlist", playlistChannelId: "", playlistType: .custom, playlistSubscribed: false, playlistThumbnail: Self.base + "/art/orbit.jpg", playlistDescription: nil, playlistEntries: [])
        playlists.insert(newPlaylist, at: 0)
        return newPlaylist
    }

    func updateSubscription(playlistId: String, subscribed: Bool) async throws {}
    func addVideoToPlaylist(playlistId: String, videoId: String) async throws {}
    func removeVideoFromPlaylist(playlistId: String, videoId: String) async throws {}

    func deletePlaylist(id: String, deleteVideos: Bool) async throws {
        playlists.removeAll { $0.playlistId == id }
    }

    func search(query: String, page: Int) async throws -> SearchResult {
        try await prepareState()
        return SearchResult(videos: videos.filter { ($0.title + " " + $0.channelName).localizedCaseInsensitiveContains(query) }, channels: [])
    }

    func getChannel(id: String) async throws -> Channel {
        try await prepareState()
        let lunar = id == "channel-lunar-notes"
        return Channel(channelId: id, channelName: lunar ? "Lunar Notes" : "Orbital Journal", channelThumbUrl: Self.base + (lunar ? "/art/moon.jpg" : "/art/orbit.jpg"), channelBannerUrl: Self.base + (lunar ? "/art/apollo.jpg" : "/art/earthrise.jpg"), channelDescription: "Illustrative films about the places beyond our everyday view. Test metadata and credited NASA stills; playback is a generated test clip.", channelSubscribed: subscriptions[id] ?? !lunar, channelSubs: lunar ? 1200 : 24800)
    }
    func setSubscribed(channelId: String, subscribed: Bool) async throws { subscriptions[channelId] = subscribed }

    private static func video(_ id: String, title: String, channel: String, duration: Int, progress: Double = 0) -> Video {
        let words = title.split(separator: " ")
        let channelId = "channel-" + channel.lowercased().replacingOccurrences(of: " ", with: "-")
        return Video(
            youtubeId: id,
            title: title,
            description: "An illustrative video in the preview library. Metadata is synthetic, the still is credited NASA photography, and playback is a generated twelve-second test pattern.",
            published: "2026-10-17",
            publishedShort: "Oct 17",
            downloaded: "2026-10-17",
            downloadedShort: "Oct 17",
            channelName: channel,
            channelId: channelId,
            channelThumbUrl: Self.base + (channel == "Lunar Notes" ? "/art/moon.jpg" : "/art/orbit.jpg"),
            thumbUrl: Self.base + "/art/\(id).jpg",
            mediaUrl: Self.base + "/media.mp4",
            duration: duration,
            durationStr: String(format: "%d:%02d", duration / 60, duration % 60),
            watched: false,
            progress: progress,
            position: Double(duration) * progress / 100,
            viewCount: 18_400,
            likeCount: 1_200,
            mediaSize: 0,
            vidType: id == "moon" ? "shorts" : "videos",
            category: ["Documentary"],
            tags: words.map(String.init),
            streams: [StreamInfo(type: "video", codec: "h264", bitrate: 1_000_000, width: 640, height: 360)],
            sponsorblock: [],
            playlists: []
        )
    }
}

#endif
