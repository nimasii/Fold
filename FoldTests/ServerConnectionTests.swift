import Foundation
import AVFoundation
import Testing
@testable import Fold

private final class PlaybackFixtureBundle: NSObject {}

extension DataLayerSuite {
@Suite(.serialized) struct ServerConnectionTests {
    let base = URL(string: "https://umbrel.example:8079")!
    func cookie(_ name: String = "sessionid", domain: String = "umbrel.example", path: String = "/", secure: Bool = true, expires: Date? = nil) -> HTTPCookie {
        var p: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "fixture", .domain: domain, .path: path, .secure: secure ? "TRUE" : "FALSE"]
        if let expires { p[.expires] = expires }
        return HTTPCookie(properties: p)!
    }
    @Test func browserHandoffBoundary() {
        #expect(ServerSignInBrowser.allows(URL(string: "https://umbrel.example:2000/login")!, for: base))
        #expect(!ServerSignInBrowser.allows(URL(string: "https://evil.example/login")!, for: base))
        #expect(!ServerSignInBrowser.allows(URL(string: "https://child.umbrel.example/login")!, for: base))
        #expect(!ServerSignInBrowser.allows(URL(string: "http://umbrel.example:2000/login")!, for: base))
        #expect(!ServerSignInBrowser.allows(URL(string: "https://umbrel.example:9000/login")!, for: base))
        #expect(!ServerSignInBrowser.allows(URL(string: "https://user:pass@umbrel.example/login")!, for: base))
    }
    @Test func normalizedURLRejectsCredentialsAndNonHTTP() {
        for value in ["file:///etc/passwd", "https://a:b@host", "https://host?key=x", "https://host/#secret"] {
            #expect(RequestAuthorization.normalizedURL(value) == nil)
        }
        #expect(RequestAuthorization.normalizedURL("umbrel.example:8079")?.scheme == "https")
    }
    @Test func exactHostPathSecureAndExpiry() throws {
        let auth = RequestAuthorization(baseURL: base, cookies: [cookie(), cookie("parent", domain: ".example"), cookie("other", domain: "evil.example"), cookie("wrongpath", path: "/api/private"), cookie("expired", expires: .distantPast)])
        var request = URLRequest(url: base.appendingPathComponent("api/ping/"))
        try auth.apply(to: &request)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionid=fixture")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(!RequestAuthorization.matches(cookie(path: "/api"), url: base.appendingPathComponent("apievil")))
        #expect(!RequestAuthorization.matches(cookie(), url: URL(string: "http://umbrel.example")!))
    }
    @Test func CSRFForSessionMutations() throws {
        let auth = RequestAuthorization(baseURL: base, cookies: [cookie(), cookie("csrftoken")])
        var request = URLRequest(url: base.appendingPathComponent("api/watched/")); request.httpMethod = "POST"
        try auth.apply(to: &request)
        #expect(request.value(forHTTPHeaderField: "X-CSRFToken") == "fixture")
        #expect(request.value(forHTTPHeaderField: "Origin") == "https://umbrel.example:8079")
        #expect(request.value(forHTTPHeaderField: "Referer") == base.absoluteString)
        let missing = RequestAuthorization(baseURL: base, cookies: [cookie()])
        #expect(throws: AppError.self) { try missing.apply(to: &request) }
    }
    @Test func tokenAndCookiesNeverLeaveOrigin() {
        let auth = RequestAuthorization(baseURL: base, token: "fixture-token", cookies: [cookie()])
        for target in ["https://evil.example", "https://umbrel.example:2000", "http://umbrel.example:8079"] {
            var request = URLRequest(url: URL(string: target)!)
            #expect(throws: AppError.self) { try auth.apply(to: &request) }
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }
    @Test func revokedSnapshotCannotAuthorize() {
        let auth = RequestAuthorization(baseURL: base, cookies: [cookie()]); auth.revoke()
        var request = URLRequest(url: base)
        #expect(throws: AppError.self) { try auth.apply(to: &request) }
    }
    @Test func cookiePersistenceRoundtrip() throws {
        let stored = StoredCookie(cookie())
        let data = try JSONEncoder().encode([stored])
        let restored = try JSONDecoder().decode([StoredCookie].self, from: data).compactMap(\.cookie)
        #expect(restored.count == 1)
        #expect(restored.first?.isSecure == true)
        #expect(restored.first?.value == "fixture")
    }
    @Test func browserSessionValidatesOnlyPingAndDoesNotFetchToken() async throws {
        let (client, state) = MockResponse.makeAPIClient()
        MockResponse.setUp(json: ["response": "pong", "user": 1])
        let repo = AuthRepositoryImpl(apiClient: client, authState: state)
        try await repo.connectSession(serverURL: base, cookies: [cookie(), cookie("csrftoken")])
        #expect(MockURLProtocol.lastRequest?.url?.path == "/api/ping")
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=fixture") == true)
        #expect(state.isAuthenticated)
        #expect(state.token == nil)
        let snapshot = state.authorization
        state.handleUnauthorized()
        #expect(snapshot?.isActive == false)
        #expect(!state.isAuthenticated)
    }
    @Test func gatewayCookieAloneDoesNotReplaceWorkingCredentials() async {
        let (client, state) = MockResponse.makeAPIClient()
        let old = state.authorization
        MockResponse.setUp(statusCode: 403, json: ["detail": "Authentication credentials were not provided"])
        let repo = AuthRepositoryImpl(apiClient: client, authState: state)
        await #expect(throws: AppError.self) { try await repo.connectSession(serverURL: base, cookies: [cookie("umbrel")]) }
        #expect(state.authorization === old)
        #expect(state.token == "test-token")
    }
    @Test func sessionAPIWritesHaveCSRFAndNoToken() async throws {
        let state = MockResponse.makeAuthState()
        try state.setSession(cookies: [cookie(), cookie("csrftoken")], serverURL: base)
        let (client, _) = MockResponse.makeAPIClient(authState: state)
        MockResponse.setUp(statusCode: 204, data: Data())
        try await client.requestVoid(endpoint: .videoProgress(id: "fixture"), body: VideoProgressDTO(position: 1))
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-CSRFToken") == "fixture")
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }
    @Test func HTMLAndRedirectsRequireRelogin() async {
        let (client, _) = MockResponse.makeAPIClient()
        MockResponse.setUp(statusCode: 302, data: Data())
        await #expect(throws: AppError.self) { let _: PingDTO = try await client.request(endpoint: .ping) }
        #expect(RequestAuthorization.isAuthenticationFailure(HTTPURLResponse(url: base, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"text/html"])!))
    }
    @Test func sessionAndLegacyTokenPersistWithoutChangingAuthenticationMode() throws {
        let keychain = KeychainService(inMemory: true)
        let state = AuthState(keychainService: keychain)
        state.setCredentials(token: "fixture-token", serverURL: base.absoluteString)
        let legacy = AuthState(keychainService: keychain)
        #expect(legacy.token == "fixture-token")
        #expect(legacy.isAuthenticated)
        try state.setSession(cookies: [cookie(), cookie("csrftoken")], serverURL: base)
        let restored = AuthState(keychainService: keychain)
        #expect(restored.token == nil)
        #expect(restored.authorization?.cookies.count == 2)
        #expect(restored.baseURL == base)
        #expect(keychain.load(for: .authToken) == nil)
        try state.setExistingToken("existing-fixture-token", serverURL: base)
        let fallback = AuthState(keychainService: keychain)
        #expect(fallback.token == "existing-fixture-token")
        #expect(fallback.authorization?.cookies.isEmpty == true)
    }

    @Test func expiredSessionRoutesToLoginAndCanReconnect() async throws {
        let state = AuthState(keychainService: KeychainService(inMemory: true))
        try state.setSession(cookies: [cookie(), cookie("csrftoken")], serverURL: base)
        let old = state.authorization
        let router = AppRouter(authState: state)
        router.onLoginSuccess()
        let (client, _) = MockResponse.makeAPIClient(authState: state)
        MockResponse.setUp(statusCode: 403, data: Data())
        var message: String?
        do { let _: PingDTO = try await client.request(endpoint: .ping); Issue.record("Expected expired session") }
        catch { router.handleError(error, errorMessage: &message) }
        #expect(router.appState == .login)
        #expect(old?.isActive == false)
        #expect(state.reloginURL == base.absoluteString)
        MockResponse.setUp(json: ["response":"pong", "user":1])
        try await AuthRepositoryImpl(apiClient: client, authState: state).connectSession(serverURL: base, cookies: [cookie(), cookie("csrftoken")])
        router.onLoginSuccess()
        #expect(router.appState == .authenticated)
        #expect(state.authorization?.id != old?.id)
    }

    @Test func preloaderAuthenticatesHEADAndByteRangesWithSameSession() async throws {
        let preloader = VideoCachePreloader.shared
        await preloader.clear()
        VideoCachePreloader.testSessionConfigurationOverride = MockResponse.makeConfiguration()
        defer { VideoCachePreloader.testSessionConfigurationOverride = nil; MockResponse.tearDown() }
        let requests = SendableBox<[URLRequest]>([])
        MockURLProtocol.requestHandler = { request in
            requests.set(requests.current + [request])
            let head = request.httpMethod == "HEAD"
            return (HTTPURLResponse(url: request.url!, statusCode: head ? 200 : 206, httpVersion: nil,
                headerFields: ["Content-Length":"32", "Content-Type":"video/mp4", "Content-Range":"bytes 0-31/32"])!, head ? Data() : Data(repeating: 1, count: 32))
        }
        await preloader.startPreloadWithRetry(videoId: "session-range-fixture", url: base.appendingPathComponent("media/fixture.mp4"), token: "",
            authorization: RequestAuthorization(baseURL: base, cookies: [cookie()]), maxRetries: 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while preloader.store.cachedByteCount(videoId: "session-range-fixture") < 32 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(preloader.store.cachedByteCount(videoId: "session-range-fixture") == 32)
        #expect(requests.current.contains { $0.httpMethod == "HEAD" })
        #expect(requests.current.contains { $0.value(forHTTPHeaderField: "Range") == "bytes=0-\(CacheStore.computePrefixSize(totalSize: 32) - 1)" })
        for request in requests.current {
            #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionid=fixture")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
        await preloader.clear()
    }

    @Test(.timeLimit(.minutes(1)))
    func avPlayerStartsAndSeeksUsingAuthenticatedRanges() async throws {
        let file = try #require(Bundle(for: PlaybackFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4"))
        let bytes = try Data(contentsOf: file)
        let requests = SendableBox<[URLRequest]>([])
        MockResponse.tearDown()
        defer { MockResponse.tearDown() }
        MockURLProtocol.requestHandler = { request in
            requests.set(requests.current + [request])
            let range = request.value(forHTTPHeaderField: "Range")?.replacingOccurrences(of: "bytes=", with: "").split(separator: "-")
            let lower = min(Int(range?.first ?? "0") ?? 0, bytes.count - 1)
            let upper = min(range?.count == 2 ? Int(range![1]) ?? bytes.count - 1 : bytes.count - 1, bytes.count - 1)
            let body = request.httpMethod == "HEAD" ? Data() : bytes.subdata(in: lower..<(upper + 1))
            let headers = ["Content-Type":"video/mp4", "Accept-Ranges":"bytes", "Content-Length":"\(request.httpMethod == "HEAD" ? bytes.count : body.count)", "Content-Range":"bytes \(lower)-\(upper)/\(bytes.count)"]
            return (HTTPURLResponse(url: request.url!, statusCode: request.httpMethod == "HEAD" ? 200 : 206, httpVersion: nil, headerFields: headers)!, body)
        }
        let url = base.appendingPathComponent("media/fixture.mp4")
        let auth = RequestAuthorization(baseURL: base, cookies: [cookie()])
        let loader = CachingResourceLoader(videoId: "actual-playback-fixture", originalURL: url, token: "", authorization: auth,
            sessionConfiguration: MockResponse.makeConfiguration(), store: CacheStore(), isPreloadingCheck: { _ in false })
        let asset = AVURLAsset(url: try #require(CachingResourceLoader.cachingURL(from: url)))
        asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
        #expect(try await asset.load(.isPlayable))
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        player.play()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while player.currentTime().seconds < 0.2 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(player.currentTime().seconds >= 0.2)
        #expect(await player.seek(to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero))
        #expect(player.currentTime().seconds >= 0.9)
        #expect(requests.current.contains { $0.value(forHTTPHeaderField: "Range") != nil })
        for request in requests.current {
            #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionid=fixture")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
        auth.revoke()
    }

}
}
