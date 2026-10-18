import Foundation

@Observable
final class DependencyContainer {
    static let shared = DependencyContainer()

    // Local
    let keychainService: KeychainService
    let authState: AuthState
    let offlineLibrary: OfflineLibrary

    // Network
    let apiClient: APIClient

    // Repositories
    let authRepository: AuthRepositoryProtocol
    let videoRepository: VideoRepositoryProtocol
    let searchRepository: SearchRepositoryProtocol
    let channelRepository: ChannelRepositoryProtocol
    let downloadRepository: DownloadRepositoryProtocol
    let playlistRepository: PlaylistRepositoryProtocol

    // Settings
    let sponsorBlockSettings: SponsorBlockSettings

    // Navigation
    let router: AppRouter

    private init() {
        #if DEBUG && targetEnvironment(simulator) && !UI_REVIEW_PREVIEW
        if ProcessInfo.processInfo.arguments.contains("--streaming-fixture") {
            keychainService = KeychainService(inMemory: true)
            authState = AuthState(keychainService: keychainService, loadPersistedCredentials: false)
            try? authState.setExistingToken("STREAMING_FIXTURE_TOKEN", serverURL: URL(string: StreamingFixtureRepository.base)!)
            authState.setPrivileges(isSuperuser: true, isStaff: true)
            apiClient = APIClient(authState: authState)
            let repository = StreamingFixtureRepository()
            authRepository = repository; videoRepository = repository; searchRepository = repository
            channelRepository = repository; downloadRepository = repository; playlistRepository = repository
            sponsorBlockSettings = SponsorBlockSettings(defaults: UserDefaults(suiteName: "StreamingDesignFixture-v1")!)
            router = AppRouter(authState: authState)
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("StreamingDesignFixture-v1", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--streaming-fixture-reset") { try? FileManager.default.removeItem(at: root) }
            if ProcessInfo.processInfo.arguments.contains("--streaming-fixture-legacy-artwork") || ProcessInfo.processInfo.arguments.contains("--streaming-fixture-corrupt-artwork"),
               let store = try? OfflineDiskStore(root: root), var copies = try? store.load() {
                for index in copies.indices where copies[index].status == .ready {
                    if ProcessInfo.processInfo.arguments.contains("--streaming-fixture-legacy-artwork") { copies[index].metadata = nil }
                    for kind in ["thumbnail", "channel"] {
                        let file = root.appendingPathComponent("Artwork/" + copies[index].id.uuidString + "-" + kind + ".jpg")
                        if ProcessInfo.processInfo.arguments.contains("--streaming-fixture-corrupt-artwork") {
                            try? Data("corrupt fixture".utf8).write(to: file, options: .atomic)
                        } else { try? FileManager.default.removeItem(at: file) }
                    }
                }
                try? store.save(copies)
            }
            offlineLibrary = OfflineLibrary(authState: authState, root: root)
            router.onLoginSuccess()
            if ProcessInfo.processInfo.arguments.contains("--streaming-fixture-downloads") { router.selectedTab = .downloads }
            if ProcessInfo.processInfo.arguments.contains("--streaming-fixture-login") { router.appState = .login }
            return
        }
        #endif
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--session-persistence-fixture") {
            keychainService = KeychainService(persistentFixture: true)
            if ProcessInfo.processInfo.arguments.contains("--session-persistence-reset") { keychainService.clearAll() }
        } else { keychainService = KeychainService() }
        #else
        keychainService = KeychainService()
        #endif
        #if DEBUG
        let isolated = (ProcessInfo.processInfo.arguments.contains("--connection-fixture") || ProcessInfo.processInfo.arguments.contains("--playback-fixture")) || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        authState = AuthState(keychainService: keychainService, loadPersistedCredentials: !isolated)
        #else
        authState = AuthState(keychainService: keychainService)
        #endif
        apiClient = APIClient(authState: authState)

        authRepository = AuthRepositoryImpl(apiClient: apiClient, authState: authState)
        videoRepository = VideoRepositoryImpl(apiClient: apiClient, authState: authState)
        searchRepository = SearchRepositoryImpl(apiClient: apiClient, authState: authState)
        channelRepository = ChannelRepositoryImpl(apiClient: apiClient, authState: authState)
        downloadRepository = DownloadRepositoryImpl(apiClient: apiClient, authState: authState)
        playlistRepository = PlaylistRepositoryImpl(apiClient: apiClient, authState: authState)

        sponsorBlockSettings = SponsorBlockSettings()
        router = AppRouter(authState: authState)
        offlineLibrary = OfflineLibrary(authState: authState)
    }

    // MARK: - ViewModel Factories

    func makeLoginViewModel() -> LoginViewModel {
        let model = LoginViewModel(authRepository: authRepository, router: router)
        model.serverURL = authState.reloginURL ?? authState.serverURL ?? ""
        return model
    }

    func makeVideoListViewModel() -> VideoListViewModel {
        VideoListViewModel(videoRepository: videoRepository, authRepository: authRepository, downloadRepository: downloadRepository, router: router)
    }

    func makeVideoDetailViewModel(videoId: String) -> VideoDetailViewModel {
        VideoDetailViewModel(videoId: videoId, videoRepository: videoRepository, authState: authState, router: router, sponsorBlockSettings: sponsorBlockSettings, playlistRepository: playlistRepository)
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(searchRepository: searchRepository, router: router)
    }

    func makeChannelDetailViewModel(channelId: String) -> ChannelDetailViewModel {
        ChannelDetailViewModel(channelId: channelId, channelRepository: channelRepository, videoRepository: videoRepository, router: router)
    }

    func makeDownloadQueueViewModel() -> DownloadQueueViewModel {
        DownloadQueueViewModel(downloadRepository: downloadRepository, router: router)
    }

    func makePlaylistListViewModel() -> PlaylistListViewModel {
        PlaylistListViewModel(playlistRepository: playlistRepository, router: router)
    }

    func makePlaylistDetailViewModel(playlistId: String) -> PlaylistDetailViewModel {
        PlaylistDetailViewModel(playlistId: playlistId, playlistRepository: playlistRepository, videoRepository: videoRepository, router: router)
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(settings: sponsorBlockSettings)
    }
}
