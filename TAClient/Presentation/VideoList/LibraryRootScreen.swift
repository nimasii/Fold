import SwiftUI

/// Both initializers are side-effect-free. State owns each VM once per Library root,
/// preserving filters across search mode and all normal tab/back navigation.
struct LibraryRootScreen: View {
    @State private var videos: VideoListViewModel
    @State private var search: SearchViewModel
    @Environment(AppRouter.self) private var router
    init(makeVideos: () -> VideoListViewModel, makeSearch: () -> SearchViewModel) {
        _videos = State(wrappedValue: makeVideos())
        _search = State(wrappedValue: makeSearch())
    }
    var body: some View {
        Group {
            if router.isLibrarySearchActive {
                SearchView(viewModel: search, embeddedInLibrary: true)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if router.path.isEmpty { LibrarySearchEditor() }
                    }
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { SectionMenu(hasFilters: false) { EmptyView() } } }
            } else { VideoListView(viewModel: videos) }
        }
        .onChange(of: router.path.count) { _, count in if count > 0 { router.librarySearchWantsFocus = false } }
        .onChange(of: router.selectedTab) { _, tab in if tab != .library { router.librarySearchWantsFocus = false } }
        .onChange(of: router.librarySearchQuery) { syncQuery() }
        .onChange(of: router.isLibrarySearchActive) { syncQuery() }
        .onAppear { syncQuery() }
    }
    private func syncQuery() {
        guard search.query != router.librarySearchQuery else { return }
        search.query = router.librarySearchQuery
        search.onQueryChanged()
    }
}
