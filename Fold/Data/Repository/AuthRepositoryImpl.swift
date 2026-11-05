import Foundation

final class AuthRepositoryImpl: AuthRepositoryProtocol {
    private let apiClient: APIClient
    private let authState: AuthState

    init(apiClient: APIClient, authState: AuthState) {
        self.apiClient = apiClient
        self.authState = authState
    }

    func login(serverURL: String, username: String, password: String) async throws {
        var normalizedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedURL.hasSuffix("/") {
            normalizedURL = String(normalizedURL.dropLast())
        }
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            normalizedURL = "https://\(normalizedURL)"
        }

        guard let url = URL(string: normalizedURL) else {
            throw AppError.invalidURL
        }

        let token = try await apiClient.login(
            serverURL: url,
            username: username,
            password: password
        )

        authState.setCredentials(token: token, serverURL: normalizedURL)
    }

    func connectSession(serverURL: URL, cookies: [HTTPCookie]) async throws {
        // Validate without fetching/creating tokens or replacing a working connection.
        let userID = try await apiClient.verify(RequestAuthorization(baseURL: serverURL, cookies: cookies))
        try authState.setSession(cookies: cookies, serverURL: serverURL, userID: userID)
    }

    func connectToken(serverURL: URL, token: String) async throws {
        let userID = try await apiClient.verify(RequestAuthorization(baseURL: serverURL, token: token))
        try authState.setExistingToken(token, serverURL: serverURL, userID: userID)
    }

    func ping() async throws -> Bool {
        let snapshot = authState.authorization?.id
        let response: PingDTO = try await apiClient.request(endpoint: .ping)
        if response.response == "pong", let user = response.user, let snapshot { authState.setVerifiedAccount(user, authorizationID: snapshot) }
        return response.response == "pong"
    }

    func fetchUserAccount() async throws {
        let snapshot = authState.authorization?.id
        let dto: UserAccountDTO = try await apiClient.request(endpoint: .userAccount)
        guard let snapshot, authState.authorization?.id == snapshot, !Task.isCancelled else { throw CancellationError() }
        if let user = dto.id { authState.setVerifiedAccount(user, authorizationID: snapshot) }
        authState.setPrivileges(
            isSuperuser: dto.isSuperuser ?? false,
            isStaff: dto.isStaff ?? false
        )
    }

    func logout() {
        authState.handleUnauthorized()
    }
}
