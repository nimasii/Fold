import SwiftUI

struct OfflineDownloadsView: View {
    var videoRepository: VideoRepositoryProtocol? = nil
    @Environment(OfflineLibrary.self) private var library
    @Environment(AuthState.self) private var authState
    @State private var playing: OfflineRecord?
    @State private var removing: OfflineRecord?
    @State private var showInfo = false

    private var completed: [OfflineRecord] { library.records.filter { $0.status == .ready } }
    private var transfers: [OfflineRecord] { library.records.filter { $0.status != .ready } }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error = library.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                if library.records.isEmpty {
                    ContentUnavailableView(String(localized: "offline_empty"), systemImage: "arrow.down.circle",
                        description: Text(String(localized: "offline_empty_help")))
                }
                if !completed.isEmpty {
                    AdaptiveVideoGrid(
                        videos: completed.map(\.displayVideo),
                        onVideoTap: { id in playing = completed.first { $0.id.uuidString == id } },
                        localArtwork: Dictionary(uniqueKeysWithValues: completed.map { ($0.id.uuidString, artwork($0)) }),
                        supplementaryText: Dictionary(uniqueKeysWithValues: completed.map {
                            ($0.id.uuidString, library.refreshingDetails.contains($0.id) ? String(localized: "offline_refreshing_details") : $0.formattedSize)
                        }),
                        onRemoveLocalCopy: { id in removing = completed.first { $0.id.uuidString == id } },
                        onRefreshLocalDetails: videoRepository != nil && authState.isAuthenticated ? { id in
                            guard let record = completed.first(where: { $0.id.uuidString == id }), let videoRepository else { return }
                            Task { await library.refreshDetails(record.id, using: videoRepository) }
                        } : nil,
                        refreshableLocalIDs: Set(completed.filter { library.canRefreshDetails($0) }.map { $0.id.uuidString })
                    )
                }
                ForEach(transfers) { record in
                    transferRow(record).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .geometryGroup()
        .navigationTitle(String(localized: "offline_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel(String(localized: "offline_info"))
            }
        }
        .navigationDestination(item: $playing) { record in OfflinePlayerView(record: record) }
        .confirmationDialog(String(localized: "offline_remove_title"), isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(String(localized: "offline_remove"), role: .destructive) {
                if let record = removing { library.remove(record.id) }; removing = nil
            }
            Button(String(localized: "cancel"), role: .cancel) { removing = nil }
        } message: { Text(String(localized: "offline_remove_help")) }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                Form {
                    Section {
                        Label(String(localized: "offline_on_device"), systemImage: "iphone")
                        LabeledContent(String(localized: "offline_storage_used"), value: library.totalSize)
                        Text(String(localized: "offline_private_help"))
                    }
                    Section {
                        Text(String(localized: "offline_transfer_help"))
                        Text(String(localized: "offline_sign_in_help"))
                        Text(String(localized: "offline_legacy_artwork_help"))
                    }
                }
                .navigationTitle(String(localized: "offline_info"))
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "connection_done")) { showInfo = false }
                        .accessibilityLabel(String(localized: "connection_done"))
                } }
            }
        }
    }

    private func artwork(_ record: OfflineRecord) -> LocalVideoArtwork {
        LocalVideoArtwork(thumbnail: library.thumbnailURL(record.id), channel: library.channelArtworkURL(record.id), revision: library.artworkRevision)
    }

    private func transferRow(_ record: OfflineRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.title).font(.headline)
            Text(record.status.label).font(.subheadline).foregroundStyle(.secondary)
            if record.status == .downloading {
                ProgressView(value: record.totalBytes > 0 ? min(1, Double(record.bytes) / Double(record.totalBytes)) : nil)
                    .accessibilityLabel(String(localized: "offline_progress"))
                Button(String(localized: "offline_cancel"), systemImage: "stop.circle") { library.cancel(record.id) }
                    .accessibilityLabel(String(localized: "offline_cancel"))
            } else {
                if let failure = record.failure { Text(failure.message).font(.footnote).foregroundStyle(.secondary) }
                Button(String(localized: "retry"), systemImage: "arrow.clockwise") { library.retry(record.id) }
                    .accessibilityLabel(String(localized: "retry"))
            }
            Text(String(localized: "offline_transfer_help")).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(String(localized: "offline_remove"), systemImage: "trash", role: .destructive) { removing = record }
                .accessibilityLabel(String(localized: "offline_remove"))
        }
    }
}

struct OfflinePlayerView: View {
    let record: OfflineRecord
    @Environment(OfflineLibrary.self) private var library
    @State private var playback = OfflinePlayback()
    @State private var isFullScreen = false
    @State private var isPiPActive = false
    @State private var isPinned = false
    @State private var isViewVisible = true
    private var video: Video { record.displayVideo }

    var body: some View {
        VideoDetailLayout(isPinned: isPinned) {
            VideoPlayerSurface(
                video: video, player: playback.player, vlcURL: playback.vlcURL,
                isFullScreen: $isFullScreen, isPiPActive: $isPiPActive,
                isBuffering: playback.isLoading, localArtworkURL: library.thumbnailURL(record.id),
                startPosition: record.position >= Double(record.duration) ? 0 : record.position,
                playbackError: playback.error, seekInterval: playback.seekInterval,
                seekFeedback: playback.seekFeedback, vlcSeekDelta: playback.vlcSeekDelta,
                onTimeChanged: { playback.vlcPosition($0) }, onClearVLCSeekDelta: { playback.clearVLCSeekDelta() },
                onDoubleTap: playback.doubleTapToSeek ? { playback.seekByInterval(forward: $0) } : nil,
                onPiPStopped: { if !isViewVisible && !isFullScreen { playback.stop() } },
                onPlay: startPlayback, onRetry: startPlayback, overlay: EmptyView()
            )
        } details: {
            VStack(spacing: 16) {
                VideoInfoSection(video: video,
                    localArtwork: LocalVideoArtwork(thumbnail: library.thumbnailURL(record.id), channel: library.channelArtworkURL(record.id), revision: library.artworkRevision),
                    showsStatistics: record.metadata != nil)
                Label(String(localized: "offline_playing_local"), systemImage: "internaldrive")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                if let description = video.description, !description.isEmpty {
                    Text(description).font(.body).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .geometryGroup()
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPinned.toggle() } label: { Image(systemName: isPinned ? "pin.fill" : "pin") }
                    .accessibilityLabel(String(localized: "video_detail_pin_player"))
            }
        }
        .task { await playback.load(record, library: library) }
        .onAppear { isViewVisible = true }
        .onDisappear {
            isViewVisible = false
            if !isFullScreen && !isPiPActive { playback.stop() }
        }
    }
    private func startPlayback() { Task { await playback.load(record, library: library) } }
}
