import SwiftUI

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    var embeddedInLibrary = false

    @ViewBuilder var body: some View {
        if embeddedInLibrary {
            content
        } else {
            content.searchable(text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(String(localized: "search_archive_prompt")))
                .onSubmit(of: .search) { viewModel.submitSearch() }
                .onChange(of: viewModel.query) { viewModel.onQueryChanged() }
        }
    }
    private var content: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StreamingStyle.background)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onChange(of: viewModel.router.deletedVideoIds) { viewModel.removeDeletedVideos() }
        .navigationTitle(String(localized: embeddedInLibrary ? "stream_library" : "video_list_search"))
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
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                Text(String(localized: "stream_search_intro")).font(.largeTitle.bold())
                Text(String(localized: "stream_search_help")).font(.body).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StreamingStyle.gutter).padding(.top, 24)
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
