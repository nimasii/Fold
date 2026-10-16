import Foundation

@Observable
final class SearchViewModel {
    var query: String = ""
    var videos: [Video] = []
    var isLoading = false
    var hasSearched = false
    var errorMessage: String?

    let router: AppRouter
    private var queryGeneration = 0
    private var searchTask: Task<Void, Never>?
    private let searchRepository: SearchRepositoryProtocol

    init(searchRepository: SearchRepositoryProtocol, router: AppRouter) {
        self.searchRepository = searchRepository
        self.router = router
    }

    func onQueryChanged() { scheduleSearch(debounce: true) }

    func submitSearch() { scheduleSearch(debounce: false) }

    private func scheduleSearch(debounce: Bool) {
        queryGeneration += 1
        let generation = queryGeneration
        searchTask?.cancel()
        errorMessage = nil
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            videos = []
            hasSearched = false
            isLoading = false
            return
        }
        searchTask = Task {
            if debounce {
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
            }
            await performSearch(query: trimmedQuery, generation: generation)
        }
    }

    private func performSearch(query: String, generation: Int) async {
        guard generation == queryGeneration, !Task.isCancelled else { return }
        isLoading = true
        defer { if generation == queryGeneration { isLoading = false } }
        do {
            let result = try await searchRepository.search(query: query, page: 1)
            guard generation == queryGeneration, !Task.isCancelled else { return }
            videos = result.videos
            hasSearched = true
        } catch {
            guard generation == queryGeneration, !Task.isCancelled else { return }
            router.handleError(error, errorMessage: &errorMessage)
        }
    }

    func removeDeletedVideos() {
        guard !router.deletedVideoIds.isEmpty else { return }
        videos.removeAll { router.deletedVideoIds.contains($0.youtubeId) }
    }

    func navigateToVideo(_ videoId: String) {
        router.navigate(to: .videoDetail(videoId: videoId))
    }

    func navigateToChannel(_ channelId: String) {
        router.navigate(to: .channelDetail(channelId: channelId))
    }
}
