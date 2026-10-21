import SwiftUI

struct ChannelDetailView: View {
    @Bindable var viewModel: ChannelDetailViewModel
    @Environment(AuthState.self) private var authState
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView()
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error) {
                    Task { await viewModel.loadChannel() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        channelHeader

                        if viewModel.videos.isEmpty {
                            ContentUnavailableView(
                                String(localized: "video_list_empty"),
                                systemImage: "rectangle.stack"
                            )
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            AdaptiveVideoGrid(
                                videos: viewModel.videos,
                                onVideoTap: { videoId in
                                    viewModel.navigateToVideo(videoId)
                                },
                                onToggleWatched: { videoId in
                                    Task { await viewModel.toggleWatched(videoId: videoId) }
                                },
                                onNearEnd: {
                                    Task { await viewModel.loadMoreVideos() }
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
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                }
                .geometryGroup()
            }
        }
        .background(StreamingStyle.background)
        .navigationTitle(viewModel.channel?.channelName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isSelecting {
                ToolbarItem(placement: .principal) {
                    Text(String(localized: "selection_count \(viewModel.selectedVideoIds.count)"))
                        .font(.headline)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.batchSetWatched(true) }
                    } label: {
                        Image(systemName: "eye")
                    }
                    .accessibilityLabel(String(localized: "video_mark_watched"))

                    Button {
                        Task { await viewModel.batchSetWatched(false) }
                    } label: {
                        Image(systemName: "eye.slash")
                    }
                    .accessibilityLabel(String(localized: "video_mark_unwatched"))

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
            }
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
        .task {
            await viewModel.loadChannel()
        }
        .onChange(of: viewModel.router.deletedVideoIds) {
            viewModel.removeDeletedVideos()
        }
        .onChange(of: viewModel.router.watchedChanges) {
            viewModel.applyWatchedChanges()
        }
    }

    @ViewBuilder
    private var channelHeader: some View {
        if let channel = viewModel.channel {
            VStack(alignment: .leading, spacing: 20) {
                if let bannerURL = channel.channelBannerUrl {
                    Color(.secondarySystemBackground).aspectRatio(16 / 7, contentMode: .fit)
                        .overlay { AuthenticatedAsyncImage(url: bannerURL) }.clipped()
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "stream_channel")).font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 14) {
                        AuthenticatedAsyncImage(url: channel.channelThumbUrl)
                            .frame(width: 64, height: 64).clipShape(.circle).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(channel.channelName).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                            Text(String(localized: "channel_detail_subscribers \(channel.channelSubs)"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if authState.isPrivileged {
                        Button { Task { await viewModel.toggleSubscription() } } label: {
                            Label(channel.channelSubscribed ? String(localized: "channel_unsubscribe") : String(localized: "channel_subscribe"),
                                  systemImage: channel.channelSubscribed ? "checkmark" : "plus")
                        }
                        .foldAction()
                        .accessibilityLabel(channel.channelSubscribed ? String(localized: "channel_unsubscribe") : String(localized: "channel_subscribe"))
                    }
                    if let description = channel.channelDescription, !description.isEmpty {
                        DisclosureGroup(String(localized: "stream_about_channel")) {
                            Text(description).font(.body).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.subheadline.weight(.medium))
                    }
                }.padding(.horizontal, StreamingStyle.gutter)
                MediaSectionHeading(title: String(localized: "video_list_title"))
            }
        }
    }
}
