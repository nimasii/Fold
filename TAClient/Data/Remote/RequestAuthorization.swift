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

    init(baseURL: URL, token: String? = nil, cookies: [HTTPCookie] = []) {
        self.baseURL = baseURL
        self.token = token
        self.cookies = cookies.filter { Self.exactHost($0, url: baseURL) }
    }

    func revoke() { lock.withLock { revoked = true } }
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
            guard let csrf = matching.first(where: { $0.name == "csrftoken" }) else { throw AppError.unauthorized }
            request.setValue(csrf.value, forHTTPHeaderField: "X-CSRFToken")
            request.setValue(Self.csrfOrigin(baseURL), forHTTPHeaderField: "Origin")
            request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        }
    }

    /// All native requests stop redirects, including same-host gateway handoffs.
    /// Authentication handoffs happen only in the visible sign-in browser.
    static func isAuthenticationFailure(_ response: HTTPURLResponse) -> Bool {
        [401, 403].contains(response.statusCode) || (300...399).contains(response.statusCode) ||
            ((200...299).contains(response.statusCode) && response.mimeType == "text/html")
    }
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
