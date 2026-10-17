import SwiftUI

struct VideoListView: View {
    @State var viewModel: VideoListViewModel
    @Environment(AuthState.self) private var authState
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showLogoutConfirmation = false
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
                        if !viewModel.isSelecting { quickFilters }
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
        .navigationTitle(showsDiscovery ? String(localized: "stream_watch") : selectedSectionTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.isSelecting {
                ToolbarItem(placement: .principal) {
                    Text(String(localized: "selection_count \(viewModel.selectedVideoIds.count)"))
                        .font(.headline)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.showMarkWatched {
                        Button {
                            Task { await viewModel.batchSetWatched(true) }
                        } label: {
                            Image(systemName: "eye")
                        }
                        .accessibilityLabel(String(localized: "video_mark_watched"))
                    }

                    if viewModel.showMarkUnwatched {
                        Button {
                            Task { await viewModel.batchSetWatched(false) }
                        } label: {
                            Image(systemName: "eye.slash")
                        }
                        .accessibilityLabel(String(localized: "video_mark_unwatched"))
                    }

                    if authState.isPrivileged {
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(String(localized: "selection_delete"))
                    }

                    Button {
                        viewModel.selectAll()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel(String(localized: "selection_select_all"))

                    Button(String(localized: "cancel")) {
                        viewModel.cancelSelection()
                    }
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(VidTypeFilter.allCases, id: \.self) { type in
                            Button {
                                viewModel.setVidType(type)
                            } label: {
                                if viewModel.vidTypeFilter == type {
                                    Label(type.label, systemImage: "checkmark")
                                } else {
                                    Text(type.label)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel(String(localized: "vid_type_section_title"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SortFilterMenu(
                        sortOption: $viewModel.sortOption,
                        sortAscending: $viewModel.sortAscending,
                        watchFilter: $viewModel.watchFilter
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.navigateToSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(String(localized: "search_hint"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.navigateToPlaylists()
                        } label: {
                            Label(String(localized: "playlist_list_title"), systemImage: "music.note.list")
                        }

                        Button { viewModel.router.navigate(to: .offlineDownloads) } label: {
                            Label(String(localized: "offline_title"), systemImage: "arrow.down.circle.fill")
                        }
                        .accessibilityLabel(String(localized: "offline_title"))
                        .accessibilityIdentifier("watch.private-downloads")

                        Button {
                            viewModel.navigateToDownloadQueue()
                        } label: {
                            Label(String(localized: "stream_server_queue"), systemImage: "server.rack")
                        }

                        Button {
                            viewModel.navigateToSettings()
                        } label: {
                            Label(String(localized: "settings_title"), systemImage: "gearshape")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showLogoutConfirmation = true
                        } label: {
                            Label(String(localized: "video_list_logout"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .overlay(alignment: .topTrailing) {
                                if viewModel.hasActiveDownloads {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 2, y: -2)
                                }
                            }
                    }
                    .accessibilityLabel(String(localized: "more_actions"))
                }
            }
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
            String(localized: "video_list_logout"),
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "video_list_logout"), role: .destructive) {
                viewModel.logout()
            }
            Button(String(localized: "cancel"), role: .cancel) {}
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

    private var showsDiscovery: Bool {
        !viewModel.isSelecting && viewModel.sortOption == .downloaded && !viewModel.sortAscending
            && viewModel.watchFilter == .unwatched && viewModel.vidTypeFilter == .all
    }
    private var continuing: [Video] {
        Array(viewModel.videos.filter { $0.progress > 0 && !$0.watched }.prefix(8))
    }
    @ViewBuilder private var quickFilters: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { filterButtons }
                .padding(.horizontal, StreamingStyle.gutter)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 10) { filterButtons }.padding(.horizontal, StreamingStyle.gutter)
            }.scrollIndicators(.hidden).accessibilityIdentifier("watch.filters")
        }
    }
    private var filterButtons: some View {
        ForEach([WatchFilter.unwatched, .continue, .all], id: \.self) { filter in
            Button { viewModel.watchFilter = filter } label: {
                Text(filter.label).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
                    .foregroundStyle(viewModel.watchFilter == filter ? Color(.systemBackground) : Color.primary)
                    .background(viewModel.watchFilter == filter ? Color.primary : Color(.secondarySystemBackground), in: .capsule)
            }
            .buttonStyle(.plain).accessibilityLabel(filter.label)
            .accessibilityAddTraits(viewModel.watchFilter == filter ? .isSelected : [])
        }
    }

    private var selectedSectionTitle: String {
        viewModel.vidTypeFilter == .all
            ? String(localized: "video_list_title")
            : viewModel.vidTypeFilter.label
    }
}
