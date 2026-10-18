import SwiftUI

/// Side-effect-free factory; search state lives for this transient Library context.
struct LibrarySearchScreen: View {
    @State private var viewModel: SearchViewModel
    @Environment(AppRouter.self) private var router
    init(make: () -> SearchViewModel) { _viewModel = State(wrappedValue: make()) }
    var body: some View {
        SearchView(viewModel: viewModel, embeddedInLibrary: true)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SectionMenu(hasFilters: false) { EmptyView() } } }
            .onChange(of: router.librarySearchQuery) { syncQuery() }
            .onAppear { syncQuery() }
            .onDisappear {
                if !router.isLibrarySearchActive { viewModel.query = ""; viewModel.onQueryChanged() }
            }
            .onSubmit(of: .search) { viewModel.submitSearch() }
    }
    private func syncQuery() {
        guard viewModel.query != router.librarySearchQuery else { return }
        viewModel.query = router.librarySearchQuery
        viewModel.onQueryChanged()
    }
}
