import SwiftUI

@main
struct UIReviewPreviewApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var preview = UIReviewPreviewContext()
    @State private var previewColorScheme: ColorScheme? = ProcessInfo.processInfo.arguments.contains("--review-dark") ? .dark : nil
    private let reviewScreen = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--review-screen=") }?.split(separator: "=").last.map(String.init)

    var body: some Scene {
        WindowGroup {
            @Bindable var router = preview.router

            NavigationStack(path: $router.path) {
                Group {
                    if reviewScreen == "offline" {
                        OfflineDownloadsView(videoRepository: preview.repository)
                            .toolbar {
                                if ProcessInfo.processInfo.arguments.contains("--review-offline-transfer") {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Download fixture") { preview.offlineLibrary.enqueue(OfflinePreviewFixture.video) }
                                    }
                                }
                            }
                    } else if reviewScreen == "login" {
                        LoginScreen { LoginViewModel(authRepository: preview.repository, router: preview.router) }
                    } else if reviewScreen == "search" {
                        SearchScreen(make: preview.makeSearchViewModel)
                    } else {
                        VideoListScreen(make: preview.makeVideoListViewModel)
                    }
                }
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .videoList:
                            VideoListScreen(make: preview.makeVideoListViewModel)
                        case .videoDetail(let videoId):
                            VideoDetailScreen { preview.makeVideoDetailViewModel(videoId: videoId) }
                        case .search:
                            SearchScreen(make: preview.makeSearchViewModel)
                        case .channelDetail(let channelId):
                            ChannelDetailScreen { preview.makeChannelDetailViewModel(channelId: channelId) }
                        case .offlineDownloads: OfflineDownloadsView(videoRepository: preview.repository)
                        case .downloadQueue:
                            DownloadQueueScreen(make: preview.makeDownloadQueueViewModel)
                        case .playlistList:
                            PlaylistListScreen(make: preview.makePlaylistListViewModel)
                        case .playlistDetail(let playlistId):
                            PlaylistDetailScreen { preview.makePlaylistDetailViewModel(playlistId: playlistId) }
                        case .settings:
                            SettingsScreen(make: preview.makeSettingsViewModel)
                        case .about:
                            AboutView()
                        }
                    }
            }
            .environment(preview.authState)
            .environment(preview.router)
            .environment(preview.offlineLibrary)
            .onChange(of: preview.authState.authorization?.id) { preview.offlineLibrary.authorizationChanged() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { preview.offlineLibrary.pauseAll() } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                    Text("UI REVIEW PREVIEW")
                        .fontWeight(.bold)
                    Spacer(minLength: 8)
                    Text(reviewScreen == "offline" ? "Local fixtures" : "Synthetic · playback off")
                        .lineLimit(1)
                    Menu {
                        Button("System") { previewColorScheme = nil }
                        Button("Light") { previewColorScheme = .light }
                        Button("Dark") { previewColorScheme = .dark }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                    .accessibilityLabel("Preview appearance")
                }
                .font(.caption2)
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(reviewScreen == "offline"
                    ? "UI review preview. Synthetic local video fixtures."
                    : "UI review preview. Synthetic fixtures. Playback is unavailable.")
            }
            .preferredColorScheme(previewColorScheme)
            .tint(.accentColor)
        }
    }
}

@MainActor
@Observable
final class UIReviewPreviewContext {
    let authState: AuthState
    let offlineLibrary: OfflineLibrary
    let router: AppRouter
    let repository: UIReviewPreviewRepository
    let sponsorBlockSettings: SponsorBlockSettings

    init() {
        authState = AuthState(keychainService: KeychainService(inMemory: true), loadPersistedCredentials: false)
        offlineLibrary = OfflinePreviewFixture.makeLibrary(authState: authState)
        router = AppRouter(authState: authState)
        repository = UIReviewPreviewRepository()
        sponsorBlockSettings = SponsorBlockSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        router.onLoginSuccess()
        if ProcessInfo.processInfo.arguments.contains("--review-screen=downloads") {
            authState.setPrivileges(isSuperuser: true, isStaff: true)
            router.navigate(to: .downloadQueue)
        }
    }

    func makeVideoListViewModel() -> VideoListViewModel {
        VideoListViewModel(
            videoRepository: repository,
            authRepository: repository,
            downloadRepository: repository,
            router: router
        )
    }

    func makeVideoDetailViewModel(videoId: String) -> VideoDetailViewModel {
        VideoDetailViewModel(
            videoId: videoId,
            videoRepository: repository,
            authState: authState,
            router: router,
            sponsorBlockSettings: sponsorBlockSettings,
            playlistRepository: repository
        )
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(searchRepository: repository, router: router)
    }

    func makeChannelDetailViewModel(channelId: String) -> ChannelDetailViewModel {
        ChannelDetailViewModel(
            channelId: channelId,
            channelRepository: repository,
            videoRepository: repository,
            router: router
        )
    }

    func makeDownloadQueueViewModel() -> DownloadQueueViewModel {
        DownloadQueueViewModel(downloadRepository: repository, router: router)
    }

    func makePlaylistListViewModel() -> PlaylistListViewModel {
        PlaylistListViewModel(playlistRepository: repository, router: router)
    }

    func makePlaylistDetailViewModel(playlistId: String) -> PlaylistDetailViewModel {
        PlaylistDetailViewModel(
            playlistId: playlistId,
            playlistRepository: repository,
            videoRepository: repository,
            router: router
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(settings: sponsorBlockSettings)
    }
}
