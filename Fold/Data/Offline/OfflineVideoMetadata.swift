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
    struct Sponsor: Codable, Hashable {
        let category: String
        let start: Double
        let end: Double
        var value: SponsorBlockSegment? {
            guard let category = SponsorCategory(rawValue: category), start.isFinite, end.isFinite, start >= 0, end > start else { return nil }
            return SponsorBlockSegment(category: category, startTime: start, endTime: end)
        }
    }
    let sponsorSegments: [Sponsor]?
    let playlistIDs: [String]?
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
        sponsorSegments = video.sponsorblock.map { Sponsor(category: $0.category.rawValue, start: $0.startTime, end: $0.endTime) }
        playlistIDs = video.playlists
        description = video.description; published = video.published; publishedShort = video.publishedShort
        downloaded = video.downloaded; downloadedShort = video.downloadedShort; durationString = video.durationStr
        channelID = video.channelId; views = video.viewCount; likes = video.likeCount; videoType = video.vidType
        streams = video.streams.map { Stream(type: $0.type, codec: $0.codec, bitrate: $0.bitrate, width: $0.width, height: $0.height) }
        thumbnailPath = Self.artworkPath(video.thumbUrl, origin: origin)
        channelArtworkPath = Self.artworkPath(video.channelThumbUrl, origin: origin)
    }
    private static func artworkPath(_ raw: String?, origin: String) -> String? {
        guard let resolved = ServerArtwork.resolve(raw, baseURL: origin), let url = URL(string: resolved), RequestAuthorization.origin(url) == origin,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              artworkURL(path: path, origin: origin) != nil else { return nil }
        return path
    }
    /// Revalidate persisted paths as well as fresh server responses. No URL,
    /// query, traversal segment or encoded separator may escape the saved origin.
    static func artworkURL(path: String, origin: String) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              !path.contains("\\"), !path.contains("?"), !path.contains("#") else { return nil }
        var decoded = path
        for _ in 0..<3 {
            guard !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !decoded.contains("\\"), !decoded.hasPrefix("//"),
                  !decoded.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) else { return nil }
            guard let next = decoded.removingPercentEncoding else { return nil }
            if next == decoded { break }
            // Encoded separators can change a path after the server decodes it.
            guard next.filter({ $0 == "/" }).count == decoded.filter({ $0 == "/" }).count else { return nil }
            decoded = next
        }
        guard !decoded.contains("%"), !decoded.contains("\\"),
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !decoded.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }),
              let url = URL(string: origin + path), RequestAuthorization.origin(url) == origin,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

}

extension OfflineRecord {
    /// Uses the local UUID as grid identity: equal YouTube IDs on different servers stay distinct.
    /// Empty remote artwork/media URLs prevent shared presentation from contacting a server.
    var displayVideo: Video { videoSnapshot(id: id.uuidString) }
    var libraryVideo: Video { videoSnapshot(id: videoID) }
    private func videoSnapshot(id displayID: String) -> Video {
        let durationString = metadata?.durationString ?? Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))
        return Video(youtubeId: displayID, title: title, description: metadata?.description,
                     published: metadata?.published ?? "", publishedShort: metadata?.publishedShort ?? "",
                     downloaded: metadata?.downloaded ?? "", downloadedShort: metadata?.downloadedShort ?? "",
                     channelName: channel, channelId: metadata?.channelID ?? "", channelThumbUrl: nil,
                     thumbUrl: "", mediaUrl: "", duration: duration, durationStr: durationString,
                     watched: false, progress: duration > 0 ? min(100, position / Double(duration) * 100) : 0,
                     position: position, viewCount: metadata?.views ?? 0, likeCount: metadata?.likes ?? 0,
                     mediaSize: bytes, vidType: metadata?.videoType ?? "videos", category: [], tags: [],
                     streams: (playbackStreams ?? metadata?.streams)?.map(\.value) ?? codecs.map { StreamInfo(type: "video", codec: $0, bitrate: 0, width: nil, height: nil) }, sponsorblock: metadata?.sponsorSegments?.compactMap(\.value) ?? [], playlists: metadata?.playlistIDs ?? [])
    }
}
