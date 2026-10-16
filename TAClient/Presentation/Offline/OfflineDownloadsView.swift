import SwiftUI

struct OfflineDownloadsView: View {
    @Environment(OfflineLibrary.self) private var library
    @Environment(AuthState.self) private var authState
    @State private var playing: OfflineRecord?
    @State private var removing: OfflineRecord?

    var body: some View {
        List {
            Section {
                Label(String(localized: "offline_on_device"), systemImage: "iphone")
                    .font(.headline)
                Text(String(localized: "offline_private_help"))
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent(String(localized: "offline_storage_used"), value: library.totalSize)
                    .font(.subheadline)
            }
            if let error = library.storageError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if library.records.isEmpty {
                ContentUnavailableView(String(localized: "offline_empty"), systemImage: "arrow.down.circle",
                                       description: Text(String(localized: "offline_empty_help")))
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(library.records) { record in
                        VStack(alignment: .leading, spacing: 12) {
                            if record.status == .ready {
                                Button { playing = record } label: {
                                    rowTitle(record, ready: true).contentShape(Rectangle())
                                }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(record.title)
                                    .accessibilityHint(String(localized: "offline_play"))
                            } else { rowTitle(record, ready: false) }
                            if record.status == .downloading {
                                ProgressView(value: record.totalBytes > 0 ? min(1, Double(record.bytes) / Double(record.totalBytes)) : nil)
                                    .accessibilityLabel(String(localized: "offline_progress"))
                                HStack {
                                    Text(record.formattedSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(String(localized: "offline_cancel"), systemImage: "stop.circle") { library.cancel(record.id) }
                                        .accessibilityLabel(String(localized: "offline_cancel"))
                                }
                            } else if record.status != .ready {
                                if let failure = record.failure { Text(failure.message).font(.footnote).foregroundStyle(.secondary) }
                                Button(String(localized: "retry"), systemImage: "arrow.clockwise") { library.retry(record.id) }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel(String(localized: "retry"))
                            }
                        }
                        .padding(.vertical, 8)
                        .swipeActions {
                            Button(role: .destructive) { removing = record } label: {
                                Label(String(localized: "offline_remove"), systemImage: "trash")
                            }
                            .accessibilityLabel(String(localized: "offline_remove"))
                        }
                        .contextMenu {
                            Button(role: .destructive) { removing = record } label: {
                                Label(String(localized: "offline_remove"), systemImage: "trash")
                            }
                            .accessibilityLabel(String(localized: "offline_remove"))
                        }
                    }
                } header: { Text(String(localized: "offline_title")) }
            }
            Section {
                Text(String(localized: "offline_transfer_help")).font(.footnote).foregroundStyle(.secondary)
                if !authState.isAuthenticated {
                    Text(String(localized: "offline_sign_in_help")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "offline_title"))
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(String(localized: "offline_remove_title"), isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button(String(localized: "offline_remove"), role: .destructive) {
                    if let record = removing { library.remove(record.id) }; removing = nil
                }
                Button(String(localized: "cancel"), role: .cancel) { removing = nil }
            } message: { Text(String(localized: "offline_remove_help")) }
        .sheet(item: $playing) { record in
            NavigationStack {
                OfflinePlayerView(record: record)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "connection_done")) { playing = nil }
                                .accessibilityLabel(String(localized: "connection_done"))
                        }
                    }
            }
        }
    }

    private func rowTitle(_ record: OfflineRecord, ready: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: ready ? "play.rectangle.fill" : "arrow.down.circle")
                .font(.title2).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.title).font(.headline).foregroundStyle(.primary)
                Text(record.channel).font(.subheadline).foregroundStyle(.secondary)
                Text(ready ? record.formattedSize : record.status.label)
                    .font(.caption).foregroundStyle(.secondary)
                Text(record.origin).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if ready { Image(systemName: "play.fill").foregroundStyle(.tint).accessibilityHidden(true) }
        }
    }
}

struct OfflinePlayerView: View {
    let record: OfflineRecord
    @Environment(OfflineLibrary.self) private var library
    @State private var playback = OfflinePlayback()
    @State private var isFullScreen = false
    @State private var isPiPActive = false

    var body: some View {
        VStack(spacing: 20) {
            if let error = playback.error {
                ErrorView(message: error) { Task { await playback.load(record, library: library) } }
            } else if let player = playback.player {
                AVPlayerView(player: player, isFullScreen: $isFullScreen, isPiPActive: $isPiPActive,
                             onPiPStopped: { if !isFullScreen { playback.stop() } })
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else if let url = playback.vlcURL {
                #if UI_REVIEW_PREVIEW
                Text(String(localized: "offline_vlc_preview"))
                #else
                VLCPlayerView(mediaURL: url, startPosition: record.position, duration: Double(record.duration),
                              onTimeChanged: { playback.vlcPosition($0) }, isFullScreen: $isFullScreen)
                    .aspectRatio(16 / 9, contentMode: .fit)
                #endif
            } else { ProgressView().accessibilityLabel(String(localized: "offline_loading")) }
            VStack(alignment: .leading, spacing: 8) {
                Text(record.title).font(.title2.bold())
                Text(record.channel).font(.subheadline).foregroundStyle(.secondary)
                Label(String(localized: "offline_playing_local"), systemImage: "internaldrive")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(Duration.seconds(playback.seconds).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("offline.playback.time")
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            Spacer(minLength: 0)
        }
        .padding(.top)
        .navigationTitle(String(localized: "offline_play"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await playback.load(record, library: library) }
        .onDisappear {
            library.savePosition(record.id, seconds: playback.seconds)
            if !isFullScreen && !isPiPActive { playback.stop() }
        }
    }
}
