import Foundation

@Observable
final class AuthState {
    private(set) var authorization: RequestAuthorization?
    private(set) var token: String?
    private(set) var reloginURL: String?
    private(set) var serverURL: String?
    private(set) var isSuperuser = false
    private(set) var isStaff = false
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
            token = stored.token
            serverURL = url.absoluteString
            authorization = RequestAuthorization(baseURL: url, token: stored.token, cookies: stored.cookies.compactMap(\.cookie))
        } else if let baseURL, token != nil {
            // Keep the existing token connection; migration never obtains or rotates a token.
            authorization = RequestAuthorization(baseURL: baseURL, token: token)
        }
    }

    func setSession(cookies: [HTTPCookie], serverURL: URL) throws {
        let auth = RequestAuthorization(baseURL: serverURL, cookies: cookies)
        let data = try JSONEncoder().encode(StoredSession(serverURL: serverURL, cookies: auth.cookies.map(StoredCookie.init)))
        guard let value = String(data: data, encoding: .utf8),
              keychainService.save(value, for: .sessionCookies) else { throw AppError.unknown(message: String(localized: "error_generic")) }
        authorization?.revoke()
        token = nil
        self.serverURL = serverURL.absoluteString
        authorization = auth
        keychainService.delete(for: .authToken)
        keychainService.save(serverURL.absoluteString, for: .serverURL)
    }

    func setExistingToken(_ token: String, serverURL: URL) throws {
        let record = StoredSession(serverURL: serverURL, cookies: [], token: token)
        let data = try JSONEncoder().encode(record)
        guard let value = String(data: data, encoding: .utf8), keychainService.save(value, for: .sessionCookies) else {
            throw AppError.unknown(message: String(localized: "error_generic"))
        }
        authorization?.revoke()
        self.token = token
        self.serverURL = serverURL.absoluteString
        authorization = RequestAuthorization(baseURL: serverURL, token: token)
        keychainService.delete(for: .authToken)
        keychainService.save(serverURL.absoluteString, for: .serverURL)
    }

    func setCredentials(token: String, serverURL: String) {
        authorization?.revoke()
        authorization = URL(string: serverURL).map { RequestAuthorization(baseURL: $0, token: token) }
        keychainService.delete(for: .sessionCookies)
        self.token = token
        self.serverURL = serverURL
        keychainService.save(token, for: .authToken)
        keychainService.save(serverURL, for: .serverURL)
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
        isSuperuser = false
        isStaff = false
        keychainService.clearAll()
    }
}
