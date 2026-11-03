import Foundation
import Testing
@testable import Fold

extension DataLayerSuite {
@MainActor @Suite(.serialized) struct MediaSessionPersistenceTests {
    private let base = URL(string: "https://example.com")!

    private func connected(_ mode: String = "session") throws -> (KeychainService, AuthState, AppRouter) {
        let keychain = KeychainService(inMemory: true)
        let state = AuthState(keychainService: keychain)
        if mode == "session" {
            let cookies = ["sessionid", "csrftoken"].map {
                HTTPCookie(properties: [.name: $0, .value: "synthetic", .domain: "example.com", .path: "/",
                    .expires: Date().addingTimeInterval(172800)])!
            }
            try state.setSession(cookies: cookies, serverURL: base)
        } else { try state.setExistingToken("SYNTHETIC_EXISTING_TOKEN", serverURL: base) }
        let router = AppRouter(authState: state); router.onLoginSuccess()
        return (keychain, state, router)
    }

    private nonisolated static func isPing(_ request: URLRequest) -> Bool {
        request.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/ping"
    }
    private nonisolated static func response(_ url: URL, _ status: Int, html: Bool = false) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": html ? "text/html" : "application/json"])!
    }
    private func installPing(_ mode: String, log: MediaSessionRequestLog) {
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            guard Self.isPing(request) else { throw URLError(.badURL) }
            switch mode {
            case "network": throw URLError(.notConnectedToInternet)
            case "503": return (Self.response(request.url!, 503, html: true), Data())
            case "malformed": return (Self.response(request.url!, 200), Data("invalid".utf8))
            case "expired": return (Self.response(request.url!, 403), Data())
            default: return (Self.response(request.url!, 200), MockResponse.json(["response": "pong", "user": 7]))
            }
        }
    }

    @Test(arguments: [401, 403, 302, 200], ["session", "token"])
    func mediaFailurePreservesValidSavedLogin(_ status: Int, _ mode: String) async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router) = try connected(mode)
        let original = try #require(state.authorization)
        let log = MediaSessionRequestLog(); installPing("valid", log: log)
        let url = base.appendingPathComponent("video.mp4")
        let loader = CachingResourceLoader(videoId: "retained", originalURL: url, token: "", authorization: original,
            sessionConfiguration: MockResponse.makeConfiguration(), store: CacheStore(), isPreloadingCheck: { _ in false })
        #expect(await loader.handleUnauthorizedIfNeeded(response: Self.response(url, status, html: status == 200)))
        #expect(state.authorization === original && original.isActive)
        #expect(router.appState == .authenticated && AuthState(keychainService: keychain).isAuthenticated)
        #expect(log.requests.count == 1 && log.requests.allSatisfy(Self.isPing))
    }

    @Test(arguments: ["network", "503", "malformed"])
    func unavailableVerificationPreservesSavedLogin(_ mode: String) async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router) = try connected()
        let original = try #require(state.authorization)
        let log = MediaSessionRequestLog(); installPing(mode, log: log)
        let session = URLSession(configuration: MockResponse.makeConfiguration())
        defer { session.invalidateAndCancel() }
        #expect(try await original.rejectsMediaResponse(Self.response(base.appendingPathComponent("video.mp4"), 403), using: session))
        #expect(state.authorization === original && AuthState(keychainService: keychain).isAuthenticated)
        #expect(router.appState == .authenticated)
    }

    @Test(arguments: [401, 403, 302, 200])
    func confirmedExpiryStillClearsOnlyCurrentConnection(_ status: Int) async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router) = try connected()
        let original = try #require(state.authorization)
        let log = MediaSessionRequestLog(); installPing("expired", log: log)
        let session = URLSession(configuration: MockResponse.makeConfiguration())
        defer { session.invalidateAndCancel() }
        #expect(try await original.rejectsMediaResponse(Self.response(base.appendingPathComponent("video.mp4"), status, html: status == 200), using: session))
        #expect(!state.isAuthenticated && !original.isActive && router.appState == .login)
        #expect(!AuthState(keychainService: keychain).isAuthenticated && log.requests.count == 1)
    }

    @Test(arguments: [true, false])
    func preloaderRejectsHEADOrRangeWithoutErasingValidLogin(_ headFailure: Bool) async throws {
        defer { VideoCachePreloader.testSessionConfigurationOverride = nil; MockResponse.tearDown() }
        let (keychain, state, router) = try connected()
        let original = try #require(state.authorization)
        let log = MediaSessionRequestLog()
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            if Self.isPing(request) { return (Self.response(request.url!, 200), MockResponse.json(["response": "pong", "user": 7])) }
            if request.httpMethod == "HEAD" && !headFailure {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "video/mp4", "Content-Length": "32"])!, Data())
            }
            return (Self.response(request.url!, 403), Data())
        }
        let preloader = VideoCachePreloader.shared
        await preloader.clear()
        VideoCachePreloader.testSessionConfigurationOverride = MockResponse.makeConfiguration()
        await preloader.startPreloadWithRetry(videoId: "preload-retained", url: base.appendingPathComponent("video.mp4"),
            token: "", authorization: original, maxRetries: 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            let active = await preloader.isPreloading(videoId: "preload-retained")
            if !log.requests.isEmpty && !active { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(log.requests.contains(where: Self.isPing))
        #expect(state.authorization === original && AuthState(keychainService: keychain).isAuthenticated)
        #expect(router.appState == .authenticated)
        #expect(preloader.store.cachedByteCount(videoId: "preload-retained") == 0)
        await preloader.clear()
    }

    @Test(arguments: ["valid", "expired", "network"])
    func offlineFailureVerifiesBeforeErasingSavedLogin(_ ping: String) async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router) = try connected()
        let original = try #require(state.authorization)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaSession-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = MediaSessionRequestLog(); installPing(ping, log: log)
        let configuration = MockResponse.makeConfiguration()
        configuration.protocolClasses = [MediaSessionOfflineProtocol.self]
        let library = OfflineLibrary(authState: state, root: root, configuration: configuration)
        let id = try #require(library.enqueue(TestData.video()))
        let record = try #require(library.records.first)
        let staged = root.appendingPathComponent("denied.fixture")
        try Data("denied".utf8).write(to: staged)
        library.finish(id.uuidString + "/" + record.attempt!.uuidString,
            response: Self.response(base.appendingPathComponent("video.mp4"), 403), staged: staged)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while library.records.first?.status == .downloading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #expect(library.records.first?.status != .ready)
        if ping == "expired" {
            #expect(!state.isAuthenticated && router.appState == .login)
            #expect(!AuthState(keychainService: keychain).isAuthenticated)
        } else {
            #expect(state.authorization === original && router.appState == .authenticated)
            #expect(AuthState(keychainService: keychain).isAuthenticated)
        }
        library.pauseAll()
    }

    @Test(arguments: ["valid", "expired", "network"])
    func proxyDeniesMediaWithoutErasingAnUnrejectedConnection(_ ping: String) async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router) = try connected()
        let original = try #require(state.authorization)
        let log = MediaSessionRequestLog()
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            if Self.isPing(request) {
                if ping == "network" { throw URLError(.notConnectedToInternet) }
                return (Self.response(request.url!, ping == "expired" ? 403 : 200), MockResponse.json(["response": "pong", "user": 7]))
            }
            return (Self.response(request.url!, 403), Data())
        }
        let proxy = AuthProxy(token: "", serverBaseURL: base, authorization: original,
            sessionConfiguration: MockResponse.makeConfiguration())
        try await proxy.start()
        let url = try #require(await proxy.proxyURL(for: base.appendingPathComponent("video.mp4")))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        _ = try? await session.data(from: url)
        session.invalidateAndCancel()
        await proxy.stop()
        #expect(log.requests.contains(where: Self.isPing))
        if ping == "expired" { #expect(!state.isAuthenticated && router.appState == .login) }
        else { #expect(state.authorization === original && router.appState == .authenticated) }
    }

    @Test(arguments: [false, true])
    func cancelledOrReplacedMediaProbeCannotEraseSavedLogin(_ replace: Bool) async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router) = try connected()
        let original = try #require(state.authorization)
        let log = MediaSessionRequestLog()
        MockURLProtocol.delayedHandler = { request in
            log.append(request)
            return (Self.response(request.url!, 403), Data(), 0.3)
        }
        let session = URLSession(configuration: MockResponse.makeConfiguration())
        defer { session.invalidateAndCancel() }
        let task = Task { try await original.rejectsMediaResponse(Self.response(base.appendingPathComponent("video.mp4"), 403), using: session) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while log.requests.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!log.requests.isEmpty)
        if replace { try state.setExistingToken("SYNTHETIC_REPLACEMENT", serverURL: base); router.onLoginSuccess() }
        else { task.cancel() }
        _ = try? await task.value
        #expect(state.isAuthenticated && router.appState == .authenticated)
        #expect(AuthState(keychainService: keychain).isAuthenticated)
    }

    @Test func unscopedAndOldNotificationsCannotClearCurrentLogin() throws {
        let (_, state, router) = try connected()
        let original = state.authorization
        NotificationCenter.default.post(name: .taAuthUnauthorized, object: nil)
        NotificationCenter.default.post(name: .taAuthUnauthorized, object: nil, userInfo: ["authorizationID": UUID()])
        #expect(state.authorization === original && router.appState == .authenticated)
    }

    @Test func unexpectedAccountVerificationBodyCannotEraseSavedLogin() async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router) = try connected()
        let original = state.authorization
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaAccount-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (api, _) = MockResponse.makeAPIClient(authState: state)
        let library = OfflineLibrary(authState: state, root: root.appendingPathComponent("Downloads"), configuration: MockResponse.makeConfiguration())
        let history = PlaybackCoordinator(auth: state, api: api, library: library, root: root.appendingPathComponent("History"), monitorNetwork: false)
        defer { history.shutdown(); library.pauseAll() }
        MockResponse.setUp(json: ["response": "maintenance", "user": 7])
        do { _ = try await history.confirmAccount(); Issue.record("Unexpected ping must not confirm an account") }
        catch { var message: String?; router.handleError(error, errorMessage: &message) }
        #expect(state.authorization === original && !state.accountConfirmed)
        #expect(AuthState(keychainService: keychain).isAuthenticated && router.appState == .authenticated)
    }

    @Test func expirySurvivesSavedSessionRestorationWithoutBeingExtended() throws {
        let (keychain, state, _) = try connected()
        let restored = AuthState(keychainService: keychain)
        let saved = try #require(state.authorization?.cookies.first)
        let cookie = try #require(restored.authorization?.cookies.first)
        #expect(saved.expiresDate == cookie.expiresDate)
        let cutoff = try #require(cookie.expiresDate)
        #expect(RequestAuthorization.matches(cookie, url: base, now: cutoff.addingTimeInterval(-1)))
        #expect(!RequestAuthorization.matches(cookie, url: base, now: cutoff.addingTimeInterval(1)))
    }
}
}

private nonisolated final class MediaSessionRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { values.append(request) } }
    var requests: [URLRequest] { lock.withLock { values } }
}

private final class MediaSessionOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.path.contains("api/ping") == true, let handler = MockURLProtocol.requestHandler else { return }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
