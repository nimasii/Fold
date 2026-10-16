import Foundation

/// A private local input to the normal video player, never an authenticated network URL.
struct LocalVideoPlayback {
    let record: OfflineRecord
    let mediaURL: URL?
    let artworkURL: URL?
    let artwork: LocalVideoArtwork
    let library: OfflineLibrary

    init(record: OfflineRecord, library: OfflineLibrary) {
        self.record = record
        self.library = library
        mediaURL = library.localURL(for: record)
        artworkURL = library.thumbnailURL(record.id)
        artwork = LocalVideoArtwork(thumbnail: artworkURL, channel: library.channelArtworkURL(record.id), revision: library.artworkRevision)
    }
}

/// Capability-limited repository for the normal detail/controller path. Local playback
/// cannot issue server requests or synchronize private viewing progress to the server.
final class LocalVideoRepository: VideoRepositoryProtocol {
    private let source: LocalVideoPlayback
    init(source: LocalVideoPlayback) { self.source = source }
    func getVideo(id: String) async throws -> Video {
        (source.library.records.first { $0.id == source.record.id } ?? source.record).displayVideo
    }
    func updateProgress(videoId: String, position: Double) async throws {
        source.library.savePosition(source.record.id, seconds: position)
    }
    func getComments(videoId: String) async throws -> [Comment] { [] }
    func getSimilarVideos(videoId: String) async throws -> [Video] { [] }
    func getVideos(page: Int, sort: String, order: String, watch: String?, channel: String?, vidType: String?) async throws -> VideoListResult { throw OfflineFailure.missingFile }
    func deleteProgress(videoId: String) async throws { throw OfflineFailure.missingFile }
    func deleteVideo(id: String) async throws { throw OfflineFailure.missingFile }
    func ignoreVideo(id: String) async throws { throw OfflineFailure.missingFile }
    func setWatched(videoId: String, isWatched: Bool) async throws { throw OfflineFailure.missingFile }
}
