import SwiftUI

struct PlaylistListView: View {
    @State var viewModel: PlaylistListViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var deleting: Playlist?

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.isLoading && viewModel.playlists.isEmpty {
                LoadingView()
            } else if let error = viewModel.errorMessage, viewModel.playlists.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.loadPlaylists() }
                }
            } else if viewModel.playlists.isEmpty {
                ContentUnavailableView(
                    String(localized: "playlist_list_empty"),
                    systemImage: "music.note.list"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : 160), spacing: 16)], alignment: .leading, spacing: 24) {
                        ForEach(viewModel.playlists) { playlist in
                            Button {
                                viewModel.navigateToPlaylist(playlist.playlistId)
                            } label: {
                                PlaylistRow(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleting = playlist
                                } label: {
                                    Label(String(localized: "playlist_delete"), systemImage: "trash")
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding()
                        }

                        Color.clear.frame(height: 1)
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded() }
                            }
                    }
                    .padding(StreamingStyle.gutter)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .background(StreamingStyle.background)
        .navigationTitle(String(localized: "playlist_list_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(PlaylistTypeFilter.allCases, id: \.self) { filter in
                        Button {
                            viewModel.typeFilter = filter
                            viewModel.onFilterChanged()
                        } label: {
                            if viewModel.typeFilter == filter {
                                Label(filter.label, systemImage: "checkmark")
                            } else {
                                Text(filter.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(String(localized: "playlist_filter_title"))

                Button {
                    viewModel.showCreateDialog = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "playlist_create"))
            }
        }
        .alert(String(localized: "playlist_create"), isPresented: $viewModel.showCreateDialog) {
            TextField(String(localized: "playlist_name_placeholder"), text: $viewModel.newPlaylistName)
            Button(String(localized: "cancel"), role: .cancel) {
                viewModel.newPlaylistName = ""
            }
            Button(String(localized: "playlist_create_confirm")) {
                Task { await viewModel.createCustomPlaylist() }
            }
        }
        .confirmationDialog(String(localized: "playlist_delete_title"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(String(localized: "playlist_delete_keep_videos"), role: .destructive) {
                if let playlist = deleting { Task { await viewModel.deletePlaylist(playlist.id, deleteVideos: false) } }
                deleting = nil
            }
            Button(String(localized: "cancel"), role: .cancel) { deleting = nil }
        }
        .task {
            if viewModel.playlists.isEmpty {
                await viewModel.loadPlaylists()
            }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color(.secondarySystemBackground).aspectRatio(16 / 11, contentMode: .fit)
                .overlay { AuthenticatedAsyncImage(url: playlist.playlistThumbnail) }.clipped()
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "rectangle.stack.fill").font(.body).foregroundStyle(.white)
                        .padding(10).background(.black.opacity(0.7), in: .circle).padding(10)
                }
                .clipShape(.rect(cornerRadius: StreamingStyle.corner)).accessibilityHidden(true)
            Text(playlist.playlistName).font(.headline).foregroundStyle(.primary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
            Text(String(localized: "playlist_entry_count \(playlist.playlistEntries.count)"))
                .font(.caption).foregroundStyle(.secondary)
            if !playlist.playlistChannel.isEmpty { Text(playlist.playlistChannel).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.playlistName), \(playlist.playlistChannel)")
    }
}
