import Foundation

/// A connection-scoped snapshot shared by API, artwork and every media transport.
/// Revocation affects retained snapshots too; cookies never enter global cookie storage.
nonisolated final class RequestAuthorization: @unchecked Sendable {
    let id = UUID()
    let baseURL: URL
    private let token: String?
    let cookies: [HTTPCookie]
    private let lock = NSLock()
    private var revoked = false
    private let authenticationProbe = AuthenticationProbe()

    init(baseURL: URL, token: String? = nil, cookies: [HTTPCookie] = []) {
        self.baseURL = baseURL
        self.token = token
        self.cookies = cookies.filter { Self.exactHost($0, url: baseURL) }
    }

    func revoke() {
        lock.withLock { revoked = true }
        Task { await authenticationProbe.cancelAll() }
    }
    var isActive: Bool { lock.withLock { !revoked } }

    static func normalizedURL(_ input: String) -> URL? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    static func origin(_ url: URL) -> String {
        "\(url.scheme ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? (url.scheme == "https" ? 443 : 80))"
    }

    /// HTTP Origin serialization omits default ports, like the browser. The
    /// comparison key above deliberately includes them and is not a wire header:
    /// Django compares Origin against scheme://Host and rejects an added :443.
    static func csrfOrigin(_ url: URL) -> String {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        if let port = url.port, !((url.scheme == "https" && port == 443) || (url.scheme == "http" && port == 80)) {
            components.port = port
        }
        return components.string ?? origin(url)
    }

    static func exactHost(_ cookie: HTTPCookie, url: URL) -> Bool {
        cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == url.host?.lowercased()
    }

    static func matches(_ cookie: HTTPCookie, url: URL, now: Date = .now) -> Bool {
        let path = url.path.isEmpty ? "/" : url.path
        return exactHost(cookie, url: url) && (!cookie.isSecure || url.scheme == "https") &&
            (cookie.expiresDate == nil || cookie.expiresDate! > now) &&
            (path == cookie.path || (path.hasPrefix(cookie.path) &&
             (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/"))))
    }

    func apply(to request: inout URLRequest) throws {
        guard isActive else { throw AppError.unauthorized }
        guard let url = request.url, Self.origin(url) == Self.origin(baseURL),
              url.user == nil, url.password == nil else { throw AppError.invalidURL }
        let matching = cookies.filter { Self.matches($0, url: url) }
        if let token, !token.isEmpty { request.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
        if !matching.isEmpty {
            request.setValue(HTTPCookie.requestHeaderFields(with: matching)["Cookie"], forHTTPHeaderField: "Cookie")
        }
        // Django SessionAuthentication precedes token auth. Unsafe requests need CSRF.
        if !["GET", "HEAD", "OPTIONS", "TRACE"].contains(request.httpMethod ?? "GET"), !cookies.isEmpty {
            guard let csrf = matching.first(where: { $0.name == "csrftoken" }) else { throw AppError.permissionDenied }
            request.setValue(csrf.value, forHTTPHeaderField: "X-CSRFToken")
            request.setValue(Self.csrfOrigin(baseURL), forHTTPHeaderField: "Origin")
            request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        }
    }

    /// Resource permissions, redirects and an unsupported artwork URL returning
    /// the server's HTML app shell are not proof that a login expired. Confirm
    /// ambiguous responses against authenticated ping using this same connection.
    /// The denied operation is never retried or treated as successful.
    func isAuthenticationFailure(_ response: HTTPURLResponse, using session: URLSession) async throws -> Bool {
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
        guard Self.isAuthenticationFailure(response) else { return false }
        if response.statusCode == 401 { return true }
        let pingURL = baseURL.appendingPathComponent("api/ping/")
        if response.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ==
            pingURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) { return true }
        let rejected = try await authenticationProbe.check(authorization: self, session: session)
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
        return rejected
    }

    fileprivate func probeAuthentication(using session: URLSession) async throws -> Bool {
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
        let pingURL = baseURL.appendingPathComponent("api/ping/")
        var request = URLRequest(url: pingURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try apply(to: &request)
        let data: Data
        let result: URLResponse
        do { (data, result) = try await session.data(for: request) }
        catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            guard isActive else { throw CancellationError() }
            return false // An outage cannot prove the saved session expired.
        }
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
        guard let http = result as? HTTPURLResponse else { return false }
        if Self.isAuthenticationFailure(http) { return true }
        if (200...299).contains(http.statusCode),
           let ping = try? JSONDecoder().decode(AuthenticatedPing.self, from: data), ping.response == "pong" {
            return ping.user == nil
        }
        return false
    }

    /// All native requests stop redirects, including same-host gateway handoffs.
    /// Authentication handoffs happen only in the visible sign-in browser.
    static func isAuthenticationFailure(_ response: HTTPURLResponse) -> Bool {
        [401, 403].contains(response.statusCode) || (300...399).contains(response.statusCode) ||
            ((200...299).contains(response.statusCode) && response.mimeType == "text/html")
    }
}

/// One bounded ping per connection while multiple denied resources are in flight.
/// Cancellation removes only that caller; the last caller cancels the transport.
/// No successful result is cached, so a later expiry is always rechecked.
private actor AuthenticationProbe {
    private var task: Task<Void, Never>?
    private var probeID: UUID?
    private var waiters: [UUID: CheckedContinuation<Bool, Error>] = [:]

    func check(authorization: RequestAuthorization, session: URLSession) async throws -> Bool {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled, authorization.isActive else {
                    continuation.resume(throwing: CancellationError()); return
                }
                waiters[waiterID] = continuation
                guard task == nil else { return }
                let id = UUID(); probeID = id
                task = Task {
                    do { complete(.success(try await authorization.probeAuthentication(using: session)), id: id) }
                    catch { complete(.failure(error), id: id) }
                }
            }
        } onCancel: {
            Task { await self.cancel(waiterID) }
        }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        if waiters.isEmpty { task?.cancel(); task = nil; probeID = nil }
    }

    func cancelAll() {
        task?.cancel(); task = nil; probeID = nil
        let pending = waiters; waiters.removeAll()
        for continuation in pending.values { continuation.resume(throwing: CancellationError()) }
    }

    private func complete(_ result: Result<Bool, Error>, id: UUID) {
        guard probeID == id else { return }
        task = nil; probeID = nil
        let pending = waiters; waiters.removeAll()
        for continuation in pending.values { continuation.resume(with: result) }
    }
}

private nonisolated struct AuthenticatedPing: Decodable {
    let response: String?
    let user: Int?
}

nonisolated final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Only documented cookie attributes are serialized; values stay in Keychain.
nonisolated struct StoredCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let expires: Date?
    init(_ cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        secure = cookie.isSecure; expires = cookie.expiresDate
    }
    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if secure { properties[.secure] = "TRUE" }
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)
    }
}

nonisolated struct StoredSession: Codable {
    let serverURL: URL
    let cookies: [StoredCookie]
    let token: String?

    init(serverURL: URL, cookies: [StoredCookie], token: String? = nil) {
        self.serverURL = serverURL; self.cookies = cookies; self.token = token
    }
}
