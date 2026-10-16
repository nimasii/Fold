import Foundation

/// In-memory fixtures for the separately built UI review app. Every mutating
/// operation affects only these values; this repository has no network client.
@MainActor
final class UIReviewPreviewRepository: VideoRepositoryProtocol, AuthRepositoryProtocol,
    DownloadRepositoryProtocol, PlaylistRepositoryProtocol, SearchRepositoryProtocol,
    ChannelRepositoryProtocol {

    private(set) var videos: [Video] = [
        UIReviewPreviewRepository.video("morning", title: "A Quiet Morning in the Mountains", channel: "Field Notes", duration: 1122, progress: 34),
        UIReviewPreviewRepository.video("workshop", title: "Building a Small Wooden Cabin", channel: "Workshop Journal", duration: 728),
        UIReviewPreviewRepository.video("kyoto", title: "A Slow Walk Through Kyoto", channel: "Everyday Atlas", duration: 571),
        UIReviewPreviewRepository.video("camera", title: "Restoring a Classic Camera", channel: "Analog Days", duration: 1456),
        UIReviewPreviewRepository.video("garden", title: "A Garden Through the Seasons", channel: "Field Notes", duration: 936),
        UIReviewPreviewRepository.video("coffee", title: "The Art of Slow Coffee", channel: "Everyday Atlas", duration: 803)
    ]

    private(set) var playlists: [Playlist] = [
        Playlist(
            playlistId: "quiet-places",
            playlistName: "Quiet Places",
            playlistChannel: "Everyday Atlas",
            playlistChannelId: "channel-everyday-atlas",
            playlistType: .regular,
            playlistSubscribed: true,
            playlistThumbnail: "preview://playlist/quiet-places",
            playlistDescription: "Thoughtful places and slower days.",
            playlistEntries: [
                PlaylistEntry(youtubeId: "morning", title: "A Quiet Morning in the Mountains", uploader: "Field Notes", idx: 0, downloaded: true),
                PlaylistEntry(youtubeId: "kyoto", title: "A Slow Walk Through Kyoto", uploader: "Everyday Atlas", idx: 1, downloaded: true)
            ]
        ),
        Playlist(
            playlistId: "saved-later",
            playlistName: "Saved for Later",
            playlistChannel: "Personal playlist",
            playlistChannelId: "",
            playlistType: .custom,
            playlistSubscribed: false,
            playlistThumbnail: "preview://playlist/saved-later",
            playlistDescription: "A small collection to revisit.",
            playlistEntries: [
                PlaylistEntry(youtubeId: "workshop", title: "Building a Small Wooden Cabin", uploader: "Workshop Journal", idx: 0, downloaded: true)
            ]
        )
    ]

    private(set) var downloads: [DownloadItem] = [
        DownloadItem(youtubeId: "morning", title: "A Quiet Morning in the Mountains", channelName: "Field Notes", channelId: "channel-field-notes", duration: "18:42", published: "Oct 8", status: "pending", message: nil, thumbUrl: "preview://video/morning", vidType: "videos", timestamp: 1),
        DownloadItem(youtubeId: "workshop", title: "Building a Small Wooden Cabin", channelName: "Workshop Journal", channelId: "channel-workshop", duration: "12:08", published: "Oct 7", status: "pending", message: nil, thumbUrl: "preview://video/workshop", vidType: "videos", timestamp: 2),
        DownloadItem(youtubeId: "kyoto", title: "A Slow Walk Through Kyoto", channelName: "Everyday Atlas", channelId: "channel-everyday-atlas", duration: "09:31", published: "Oct 6", status: "pending", message: nil, thumbUrl: "preview://video/kyoto", vidType: "videos", timestamp: 3),
        DownloadItem(youtubeId: "ignored-fixture", title: "Ignored Fixture Video", channelName: "Fixture Channel", channelId: "fixture-channel", duration: "02:10", published: "Oct 5", status: "ignore", message: nil, thumbUrl: "preview://video/ignored-fixture", vidType: "videos", timestamp: 4)
    ]

    private var channel = Channel(
        channelId: "channel-field-notes",
        channelName: "Field Notes",
        channelThumbUrl: "preview://channel/field-notes",
        channelBannerUrl: nil,
        channelDescription: "Short films about the places and details worth noticing.",
        channelSubscribed: true,
        channelSubs: 24_800
    )

    func getVideos(page: Int, sort: String, order: String, watch: String?, channel: String?, vidType: String?) async throws -> VideoListResult {
        let filtered = videos.filter { video in
            (channel == nil || video.channelId == channel) && (watch != "watched" || video.watched)
        }
        return VideoListResult(videos: filtered, currentPage: 1, lastPage: 1, totalHits: filtered.count)
    }

    func getVideo(id: String) async throws -> Video {
        videos.first(where: { $0.youtubeId == id }) ?? videos[0]
    }

    func updateProgress(videoId: String, position: Double) async throws {}
    func deleteProgress(videoId: String) async throws {}

    func deleteVideo(id: String) async throws {
        videos.removeAll { $0.youtubeId == id }
    }

    func ignoreVideo(id: String) async throws {}

    func getComments(videoId: String) async throws -> [Comment] {
        [
            Comment(id: "comment-1", author: "Mira", authorId: "user-mira", authorThumbnailUrl: "preview://user/mira", isUploader: false, text: "The light in this one is beautiful.", timeText: "2 days ago", likeCount: 18, isFavorited: false, parentId: "", replies: []),
            Comment(id: "comment-2", author: "Field Notes", authorId: "channel-field-notes", authorThumbnailUrl: "preview://channel/field-notes", isUploader: true, text: "Thank you for watching.", timeText: "1 day ago", likeCount: 6, isFavorited: false, parentId: "", replies: [])
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
    func ping() async throws -> Bool { false }
    func fetchUserAccount() async throws {}
    func logout() {}

    func getDownloads(page: Int, filter: String) async throws -> DownloadListResult {
        let filtered = filter == "all" ? downloads : downloads.filter { $0.status == filter }
        return DownloadListResult(items: filtered, currentPage: 1, lastPage: 1)
    }

    func updateStatus(videoId: String, status: String) async throws {
        downloads.removeAll { $0.youtubeId == videoId }
    }

    func deleteDownload(videoId: String) async throws {
        downloads.removeAll { $0.youtubeId == videoId }
    }

    func addToQueue(videoId: String) async throws {}
    func startDownload() async throws {}
    func getNotifications() async throws -> [TaskNotification] { [] }
    func killTask(id: String) async throws {}
    func rescanSubscriptions() async throws {}

    func getPlaylists(page: Int, type: String?) async throws -> PlaylistListResult {
        let filtered = playlists.filter { type == nil || $0.playlistType.rawValue == type }
        return PlaylistListResult(playlists: filtered, currentPage: 1, lastPage: 1)
    }

    func getPlaylist(id: String) async throws -> Playlist {
        playlists.first(where: { $0.playlistId == id }) ?? playlists[0]
    }

    func getPlaylistVideos(playlistId: String, page: Int) async throws -> VideoListResult {
        let ids = Set((playlists.first(where: { $0.playlistId == playlistId })?.playlistEntries ?? []).map(\.youtubeId))
        let result = videos.filter { ids.contains($0.youtubeId) }
        return VideoListResult(videos: result, currentPage: 1, lastPage: 1, totalHits: result.count)
    }

    func createCustomPlaylist(name: String) async throws -> Playlist {
        let newPlaylist = Playlist(playlistId: UUID().uuidString, playlistName: name, playlistChannel: "Personal playlist", playlistChannelId: "", playlistType: .custom, playlistSubscribed: false, playlistThumbnail: "preview://playlist/new", playlistDescription: nil, playlistEntries: [])
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
        SearchResult(videos: videos.filter { $0.title.localizedCaseInsensitiveContains(query) }, channels: [])
    }

    func getChannel(id: String) async throws -> Channel { channel }

    func setSubscribed(channelId: String, subscribed: Bool) async throws {
        channel.channelSubscribed = subscribed
    }

    private static func video(_ id: String, title: String, channel: String, duration: Int, progress: Double = 0) -> Video {
        let words = title.split(separator: " ")
        let channelId = "channel-" + channel.lowercased().replacingOccurrences(of: " ", with: "-")
        return Video(
            youtubeId: id,
            title: title,
            description: "A fictional sample video used only in the UI review preview.",
            published: "2026-10-08",
            publishedShort: "Oct 8",
            downloaded: "2026-10-09",
            downloadedShort: "Oct 9",
            channelName: channel,
            channelId: channelId,
            channelThumbUrl: "preview://channel/\(channelId)",
            thumbUrl: "preview://video/\(id)",
            mediaUrl: "preview://media/\(id)",
            duration: duration,
            durationStr: String(format: "%d:%02d", duration / 60, duration % 60),
            watched: false,
            progress: progress,
            position: Double(duration) * progress / 100,
            viewCount: 18_400,
            likeCount: 1_200,
            mediaSize: 842_000_000,
            vidType: "videos",
            category: ["Documentary"],
            tags: words.map(String.init),
            streams: [StreamInfo(type: "video", codec: "h264", bitrate: 5_400, width: 1920, height: 1080)],
            sponsorblock: [],
            playlists: []
        )
    }
}
