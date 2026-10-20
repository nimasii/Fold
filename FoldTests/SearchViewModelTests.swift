import SwiftUI
import Testing
@testable import Fold

struct SearchViewModelTests {

    private func makeSUT(
        searchRepo: MockSearchRepository = MockSearchRepository()
    ) -> (SearchViewModel, AppRouter) {
        let keychain = KeychainService()
        keychain.clearAll()
        let authState = AuthState(keychainService: keychain)
        let router = AppRouter(authState: authState)
        let vm = SearchViewModel(searchRepository: searchRepo, router: router)
        return (vm, router)
    }

    @Test func emptyQuery_clearsVideos() {
        let (vm, _) = makeSUT()
        vm.query = ""
        vm.onQueryChanged()

        #expect(vm.videos.isEmpty)
        #expect(vm.hasSearched == false)
    }

    @Test func validQuery_populatesVideos() async throws {
        let repo = MockSearchRepository()
        repo.searchHandler = { query, _ in
            SearchResult(
                videos: [TestData.video(youtubeId: "s1"), TestData.video(youtubeId: "s2")],
                channels: []
            )
        }
        let (vm, _) = makeSUT(searchRepo: repo)

        vm.query = "test search"
        vm.onQueryChanged()

        // Wait for debounce (300ms) + search execution
        try await Task.sleep(for: .milliseconds(500))

        #expect(vm.videos.count == 2)
        #expect(vm.hasSearched == true)
    }

    @Test func unauthorized_routerHandles() async throws {
        let repo = MockSearchRepository()
        repo.searchHandler = { _, _ in throw AppError.unauthorized }
        let (vm, router) = makeSUT(searchRepo: repo)

        vm.query = "test"
        vm.onQueryChanged()

        try await Task.sleep(for: .milliseconds(500))

        #expect(router.appState == .login)
    }

    @Test func isLoading_togglesDuringSearch() async throws {
        let repo = MockSearchRepository()
        repo.searchHandler = { _, _ in
            SearchResult(videos: [TestData.video()], channels: [])
        }
        let (vm, _) = makeSUT(searchRepo: repo)

        #expect(vm.isLoading == false)

        vm.query = "test"
        vm.onQueryChanged()

        try await Task.sleep(for: .milliseconds(500))

        #expect(vm.isLoading == false)
    }

    @Test func navigation_appendsRoutes() {
        let (vm, router) = makeSUT()

        vm.navigateToVideo("vid-1")
        #expect(router.path.count == 1)

        vm.navigateToChannel("ch-1")
        #expect(router.path.count == 2)
    }
    @Test func clearingDuringRequestStopsLoadingAndDiscardsLateResults() async throws {
        let repo = MockSearchRepository()
        repo.searchHandler = { _, _ in
            // Model a transport that returns even after cancellation.
            try? await Task.sleep(for: .milliseconds(150))
            return SearchResult(videos: [TestData.video()], channels: [])
        }
        let (vm, _) = makeSUT(searchRepo: repo)
        vm.query = "first"
        vm.submitSearch()
        try await Task.sleep(for: .milliseconds(30))
        #expect(vm.isLoading)
        vm.query = ""
        vm.onQueryChanged()
        #expect(!vm.isLoading)
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.videos.isEmpty)
        #expect(!vm.hasSearched)
    }

    @Test func oldFailureCannotSignOutNewQuery() async throws {
        let repo = MockSearchRepository()
        repo.searchHandler = { query, _ in
            if query == "old" {
                try? await Task.sleep(for: .milliseconds(150))
                throw AppError.unauthorized
            }
            return SearchResult(videos: [TestData.video(youtubeId: "new")], channels: [])
        }
        let (vm, router) = makeSUT(searchRepo: repo)
        router.onLoginSuccess()
        vm.query = "old"
        vm.submitSearch()
        try await Task.sleep(for: .milliseconds(30))
        vm.query = "new"
        vm.submitSearch()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.videos.map(\.youtubeId) == ["new"])
        #expect(router.appState == .authenticated)
        #expect(vm.errorMessage == nil)
    }

    @Test func retryClearsPriorErrorAndLoadsResults() async throws {
        let repo = MockSearchRepository()
        repo.searchHandler = { _, _ in throw AppError.network(underlying: nil) }
        let (vm, _) = makeSUT(searchRepo: repo)
        vm.query = "archive"
        vm.submitSearch()
        try await Task.sleep(for: .milliseconds(30))
        #expect(vm.errorMessage != nil)
        repo.searchHandler = { _, _ in SearchResult(videos: [TestData.video()], channels: []) }
        vm.submitSearch()
        #expect(vm.errorMessage == nil)
        try await Task.sleep(for: .milliseconds(30))
        #expect(vm.videos.count == 1)
        #expect(!vm.isLoading)
    }

}
