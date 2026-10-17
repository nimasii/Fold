import SwiftUI

struct PlaylistDetailView: View {
    @Bindable var viewModel: PlaylistDetailViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView()
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error) {
                    Task { await viewModel.loadPlaylist() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        playlistHeader

                        AdaptiveVideoGrid(
                            videos: viewModel.videos,
                            onVideoTap: { videoId in
                                viewModel.navigateToVideo(videoId)
                            },
                            onChannelTap: { channelId in
                                viewModel.navigateToChannel(channelId)
                            },
                            onNearEnd: {
                                Task { await viewModel.loadMoreVideos() }
                            }
                        )

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
        .navigationTitle(viewModel.playlist?.playlistName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.playlist != nil {
                    Button {
                        viewModel.showDeleteDialog = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(String(localized: "playlist_delete"))
                }
            }
        }
        .confirmationDialog(
            String(localized: "playlist_delete_title"),
            isPresented: $viewModel.showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button(String(localized: "playlist_delete_keep_videos"), role: .destructive) {
                Task { await viewModel.deletePlaylist(deleteVideos: false) }
            }
            Button(String(localized: "playlist_delete_with_videos"), role: .destructive) {
                Task { await viewModel.deletePlaylist(deleteVideos: true) }
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "playlist_delete_message"))
        }
        .task {
            await viewModel.loadPlaylist()
        }
    }

    @ViewBuilder
    private var playlistHeader: some View {
        if let playlist = viewModel.playlist {
            VStack(alignment: .leading, spacing: 18) {
                Color(.secondarySystemBackground).aspectRatio(16 / 8, contentMode: .fit)
                    .overlay { AuthenticatedAsyncImage(url: playlist.playlistThumbnail) }.clipped()
                    .clipShape(.rect(cornerRadius: 20)).accessibilityHidden(true)
                Text(String(localized: "stream_collection")).font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                Text(playlist.playlistName).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(String(localized: "playlist_entry_count \(playlist.playlistEntries.count)"))
                    Text(playlist.playlistType == .custom ? String(localized: "playlist_type_custom") : String(localized: "playlist_type_regular"))
                }.font(.subheadline).foregroundStyle(.secondary)
                if !playlist.playlistChannel.isEmpty {
                    Button { viewModel.navigateToChannel(playlist.playlistChannelId) } label: {
                        Label(playlist.playlistChannel, systemImage: "person.crop.circle")
                    }.font(.headline).frame(minHeight: 44)
                        .disabled(playlist.playlistChannelId.isEmpty)
                        .accessibilityLabel(playlist.playlistChannel)
                }
                if let description = playlist.playlistDescription, !description.isEmpty {
                    Text(description).font(.subheadline).foregroundStyle(.secondary)
                }
                if playlist.playlistType == .regular {
                    Button { Task { await viewModel.toggleSubscription() } } label: {
                        Label(playlist.playlistSubscribed ? String(localized: "playlist_unsubscribe") : String(localized: "playlist_subscribe"),
                              systemImage: playlist.playlistSubscribed ? "checkmark" : "plus")
                    }.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
                        .accessibilityLabel(playlist.playlistSubscribed ? String(localized: "playlist_unsubscribe") : String(localized: "playlist_subscribe"))
                }
            }.padding(.horizontal, StreamingStyle.gutter).padding(.top, 12)
        }
    }
}
