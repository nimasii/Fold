import SwiftUI
import AVFoundation

@main
struct FoldApp: App {
    @State private var container = DependencyContainer.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Configure audio session category once at app launch. Activation is
        // deferred to `PlayerSessionCoordinator.start()` when playback begins
        // — avoids stealing audio focus from Music/Podcasts while the user is
        // only browsing the app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
    }

    var body: some Scene {
        WindowGroup {
            appContent
                .tint(StreamingStyle.accent)
                .environment(container)
                .environment(container.router)
                .environment(container.authState)
                .environment(container.offlineLibrary)
                .environment(\.playbackCoordinator, container.playbackCoordinator)
                .onChange(of: container.authState.authorization?.id) {
                    container.offlineLibrary.authorizationChanged()
                    container.playbackCoordinator.connectionChanged()
                }
                .onChange(of: container.authState.playbackAccount) { container.playbackCoordinator.connectionChanged() }
                .onChange(of: container.authState.accountConfirmed) { container.playbackCoordinator.requestSync() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { container.offlineLibrary.pauseAll() }
                    if phase == .active {
                        container.playbackCoordinator.requestSync(force: true)
                        forceLayoutUpdate()
                    }
                }
        }
    }

    @ViewBuilder private var appContent: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--streaming-fixture") {
            StreamingFixtureRoot()
        } else if ProcessInfo.processInfo.arguments.contains("--playback-fixture") {
            PlaybackParityFixtureView()
        } else { RootView() }
        #else
        RootView()
        #endif
    }

    private func forceLayoutUpdate() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.rootViewController?.view.setNeedsLayout()
                window.rootViewController?.view.layoutIfNeeded()
            }
        }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DependencyContainer.self) private var container

    var body: some View {
        @Bindable var router = router

        switch router.appState {
        case .splash:
            NavigationStack(path: $router.path) {
                VStack {
                    SplashView()
                    NavigationLink(value: Route.offlineDownloads) {
                        Label(String(localized: "offline_title"), systemImage: "arrow.down.circle")
                    }
                    .accessibilityLabel(String(localized: "offline_title"))
                }
                .background(StreamingStyle.background)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Route.self) { destination(for: $0) }
            }
            .task(id: router.path.isEmpty) {
                guard router.path.isEmpty else { return }
                await autoLogin()
            }
        case .login:
            NavigationStack(path: $router.path) {
                LoginScreen { container.makeLoginViewModel() }
                    .navigationDestination(for: Route.self) { destination(for: $0) }
            }
        case .authenticated:
            StreamingTabs { destination(for: $0) }
        }
    }

    @ViewBuilder private func destination(for route: Route) -> some View {
        switch route {
        case .videoList: VideoListScreen { container.makeVideoListViewModel() }
        case .videoDetail(let id): VideoDetailScreen { container.makeVideoDetailViewModel(videoId: id) }
        case .search: SearchScreen { container.makeSearchViewModel() }
        case .channelDetail(let id): ChannelDetailScreen { container.makeChannelDetailViewModel(channelId: id) }
        case .downloadQueue: DownloadQueueScreen { container.makeDownloadQueueViewModel() }
        case .offlineDownloads: OfflineDownloadsView(videoRepository: container.videoRepository, playbackSettings: container.sponsorBlockSettings)
        case .playlistList: PlaylistListScreen { container.makePlaylistListViewModel() }
        case .playlistDetail(let id): PlaylistDetailScreen { container.makePlaylistDetailViewModel(playlistId: id) }
        case .settings: SettingsScreen { container.makeSettingsViewModel() }
        case .about: AboutView()
        }
    }

    private func autoLogin() async {
        await SessionRestorer.restore(authState: container.authState, repository: container.authRepository, router: router)
    }
}
