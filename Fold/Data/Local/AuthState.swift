import Foundation

@Observable
final class AuthState {
    private(set) var authorization: RequestAuthorization?
    private(set) var token: String?
    private(set) var reloginURL: String?
    private(set) var serverURL: String?
    private(set) var isSuperuser = false
    private(set) var isStaff = false
    private(set) var userID: Int?
    private(set) var accountConfirmed = false
    var playbackAccount: PlaybackAccount? {
        guard let baseURL, let userID, isAuthenticated else { return nil }
        return PlaybackAccount(baseURL: baseURL, userID: userID)
    }
    private let keychainService: KeychainService

    var isAuthenticated: Bool {
        authorization != nil && serverURL != nil
    }

    /// Existing playback APIs still accept a token argument; session transports use authorization.
    var playbackToken: String? { isAuthenticated ? (token ?? "") : nil }

    var isPrivileged: Bool {
        isSuperuser || isStaff
    }

    var baseURL: URL? {
        guard let serverURL else { return nil }
        return URL(string: serverURL)
    }

    init(keychainService: KeychainService, loadPersistedCredentials: Bool = true) {
        self.keychainService = keychainService
        if loadPersistedCredentials {
            self.token = keychainService.load(for: .authToken)
            self.serverURL = keychainService.load(for: .serverURL)
        } else {
            self.token = nil
            self.serverURL = nil
        }
        if loadPersistedCredentials,
           let data = keychainService.load(for: .sessionCookies)?.data(using: .utf8),
           let stored = try? JSONDecoder().decode(StoredSession.self, from: data),
           let url = RequestAuthorization.normalizedURL(stored.serverURL.absoluteString) {
            userID = stored.userID
            token = stored.token
            serverURL = url.absoluteString
            authorization = RequestAuthorization(baseURL: url, token: stored.token, cookies: stored.cookies.compactMap(\.cookie))
        } else if let baseURL, token != nil {
            // Keep the existing token connection; migration never obtains or rotates a token.
            authorization = RequestAuthorization(baseURL: baseURL, token: token)
        }
    }

    func setSession(cookies: [HTTPCookie], serverURL: URL, userID: Int? = nil) throws {
        let auth = RequestAuthorization(baseURL: serverURL, cookies: cookies)
        let data = try JSONEncoder().encode(StoredSession(serverURL: serverURL, cookies: auth.cookies.map(StoredCookie.init), userID: userID))
        guard let value = String(data: data, encoding: .utf8),
              keychainService.save(value, for: .sessionCookies) else { throw AppError.unknown(message: String(localized: "error_generic")) }
        authorization?.revoke()
        token = nil
        self.userID = userID; accountConfirmed = userID != nil
        self.serverURL = serverURL.absoluteString
        authorization = auth
        keychainService.delete(for: .authToken)
        keychainService.save(serverURL.absoluteString, for: .serverURL)
    }

    func setExistingToken(_ token: String, serverURL: URL, userID: Int? = nil) throws {
        let record = StoredSession(serverURL: serverURL, cookies: [], token: token, userID: userID)
        let data = try JSONEncoder().encode(record)
        guard let value = String(data: data, encoding: .utf8), keychainService.save(value, for: .sessionCookies) else {
            throw AppError.unknown(message: String(localized: "error_generic"))
        }
        authorization?.revoke()
        self.token = token
        self.userID = userID; accountConfirmed = userID != nil
        self.serverURL = serverURL.absoluteString
        authorization = RequestAuthorization(baseURL: serverURL, token: token)
        keychainService.delete(for: .authToken)
        keychainService.save(serverURL.absoluteString, for: .serverURL)
    }

    func setCredentials(token: String, serverURL: String) {
        userID = nil; accountConfirmed = false
        authorization?.revoke()
        authorization = URL(string: serverURL).map { RequestAuthorization(baseURL: $0, token: token) }
        keychainService.delete(for: .sessionCookies)
        self.token = token
        self.serverURL = serverURL
        keychainService.save(token, for: .authToken)
        keychainService.save(serverURL, for: .serverURL)
    }

    /// Only a response from this exact still-active connection may name its account.
    func setVerifiedAccount(_ userID: Int, authorizationID: UUID) {
        guard userID > 0, let auth = authorization, auth.id == authorizationID, auth.isActive else { return }
        self.userID = userID
        accountConfirmed = true
        let record = StoredSession(serverURL: auth.baseURL, cookies: auth.cookies.map(StoredCookie.init), token: token, userID: userID)
        if let data = try? JSONEncoder().encode(record), let value = String(data: data, encoding: .utf8) {
            keychainService.save(value, for: .sessionCookies)
        }
    }

    func setPrivileges(isSuperuser: Bool, isStaff: Bool) {
        self.isSuperuser = isSuperuser
        self.isStaff = isStaff
    }

    func handleUnauthorized() {
        reloginURL = serverURL
        authorization?.revoke()
        authorization = nil
        token = nil
        serverURL = nil
        userID = nil; accountConfirmed = false
        isSuperuser = false
        isStaff = false
        keychainService.clearAll()
    }
}
