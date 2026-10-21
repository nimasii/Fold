import SwiftUI

enum AppState {
    case splash
    case login
    case authenticated
}

enum AppTab: Int, CaseIterable {
    case library, downloads, queue
}

@Observable
final class AppRouter {
    var autoplayVideoID: String?
    var selectedTab: AppTab = .library
    var isPrivatePlayerVisible = false
    var librarySearchQuery = ""
    var isLibrarySearchActive = false
    var librarySearchWantsFocus = false
    var librarySearchPath = NavigationPath()
    private(set) var searchReturnTab: AppTab = .library

    /// Search is transient Library context, with its own history. Cancel returns
    /// to the originating section without discarding any section's navigation.
    func beginLibrarySearch() {
        if !isLibrarySearchActive { searchReturnTab = selectedTab }
        librarySearchWantsFocus = true
        selectedTab = .library
        isLibrarySearchActive = true
    }
    func cancelLibrarySearch(returnToOrigin: Bool = true) {
        if returnToOrigin && isLibrarySearchActive { selectedTab = searchReturnTab }
        librarySearchQuery = ""
        isLibrarySearchActive = false
        librarySearchWantsFocus = false
        librarySearchPath = NavigationPath()
    }
    private var tabPaths: [AppTab: NavigationPath] = [:]
    private var entryPath = NavigationPath()
    var path: NavigationPath {
        get {
            if appState != .authenticated { return entryPath }
            return isLibrarySearchActive ? librarySearchPath : path(for: selectedTab)
        }
        set {
            if appState == .authenticated {
                if isLibrarySearchActive { librarySearchPath = newValue }
                else { tabPaths[selectedTab] = newValue }
            }
            else { entryPath = newValue }
        }
    }

    func path(for tab: AppTab) -> NavigationPath { tabPaths[tab] ?? NavigationPath() }
    func setPath(_ path: NavigationPath, for tab: AppTab) { tabPaths[tab] = path }
    private func resetNavigation() {
        autoplayVideoID = nil
        entryPath = NavigationPath()
        tabPaths.removeAll()
        selectedTab = .library
        cancelLibrarySearch(returnToOrigin: false)
        searchReturnTab = .library
        isPrivatePlayerVisible = false
    }
    var appState: AppState
    private(set) var deletedVideoIds: Set<String> = []
    private(set) var watchedChanges: [String: Bool] = [:]

    private let authState: AuthState
    private var didHandleUnauth: Bool = false
    @ObservationIgnored private var unauthorizedObserver: NSObjectProtocol?

    init(authState: AuthState) {
        self.authState = authState
        self.appState = authState.isAuthenticated ? .splash : .login

        // Subscribe to Data-layer auth failure notifications. The preloader and
        // `CachingResourceLoader` don't go through `APIClient`, so they post
        // this instead of propagating a typed `AppError.unauthorized` upward.
        self.unauthorizedObserver = NotificationCenter.default.addObserver(
            forName: .taAuthUnauthorized,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let id = notification.userInfo?["authorizationID"] as? UUID,
               id != self?.authState.authorization?.id { return }
            self?.handleUnauthorized()
        }
    }

    deinit {
        if let token = unauthorizedObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func navigate(to route: Route) {
        path.append(route)
    }

    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func markVideoDeleted(_ videoId: String) {
        deletedVideoIds.insert(videoId)
    }

    func markWatchedChanged(_ videoId: String, isWatched: Bool) {
        watchedChanges[videoId] = isWatched
    }

    func handleUnauthorized() {
        // Idempotent: multiple concurrent data-layer failures (preloader,
        // resource loader, API) often fire this in rapid succession. We only
        // want to wipe state and transition to `.login` once per session.
        if didHandleUnauth { return }
        didHandleUnauth = true

        authState.handleUnauthorized()
        Task { [authState] in
            guard authState.authorization == nil else { return }
            await ImageCache.shared.clear()
            guard authState.authorization == nil else { return }
            await VideoCachePreloader.shared.clear()
        }
        resetNavigation()
        deletedVideoIds.removeAll()
        watchedChanges.removeAll()
        appState = .login
    }

    func onLoginSuccess() {
        didHandleUnauth = false
        resetNavigation()
        deletedVideoIds.removeAll()
        watchedChanges.removeAll()
        appState = .authenticated
    }

    /// An unavailable network is not evidence that saved credentials expired.
    func onAutoLoginUnavailable() {
        // Keep the restored connection usable for downloads and retry. A temporary
        // outage must not make a returning owner repeat the sign-in flow.
        if authState.isAuthenticated { onLoginSuccess() }
        else { appState = .login }
    }

    func onAutoLoginFailed() {
        authState.handleUnauthorized()
        appState = .login
    }

    /// Handles errors from async repository calls.
    /// Returns `true` if the error was unauthorized (caller should stop further work).
    @discardableResult
    func handleError(_ error: Error, errorMessage: inout String?) -> Bool {
        if let appError = error as? AppError, case .unauthorized = appError {
            handleUnauthorized()
            return true
        }
        if let appError = error as? AppError {
            errorMessage = appError.errorDescription
        } else {
            errorMessage = String(localized: "error_generic")
        }
        return false
    }
}
