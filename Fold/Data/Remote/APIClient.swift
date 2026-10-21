import Foundation

final class APIClient {
    private static let decoder = JSONDecoder()

    private let authState: AuthState
    private let session: URLSession
    private let loginSession: URLSession

    init(
        authState: AuthState,
        configuration: URLSessionConfiguration = .default,
        loginConfiguration: URLSessionConfiguration = .default
    ) {
        self.authState = authState

        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)

        loginConfiguration.httpCookieStorage = nil
        loginConfiguration.urlCache = nil
        self.loginSession = URLSession(configuration: loginConfiguration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel(); loginSession.invalidateAndCancel() }

    func verify(_ authorization: RequestAuthorization) async throws {
        var request = URLRequest(url: authorization.baseURL.appendingPathComponent("api/ping/"))
        try authorization.apply(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              !RequestAuthorization.isAuthenticationFailure(http), (200...299).contains(http.statusCode),
              let ping = try? Self.decoder.decode(PingDTO.self, from: data),
              ping.response == "pong", ping.user != nil else { throw AppError.unauthorized }
    }

    func request<T: Decodable>(
        endpoint: APIEndpoint,
        body: (any Encodable)? = nil,
        baseURL: URL? = nil
    ) async throws -> T {
        let data = try await rawRequest(endpoint: endpoint, body: body, baseURL: baseURL)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(underlying: error)
        }
    }

    func requestVoid(
        endpoint: APIEndpoint,
        body: (any Encodable)? = nil,
        baseURL: URL? = nil
    ) async throws {
        _ = try await rawRequest(endpoint: endpoint, body: body, baseURL: baseURL)
    }

    private func rawRequest(
        endpoint: APIEndpoint,
        body: (any Encodable)? = nil,
        baseURL: URL? = nil
    ) async throws -> Data {
        let base = baseURL ?? authState.baseURL
        guard let base else {
            throw AppError.invalidURL
        }

        var components = URLComponents(url: base.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)
        components?.queryItems = endpoint.queryItems

        guard let url = components?.url else {
            throw AppError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let authorization = authState.authorization
        try checkCurrentConnection(authorization)
        try authorization?.apply(to: &request)

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try checkCurrentConnection(authorization)
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw AppError.network(underlying: error)
        }
        try checkCurrentConnection(authorization)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network(underlying: nil)
        }

        let authenticationFailed: Bool
        if let authorization {
            authenticationFailed = try await authorization.isAuthenticationFailure(httpResponse, using: session)
        } else { authenticationFailed = RequestAuthorization.isAuthenticationFailure(httpResponse) }
        try checkCurrentConnection(authorization)
        if authenticationFailed {
            // Optional notification/task callers must not swallow a confirmed expiry.
            if let authorization {
                NotificationCenter.default.post(name: .taAuthUnauthorized, object: nil,
                    userInfo: ["authorizationID": authorization.id])
            }
            throw AppError.unauthorized
        }
        // A valid login does not make an HTML app shell a successful API action.
        // In particular, requestVoid must not report a mutation as completed.
        if (200...299).contains(httpResponse.statusCode), httpResponse.mimeType == "text/html" {
            throw AppError.decoding(underlying: nil)
        }
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 403:
            throw AppError.permissionDenied
        default:
            let message = String(data: data, encoding: .utf8)
            throw AppError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func checkCurrentConnection(_ authorization: RequestAuthorization?) throws {
        try Task.checkCancellation()
        guard authorization?.id == authState.authorization?.id, authorization?.isActive != false else {
            throw CancellationError()
        }
    }

    // MARK: - Login (2-step with cookies)

    func login(serverURL: URL, username: String, password: String) async throws -> String {
        // Step 1: POST login to get session cookie
        let loginURL = serverURL.appendingPathComponent("/api/user/login/")
        var loginRequest = URLRequest(url: loginURL)
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let loginBody = LoginRequestDTO(username: username, password: password)
        loginRequest.httpBody = try JSONEncoder().encode(loginBody)

        let (_, loginResponse): (Data, URLResponse)
        do {
            (_, loginResponse) = try await loginSession.data(for: loginRequest)
        } catch {
            throw AppError.network(underlying: error)
        }

        guard let httpLoginResponse = loginResponse as? HTTPURLResponse else {
            throw AppError.network(underlying: nil)
        }

        guard (200...299).contains(httpLoginResponse.statusCode) else {
            throw AppError.serverError(
                statusCode: httpLoginResponse.statusCode,
                message: "Login failed"
            )
        }

        // Step 2: GET token using session cookie
        let tokenURL = serverURL.appendingPathComponent("/api/appsettings/token/")
        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.httpMethod = "GET"
        let responseHeaders = httpLoginResponse.allHeaderFields.reduce(into: [String: String]()) { headers, entry in
            if let key = entry.key as? String, let value = entry.value as? String { headers[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: responseHeaders, for: serverURL)
        try RequestAuthorization(baseURL: serverURL, cookies: cookies).apply(to: &tokenRequest)

        let (tokenData, tokenResponse): (Data, URLResponse)
        do {
            (tokenData, tokenResponse) = try await loginSession.data(for: tokenRequest)
        } catch {
            throw AppError.network(underlying: error)
        }

        guard let httpTokenResponse = tokenResponse as? HTTPURLResponse,
              (200...299).contains(httpTokenResponse.statusCode) else {
            throw AppError.serverError(statusCode: 0, message: "Failed to retrieve token")
        }

        let tokenDTO = try Self.decoder.decode(TokenResponseDTO.self, from: tokenData)

        return tokenDTO.token
    }
}
