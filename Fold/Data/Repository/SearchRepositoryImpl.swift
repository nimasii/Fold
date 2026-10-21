import Foundation

final class SearchRepositoryImpl: SearchRepositoryProtocol {
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

    func search(query: String, page: Int) async throws -> SearchResult {
        let context = try await history?.prepareRead()
        let response: SearchResponseDTO = try await apiClient.request(
            endpoint: .search(query: query, page: page)
        )

        let videos = try response.results?.videoResults?.compactMap { dto -> Video? in
            guard let video = VideoMapper.map(dto, serverURL: serverURL) else { return nil }
            return try history?.accept(video, context: context) ?? video
        } ?? []
        let channels = response.results?.channelResults?.compactMap { ChannelMapper.map($0, serverURL: serverURL) } ?? []

        return SearchResult(videos: videos, channels: channels)
    }
}
