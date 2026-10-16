import Foundation

/// The preview target is never shipped. Its persistent test library has its own directory;
/// owner Keychain entries and production Downloads are never read or reset.
enum OfflinePreviewFixture {
    static var video: Video {
        let unauthorized = ProcessInfo.processInfo.arguments.contains("--review-offline-auth-fail")
        let argsRedirect = ProcessInfo.processInfo.arguments.contains("--review-offline-redirect")
        let slow = ProcessInfo.processInfo.arguments.contains("--review-offline-slow")
        let artworkRedirect = ProcessInfo.processInfo.arguments.contains("--review-offline-artwork-redirect")
        let path = unauthorized ? "unauthorized.mp4" : argsRedirect ? "redirect.mp4" : slow ? "slow.mp4" : "video.mp4"
        return Video(youtubeId: unauthorized ? "offline-auth-fixture" : "offline-fixture", title: "A Moment Offline",
                     description: "A generated local clip, saved privately for offline playback.", published: "October 8, 2026", publishedShort: "Oct 8", downloaded: "October 16, 2026", downloadedShort: "Oct 16",
                     channelName: "Fixture Studio", channelId: "fixture-studio", channelThumbUrl: "http://127.0.0.1:18081/channel.png",
                     thumbUrl: "http://127.0.0.1:18081/" + (artworkRedirect ? "redirect-artwork.png" : "thumbnail.png"), mediaUrl: "http://127.0.0.1:18081/" + path,
                     duration: 2, durationStr: "0:02", watched: false, progress: 0, position: 0,
                     viewCount: 1248, likeCount: 96, mediaSize: 0, vidType: "videos", category: [], tags: [],
                     streams: [StreamInfo(type: "video", codec: "h264", bitrate: 0, width: 320, height: 180)],
                     sponsorblock: [], playlists: [])
    }
    static func makeLibrary(authState: AuthState) -> OfflineLibrary {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--review-screen=offline") else {
            return OfflineLibrary(authState: authState, root: FileManager.default.temporaryDirectory.appendingPathComponent("OfflineReview-" + UUID().uuidString))
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineReviewFixture-v1")
        if args.contains("--review-offline-reset") { try? FileManager.default.removeItem(at: root) }
        if args.contains("--review-offline-transfer") {
            let cookie = HTTPCookie(properties: [.name: "sessionid", .value: "fixture", .domain: "127.0.0.1", .path: "/"])!
            try? authState.setSession(cookies: [cookie], serverURL: URL(string: "http://127.0.0.1:18081")!)
        }
        if args.contains("--review-offline-seed") {
            do {
                let store = try OfflineDiskStore(root: root)
                if try store.load().isEmpty, let source = (Bundle.main.url(forResource: "offline-demo", withExtension: "mp4") ?? Bundle.main.url(forResource: "offline-demo", withExtension: "mp4", subdirectory: "Fixtures")) {
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.copyItem(at: source, to: temporary)
                    var record = OfflineRecord(video: video, origin: "http://127.0.0.1:18081", mediaPath: "/video.mp4")
                    let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    let response = HTTPURLResponse(url: URL(string: video.mediaUrl)!, statusCode: 200, httpVersion: nil,
                                                   headerFields: ["Content-Type": "video/mp4", "Content-Length": String(size)])!
                    let (kind, bytes) = try store.commit(store.stage(temporary), record: record, response: response)
                    record.kind = kind; record.bytes = bytes; record.status = .ready
                    if args.contains("--review-offline-legacy") { record.metadata = nil }
                    for (kind, resource) in args.contains("--review-offline-legacy") ? [] : [(OfflineArtworkKind.thumbnail, "offline-thumbnail"), (.channel, "offline-channel")] {
                        if let image = Bundle.main.url(forResource: resource, withExtension: "png") ?? Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "Fixtures") {
                            try store.saveArtwork(Data(contentsOf: image), id: record.id, kind: kind)
                        }
                    }
                    try store.save([record])
                }
            } catch { /* The library surfaces storage errors; fixtures never fall back to an owner server. */ }
        }
        return OfflineLibrary(authState: authState, root: root)
    }
}
