import SwiftUI

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.videos.isEmpty {
                HStack {
                    Text(String(localized: "search_result_count \(viewModel.videos.count)"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView().opacity(viewModel.isLoading ? 1 : 0)
                        .accessibilityHidden(!viewModel.isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            results
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $viewModel.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(String(localized: "search_archive_prompt")))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { viewModel.submitSearch() }
        .onChange(of: viewModel.query) { viewModel.onQueryChanged() }
        .onChange(of: viewModel.router.deletedVideoIds) { viewModel.removeDeletedVideos() }
        .navigationTitle(String(localized: "video_list_search"))
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder private var results: some View {
        if let error = viewModel.errorMessage {
            ErrorView(message: error) { viewModel.submitSearch() }
        } else if viewModel.isLoading && viewModel.videos.isEmpty {
            LoadingView(message: String(localized: "search_loading"))
        } else if viewModel.hasSearched && viewModel.videos.isEmpty {
            ContentUnavailableView.search(text: viewModel.query)
        } else if viewModel.videos.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "search_archive_prompt"), systemImage: "magnifyingglass")
            } description: {
                Text(String(localized: "search_archive_description"))
            }
        } else {
            ScrollView {
                AdaptiveVideoGrid(
                    videos: viewModel.videos,
                    onVideoTap: { viewModel.navigateToVideo($0) },
                    onChannelTap: { viewModel.navigateToChannel($0) }
                )
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .geometryGroup()
        }
    }
}
