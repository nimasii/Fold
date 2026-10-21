import Foundation

final class VideoRepositoryImpl: VideoRepositoryProtocol {
    private let apiClient: APIClient
    private let authState: AuthState
    private let history: PlaybackCoordinator?

    init(apiClient: APIClient, authState: AuthState, history: PlaybackCoordinator? = nil) {
        self.apiClient = apiClient
        self.authState = authState
        self.history = history
    }

    private var serverURL: String {
        authState.serverURL ?? ""
    }

    func getVideos(page: Int, sort: String, order: String, watch: String?, channel: String?, vidType: String?) async throws -> VideoListResult {
        let context = try await history?.prepareRead()
        let response: VideoListResponseDTO
        do {
            response = try await apiClient.request(endpoint: .videoList(page: page, sort: sort, order: order, watch: watch, channel: channel, vidType: vidType))
        } catch {
            let transient: Bool
            if let error = error as? AppError {
                switch error {
                case .network: transient = true
                case .serverError(let code, _): transient = code >= 500
                default: transient = false
                }
            } else { transient = false }
            if transient, !Task.isCancelled, let context, let history {
                let videos = history.offlineVideos(context: context, watch: watch, channel: channel, vidType: vidType)
                if !videos.isEmpty { return VideoListResult(videos: page == 1 ? videos : [], currentPage: 1, lastPage: 1, totalHits: videos.count) }
            }
            throw error
        }

        let videos = try response.data?.compactMap { dto -> Video? in
            guard let video = VideoMapper.map(dto, serverURL: serverURL) else { return nil }
            return try history?.accept(video, context: context) ?? video
        } ?? []
        return VideoListResult(
            videos: videos,
            currentPage: response.paginate?.currentPage ?? page,
            lastPage: response.paginate?.lastPage ?? page,
            totalHits: response.paginate?.totalHits ?? videos.count
        )
    }

    func getVideo(id: String) async throws -> Video {
        let context = try await history?.prepareRead()
        let dto: VideoDTO = try await apiClient.request(endpoint: .videoDetail(id: id))
        guard let video = VideoMapper.map(dto, serverURL: serverURL) else {
            throw AppError.decoding(underlying: nil)
        }
        return try history?.accept(video, context: context) ?? video
    }

    func updateProgress(videoId: String, position: Double) async throws {
        try await apiClient.requestVoid(
            endpoint: .videoProgress(id: videoId),
            body: VideoProgressDTO(position: position)
        )
    }

    func deleteProgress(videoId: String) async throws {
        try await apiClient.requestVoid(endpoint: .deleteVideoProgress(id: videoId))
    }

    func deleteVideo(id: String) async throws {
        try await apiClient.requestVoid(endpoint: .deleteVideo(id: id))
    }

    func ignoreVideo(id: String) async throws {
        try await apiClient.requestVoid(
            endpoint: .ignoreVideo(id: id),
            body: IgnoreVideoDTO(status: "ignore-force")
        )
    }

    func getComments(videoId: String) async throws -> [Comment] {
        let dtos: [CommentDTO] = try await apiClient.request(endpoint: .videoComments(id: videoId))
        return dtos.compactMap { CommentMapper.map($0, serverURL: serverURL) }
    }

    func setWatched(videoId: String, isWatched: Bool) async throws {
        if let history, authState.playbackAccount != nil {
            try history.setWatched(isWatched, videoID: videoId)
            return
        }
        try await apiClient.requestVoid(
            endpoint: .setWatched,
            body: WatchedDTO(id: videoId, isWatched: isWatched)
        )
    }

    func getSimilarVideos(videoId: String) async throws -> [Video] {
        let context = try await history?.prepareRead()
        let dtos: [VideoDTO] = try await apiClient.request(endpoint: .similarVideos(id: videoId))
        return try dtos.compactMap { dto -> Video? in
            guard let video = VideoMapper.map(dto, serverURL: serverURL) else { return nil }
            return try history?.accept(video, context: context) ?? video
        }
    }
}
