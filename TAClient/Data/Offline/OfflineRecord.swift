import Foundation

nonisolated enum OfflineStatus: String, Codable {
    case downloading, ready, canceled, interrupted, failed, needsSignIn
    var label: String { String(localized: String.LocalizationValue("offline_status_" + rawValue)) }
}

nonisolated enum OfflineFailure: String, Codable, Error {
    case network, storage, invalidMedia, missingFile, signIn, server
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
    var metadata: OfflineVideoMetadata?

    init(video: Video, origin: String, mediaPath: String) {
        id = UUID(); videoID = video.youtubeId; self.origin = origin; self.mediaPath = mediaPath
        title = video.title; channel = video.channelName; duration = video.duration
        codecs = video.streams.filter { $0.type.lowercased() == "video" }.map(\.codec)
        expectedSize = max(0, video.mediaSize); status = .downloading
        metadata = OfflineVideoMetadata(video: video, origin: origin)
    }
    var requiresVLC: Bool {
        kind == .webm || codecs.contains { ["vp9", "vp09", "vp8", "vp08"].contains($0.lowercased()) }
    }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
