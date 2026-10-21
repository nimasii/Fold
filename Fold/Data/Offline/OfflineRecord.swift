import Foundation

nonisolated enum OfflineStatus: String, Codable {
    case downloading, preparing, ready, canceled, interrupted, failed, needsSignIn
    var isActive: Bool { self == .downloading || self == .preparing }
    var label: String { String(localized: String.LocalizationValue("offline_status_" + rawValue)) }
}

nonisolated enum OfflineFailure: String, Codable, Error {
    case network, storage, invalidMedia, missingFile, signIn, server, conversion, unsupportedConversion
    var message: String { String(localized: String.LocalizationValue("offline_error_" + rawValue)) }
}

nonisolated enum OfflineMediaKind: String, Codable { case mp4, webm }

/// No password, token, cookie, resume-data blob or signed URL is stored here.
nonisolated struct OfflineRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let videoID: String
    let origin: String
    let mediaPath: String
    let title: String
    let channel: String
    let duration: Int
    let codecs: [String]
    let expectedSize: Int64
    var status: OfflineStatus
    var bytes: Int64 = 0
    var totalBytes: Int64 = 0
    var kind: OfflineMediaKind?
    var failure: OfflineFailure?
    var attempt: UUID?
    var position: Double = 0
    /// Nil in older manifests: their private bookmark has no provable account owner.
    var account: PlaybackAccount?
    var legacyPosition: Double?
    var metadata: OfflineVideoMetadata?
    /// Actual private-copy streams. Optional for safe decoding of old manifests;
    /// refreshing server metadata must never overwrite converted playback codecs.
    var nativePlaybackVerified: Bool?
    var playbackStreams: [OfflineVideoMetadata.Stream]?

    init(video: Video, origin: String, mediaPath: String) {
        id = UUID(); videoID = video.youtubeId; self.origin = origin; self.mediaPath = mediaPath
        title = video.title; channel = video.channelName; duration = video.duration
        codecs = video.streams.filter { $0.type.lowercased() == "video" }.map(\.codec)
        expectedSize = max(0, video.mediaSize); status = .downloading
        metadata = OfflineVideoMetadata(video: video, origin: origin)
    }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
