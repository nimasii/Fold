import Foundation

/// Optional presentation snapshot: older manifests decode without it. Authentication and
/// remote media URLs are never copied into the snapshot. Artwork paths must be unsigned.
nonisolated struct OfflineVideoMetadata: Codable, Hashable {
    struct Stream: Codable, Hashable {
        let type: String
        let codec: String
        let bitrate: Int
        let width: Int?
        let height: Int?
        var value: StreamInfo { StreamInfo(type: type, codec: codec, bitrate: bitrate, width: width, height: height) }
    }
    let description: String?
    let published: String
    let publishedShort: String
    let downloaded: String
    let downloadedShort: String
    let durationString: String
    let channelID: String
    let views: Int
    let likes: Int
    let videoType: String
    let streams: [Stream]
    let thumbnailPath: String?
    let channelArtworkPath: String?

    init(video: Video, origin: String) {
        description = video.description; published = video.published; publishedShort = video.publishedShort
        downloaded = video.downloaded; downloadedShort = video.downloadedShort; durationString = video.durationStr
        channelID = video.channelId; views = video.viewCount; likes = video.likeCount; videoType = video.vidType
        streams = video.streams.map { Stream(type: $0.type, codec: $0.codec, bitrate: $0.bitrate, width: $0.width, height: $0.height) }
        thumbnailPath = Self.artworkPath(video.thumbUrl, origin: origin)
        channelArtworkPath = Self.artworkPath(video.channelThumbUrl, origin: origin)
    }
    private static func artworkPath(_ raw: String?, origin: String) -> String? {
        guard let raw, let url = URL(string: raw), RequestAuthorization.origin(url) == origin,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
    }
}

extension OfflineRecord {
    /// Uses the local UUID as grid identity: equal YouTube IDs on different servers stay distinct.
    /// Empty remote artwork/media URLs prevent shared presentation from contacting a server.
    var displayVideo: Video {
        let durationString = metadata?.durationString ?? Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))
        return Video(youtubeId: id.uuidString, title: title, description: metadata?.description,
                     published: metadata?.published ?? "", publishedShort: metadata?.publishedShort ?? "",
                     downloaded: metadata?.downloaded ?? "", downloadedShort: metadata?.downloadedShort ?? "",
                     channelName: channel, channelId: metadata?.channelID ?? "", channelThumbUrl: nil,
                     thumbUrl: "", mediaUrl: "", duration: duration, durationStr: durationString,
                     watched: false, progress: duration > 0 ? min(100, position / Double(duration) * 100) : 0,
                     position: position, viewCount: metadata?.views ?? 0, likeCount: metadata?.likes ?? 0,
                     mediaSize: bytes, vidType: metadata?.videoType ?? "videos", category: [], tags: [],
                     streams: metadata?.streams.map(\.value) ?? codecs.map { StreamInfo(type: "video", codec: $0, bitrate: 0, width: nil, height: nil) }, sponsorblock: [], playlists: [])
    }
}
