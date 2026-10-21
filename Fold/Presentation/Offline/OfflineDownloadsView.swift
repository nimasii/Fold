import SwiftUI

struct OfflineDownloadsView: View {
    var videoRepository: VideoRepositoryProtocol? = nil
    @Environment(OfflineLibrary.self) private var library
    @Environment(AuthState.self) private var authState
    @Environment(AppRouter.self) private var router
    var playbackSettings = SponsorBlockSettings()
    @State private var playing: OfflineRecord?
    @State private var removing: OfflineRecord?
    @State private var showInfo = false
    @State private var filter = OfflineListFilter.all
    @Environment(\.scenePhase) private var scenePhase
    @State private var artworkRequestRevision = 0

    private var completed: [OfflineRecord] { filter == .transfers ? [] : library.records.filter { $0.status == .ready } }
    private var transfers: [OfflineRecord] { filter == .ready ? [] : library.records.filter { $0.status != .ready } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                CinemaIntroduction(eyebrow: String(localized: "cinema_downloads_eyebrow"), title: String(localized: "cinema_downloads_title"))
                    .padding(.horizontal, StreamingStyle.gutter)
                deviceHeader
                Picker(String(localized: "nav_filters"), selection: $filter) {
                    ForEach(OfflineListFilter.allCases, id: \.self) { option in Text(option.label).tag(option) }
                }.pickerStyle(.segmented).padding(.horizontal, StreamingStyle.gutter)
                if !completed.isEmpty {
                    Label(String(localized: "cinema_offline_reassurance"), systemImage: "checkmark")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, StreamingStyle.gutter)
                }
                if let error = library.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                if library.records.isEmpty {
                    ContentUnavailableView(String(localized: "offline_empty"), systemImage: "arrow.down.circle",
                        description: Text(String(localized: "offline_empty_help")))
                }
                if !library.records.isEmpty && completed.isEmpty && transfers.isEmpty {
                    ContentUnavailableView(String(localized: "nav_no_matching_downloads"), systemImage: "line.3.horizontal.decrease.circle")
                }
                if !completed.isEmpty {
                    MediaSectionHeading(title: String(localized: "stream_ready"))
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
                        refreshableLocalIDs: Set(completed.filter { library.canRefreshDetails($0) }.map { $0.id.uuidString }),
                        onPrepareLocalArtwork: { id in
                            guard let id = UUID(uuidString: id) else { return }
                            await library.ensureArtwork(id, using: videoRepository)
                        },
                        artworkRequestRevision: (authState.authorization?.id.uuidString ?? "") + ":" + String(artworkRequestRevision)
                    )
                }
                if !transfers.isEmpty { MediaSectionHeading(title: String(localized: "stream_transfers")) }
                ForEach(transfers) { record in
                    transferRow(record).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .geometryGroup()
        .refreshable { library.retryArtworkOnAppearance(); artworkRequestRevision += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { library.retryArtworkOnAppearance(); artworkRequestRevision += 1 } }
        .background(StreamingStyle.background)
        .navigationTitle(String(localized: "offline_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SectionMenu {
                    ForEach(OfflineListFilter.allCases, id: \.self) { option in
                        Button { filter = option } label: {
                            if filter == option { Label(option.label, systemImage: "checkmark") }
                            else { Text(option.label) }
                        }.accessibilityIdentifier("downloads.filter." + option.rawValue)
                    }
                }
            }
        }
        .navigationDestination(item: $playing) { record in
            OfflinePlayerScreen(record: record, library: library, authState: authState, router: router, settings: playbackSettings, metadataRepository: videoRepository)
                .toolbar(.hidden, for: .tabBar)
        }
        .onChange(of: playing?.id) { router.isPrivatePlayerVisible = playing != nil }
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
                        Label(String(localized: UIDevice.current.userInterfaceIdiom == .pad ? "cinema_on_this_ipad" : "offline_on_device"), systemImage: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
                        LabeledContent(String(localized: "offline_storage_used"), value: library.totalSize)
                        Text(String(localized: "offline_private_help"))
                    }
                    Section {
                        Text(String(localized: "offline_transfer_help"))
                        Text(String(localized: "offline_prepare_help"))
                        Text(String(localized: "offline_sign_in_help"))
                        Text(String(localized: "offline_legacy_artwork_help"))
                    }
                }
                .foldReadingSurface()
                .navigationTitle(String(localized: "offline_info"))
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "connection_done")) { showInfo = false }
                        .accessibilityLabel(String(localized: "connection_done"))
                } }
            }
        }
    }

    private var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(String(localized: UIDevice.current.userInterfaceIdiom == .pad ? "cinema_on_this_ipad" : "stream_on_device"), systemImage: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(library.totalSize).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(String(localized: "offline_private_help")).font(.footnote).foregroundStyle(.secondary)
            Button { showInfo = true } label: {
                Label(String(localized: "offline_info"), systemImage: "info.circle")
            }.font(.subheadline).frame(minHeight: 44)
                .accessibilityLabel(String(localized: "offline_info"))
                .accessibilityIdentifier("downloads.info")
        }.padding(16).background(StreamingStyle.surface, in: .rect(cornerRadius: 18))
            .padding(.horizontal, StreamingStyle.gutter)
    }

    private func artwork(_ record: OfflineRecord) -> LocalVideoArtwork {
        LocalVideoArtwork(thumbnail: library.thumbnailURL(record.id), channel: library.channelArtworkURL(record.id), revision: library.artworkRevision)
    }

    private func transferRow(_ record: OfflineRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CinemaVideoRow(video: record.displayVideo, localArtwork: artwork(record))
            Label(record.status.label, systemImage: record.status.isActive ? "arrow.down.circle" : "exclamationmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
            if record.status.isActive {
                ProgressView(value: record.status == .preparing ? record.attempt.flatMap { library.preparationProgress[$0] } : (record.totalBytes > 0 ? min(1, Double(record.bytes) / Double(record.totalBytes)) : nil))
                    .accessibilityLabel(String(localized: "offline_progress"))
                Button(String(localized: "offline_cancel"), systemImage: "stop.circle") { library.cancel(record.id) }
                    .accessibilityLabel(String(localized: "offline_cancel"))
            } else {
                if let failure = record.failure { Text(failure.message).font(.footnote).foregroundStyle(.secondary) }
                Button(String(localized: "retry"), systemImage: "arrow.clockwise") { library.retry(record.id) }
                    .accessibilityLabel(String(localized: "retry"))
            }
            Text(String(localized: "offline_prepare_help")).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(StreamingStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .task(id: artworkRequestRevision) { await library.ensureArtwork(record.id, using: videoRepository) }
        .contextMenu {
            Button(String(localized: "offline_remove"), systemImage: "trash", role: .destructive) { removing = record }
                .accessibilityLabel(String(localized: "offline_remove"))
        }
    }
}

/// Owns the same production view model used by VideoDetailScreen. Init stays side-effect-free.
struct OfflinePlayerScreen: View {
    @State private var viewModel: VideoDetailViewModel
    private let recordID: UUID
    private let library: OfflineLibrary
    private let metadataRepository: VideoRepositoryProtocol?

    init(record: OfflineRecord, library: OfflineLibrary, authState: AuthState, router: AppRouter, settings: SponsorBlockSettings, metadataRepository: VideoRepositoryProtocol? = nil) {
        recordID = record.id; self.library = library; self.metadataRepository = metadataRepository
        let source = LocalVideoPlayback(record: record, library: library)
        _viewModel = State(wrappedValue: VideoDetailViewModel(
            videoId: record.id.uuidString, videoRepository: LocalVideoRepository(source: source),
            authState: authState, router: router, sponsorBlockSettings: settings, localPlayback: source))
    }

    var body: some View {
        VideoDetailView(viewModel: viewModel)
            .task { await library.ensureArtwork(recordID, using: metadataRepository) }
    }
}

private enum OfflineListFilter: String, CaseIterable {
    case all, ready, transfers
    var label: String {
        switch self {
        case .all: String(localized: "filter_all")
        case .ready: String(localized: "stream_ready")
        case .transfers: String(localized: "stream_transfers")
        }
    }
}
