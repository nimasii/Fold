import SwiftUI
import AVFoundation

@main
struct TAClientApp: App {
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
            RootView()
                .environment(container)
                .environment(container.router)
                .environment(container.authState)
                .environment(container.offlineLibrary)
                .onChange(of: container.authState.authorization?.id) { container.offlineLibrary.authorizationChanged() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { container.offlineLibrary.pauseAll() }
                    if phase == .active {
                        forceLayoutUpdate()
                    }
                }
        }
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
                .navigationTitle("Tube Archivist")
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
            NavigationStack(path: $router.path) {
                VideoListScreen { container.makeVideoListViewModel() }
                    .navigationDestination(for: Route.self) { destination(for: $0) }
            }
        }
    }

    @ViewBuilder private func destination(for route: Route) -> some View {
        switch route {
        case .videoList: VideoListScreen { container.makeVideoListViewModel() }
        case .videoDetail(let id): VideoDetailScreen { container.makeVideoDetailViewModel(videoId: id) }
        case .search: SearchScreen { container.makeSearchViewModel() }
        case .channelDetail(let id): ChannelDetailScreen { container.makeChannelDetailViewModel(channelId: id) }
        case .downloadQueue: DownloadQueueScreen { container.makeDownloadQueueViewModel() }
        case .offlineDownloads: OfflineDownloadsView(videoRepository: container.videoRepository)
        case .playlistList: PlaylistListScreen { container.makePlaylistListViewModel() }
        case .playlistDetail(let id): PlaylistDetailScreen { container.makePlaylistDetailViewModel(playlistId: id) }
        case .settings: SettingsScreen { container.makeSettingsViewModel() }
        case .about: AboutView()
        }
    }

    private func autoLogin() async {
        do {
            let isValid = try await container.authRepository.ping()
            guard !Task.isCancelled, router.path.isEmpty else { return }
            if isValid {
                try? await container.authRepository.fetchUserAccount()
                guard !Task.isCancelled, router.path.isEmpty else { return }
                router.onLoginSuccess()
            } else {
                router.onAutoLoginFailed()
            }
        } catch {
            guard !Task.isCancelled, router.path.isEmpty else { return }
            if let error = error as? AppError, case .unauthorized = error { router.onAutoLoginFailed() }
            else { router.onAutoLoginUnavailable() }
        }
    }
}
