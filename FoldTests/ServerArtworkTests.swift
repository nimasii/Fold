import Testing
@testable import Fold

struct ServerArtworkTests {
    @Test func cacheRelativeAndTrailingSlashResolveToServerOrigin() {
        #expect(ServerArtwork.resolve("videos/a/Abc123_xY-z.jpg", baseURL: "https://archive.example/") == "https://archive.example/cache/videos/a/Abc123_xY-z.jpg")
        #expect(ServerArtwork.resolve("cache/videos/a/Abc123_xY-z.jpg", baseURL: "https://archive.example/") == "https://archive.example/cache/videos/a/Abc123_xY-z.jpg")
        #expect(ServerArtwork.resolve("/media/thumb/video/Abc123_xY-z.jpg", baseURL: "https://archive.example/") == "https://archive.example/media/thumb/video/Abc123_xY-z.jpg")
    }
    @Test func missingQueueMetadataUsesBoundedServerRoutes() {
        let dto = DownloadItemDTO(youtubeId: "Abc123_xY-z", title: "Video", channelName: nil, channelId: nil,
            duration: nil, published: nil, status: nil, message: nil, vidThumbUrl: nil, vidType: nil, timestamp: nil)
        #expect(DownloadMapper.map(dto, serverURL: "https://archive.example/")?.thumbUrl == "https://archive.example/media/thumb/video/Abc123_xY-z.jpg")
        #expect(ServerArtwork.videoFallbacks("Abc123_xY-z", baseURL: "https://archive.example").last == "https://archive.example/cache/videos/a/Abc123_xY-z.jpg")
        #expect(ServerArtwork.videoFallbacks("../secret", baseURL: "https://archive.example").isEmpty)
    }
    @Test func rejectsForeignSignedAndTraversalArtwork() {
        for raw in ["https://i.ytimg.com/video.jpg", "//foreign.example/art.jpg", "/cache/../secret", "/cache/%2fsecret", "/art.jpg?token=secret", "https://user:pass@archive.example/art.jpg"] {
            #expect(ServerArtwork.resolve(raw, baseURL: "https://archive.example") == nil)
        }
    }
}
