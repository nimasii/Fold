import SwiftUI

struct VideoListView: View {
    @State var viewModel: VideoListViewModel
    @Environment(AuthState.self) private var authState
    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                LoadingView()
            } else if let error = viewModel.errorMessage, viewModel.videos.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.refresh() }
                }
            } else if viewModel.videos.isEmpty {
                ContentUnavailableView(
                    String(localized: "video_list_empty"),
                    systemImage: "rectangle.stack"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if !viewModel.isSelecting {
                            playlistsEntry
                        }
                        if showsDiscovery, let featured = viewModel.videos.first {
                            FeaturedVideo(video: featured) { viewModel.navigateToVideo(featured.id) }
                            if !continuing.isEmpty {
                                VideoShelf(title: String(localized: "stream_continue"), videos: continuing,
                                    onOpen: viewModel.navigateToVideo, onChannel: viewModel.navigateToChannel)
                            }
                            VideoShelf(title: String(localized: "stream_recent"), videos: Array(viewModel.videos.prefix(8)),
                                onOpen: viewModel.navigateToVideo, onChannel: viewModel.navigateToChannel)
                        }
                        MediaSectionHeading(title: String(localized: "stream_browse"),
                            subtitle: viewModel.watchFilter.label + " · " + viewModel.sortOption.label)
                        AdaptiveVideoGrid(
                            videos: viewModel.videos,
                            onVideoTap: { videoId in
                                viewModel.navigateToVideo(videoId)
                            },
                            onChannelTap: { channelId in
                                viewModel.navigateToChannel(channelId)
                            },
                            onToggleWatched: { videoId in
                                Task { await viewModel.toggleWatched(videoId: videoId) }
                            },
                            onNearEnd: {
                                Task { await viewModel.loadMoreIfNeeded() }
                            },
                            isSelecting: viewModel.isSelecting,
                            selectedIds: viewModel.selectedVideoIds,
                            onEnterSelection: { videoId in
                                viewModel.enterSelectionMode(videoId: videoId)
                            },
                            onToggleSelection: { videoId in
                                viewModel.toggleSelection(videoId: videoId)
                            }
                        )
                        .id(viewModel.refreshCount)

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding()
                        }
                    }
                    .padding(.vertical)
                }
                .geometryGroup()
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .background(StreamingStyle.background)
        .navigationTitle(String(localized: "stream_library"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SectionMenu(hasFilters: !viewModel.isSelecting) {
                    LibraryFilterActions(viewModel: viewModel)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.isSelecting { selectionActions }
            else if viewModel.videos.isEmpty { playlistsEntry.padding(.vertical, 8) }
        }
        .task {
            if viewModel.videos.isEmpty {
                await viewModel.loadVideos()
            }
            await viewModel.checkActiveDownloads()
        }
        .onChange(of: viewModel.sortOption) {
            Task { await viewModel.onSortOrFilterChanged() }
        }
        .onChange(of: viewModel.sortAscending) {
            Task { await viewModel.onSortOrFilterChanged() }
        }
        .onChange(of: viewModel.watchFilter) {
            Task { await viewModel.onSortOrFilterChanged() }
        }
        .onChange(of: viewModel.router.deletedVideoIds) {
            viewModel.removeDeletedVideos()
        }
        .onChange(of: viewModel.router.watchedChanges) {
            viewModel.applyWatchedChanges()
        }
        .confirmationDialog(
            String(localized: "selection_delete_confirm \(viewModel.selectedVideoIds.count)"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "video_detail_delete"), role: .destructive) {
                Task { await viewModel.batchDelete() }
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        }
    }

    private var playlistsEntry: some View {
        Button { viewModel.navigateToPlaylists() } label: {
            Label(String(localized: "playlist_list_title"), systemImage: "rectangle.stack")
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule)
        .accessibilityLabel(String(localized: "playlist_list_title"))
        .accessibilityIdentifier("library.playlists")
        .padding(.horizontal, StreamingStyle.gutter)
    }

    private var selectionActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "selection_count \(viewModel.selectedVideoIds.count)"))
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if viewModel.showMarkWatched {
                        Button { Task { await viewModel.batchSetWatched(true) } } label: { Image(systemName: "eye") }
                            .accessibilityLabel(String(localized: "video_mark_watched"))
                    }
                    if viewModel.showMarkUnwatched {
                        Button { Task { await viewModel.batchSetWatched(false) } } label: { Image(systemName: "eye.slash") }
                            .accessibilityLabel(String(localized: "video_mark_unwatched"))
                    }
                    if authState.isPrivileged {
                        Button { showDeleteConfirmation = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel(String(localized: "selection_delete"))
                    }
                    Button { viewModel.selectAll() } label: { Image(systemName: "checkmark.circle") }
                        .accessibilityLabel(String(localized: "selection_select_all"))
                    Button(String(localized: "cancel")) { viewModel.cancelSelection() }
                        .accessibilityLabel(String(localized: "cancel"))
                }.buttonStyle(.bordered).controlSize(.large)
            }.scrollIndicators(.hidden)
        }.padding(.horizontal).padding(.vertical, 8).background(StreamingStyle.background)
    }

    private var showsDiscovery: Bool {
        !viewModel.isSelecting && viewModel.sortOption == .downloaded && !viewModel.sortAscending
            && viewModel.watchFilter == .unwatched && viewModel.vidTypeFilter == .all
    }
    private var continuing: [Video] {
        Array(viewModel.videos.filter { $0.progress > 0 && !$0.watched }.prefix(8))
    }

}
