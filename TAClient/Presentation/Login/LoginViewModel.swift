import Foundation

@Observable
final class LoginViewModel {
    var serverURL: String = ""
    var apiToken = ""
    var signInDestination: ServerSignInDestination?
    var username: String = ""
    var password: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    private let authRepository: AuthRepositoryProtocol
    private let router: AppRouter

    init(authRepository: AuthRepositoryProtocol, router: AppRouter) {
        self.authRepository = authRepository
        self.router = router
    }

    func beginServerSignIn() {
        guard let url = RequestAuthorization.normalizedURL(serverURL) else {
            errorMessage = String(localized: "error_generic"); return
        }
        errorMessage = nil
        signInDestination = ServerSignInDestination(url: url)
    }

    func completeServerSignIn(url: URL, cookies: [HTTPCookie]) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authRepository.connectSession(serverURL: url, cookies: cookies)
            try? await authRepository.fetchUserAccount()
            await ImageCache.shared.clear()
            await VideoCachePreloader.shared.clear()
            router.onLoginSuccess()
            return true
        } catch {
            errorMessage = String(localized: "login_server_incomplete")
            return false
        }
    }

    func connectToken() async {
        guard let url = RequestAuthorization.normalizedURL(serverURL), !apiToken.isEmpty else {
            errorMessage = String(localized: "login_error_fields_required"); return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authRepository.connectToken(serverURL: url, token: apiToken.trimmingCharacters(in: .whitespacesAndNewlines))
            apiToken = ""
            await ImageCache.shared.clear()
            await VideoCachePreloader.shared.clear()
            try? await authRepository.fetchUserAccount()
            router.onLoginSuccess()
        } catch { errorMessage = String(localized: "login_server_incomplete") }
    }

    func login() async {
        guard !serverURL.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "login_error_fields_required")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await authRepository.login(
                serverURL: serverURL,
                username: username,
                password: password
            )
            try? await authRepository.fetchUserAccount()
            router.onLoginSuccess()
        } catch {
            router.handleError(error, errorMessage: &errorMessage)
        }

        isLoading = false
    }
}
