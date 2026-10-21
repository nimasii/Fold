import Foundation
import Testing
@testable import Fold

extension DataLayerSuite {
@MainActor @Suite(.serialized) struct QueueAuthorizationRegressionTests {
    private let base = URL(string: "https://queue.fixture.example")!

    private func connected(_ mode: String = "token") throws -> (KeychainService, AuthState, AppRouter, APIClient, DownloadQueueViewModel) {
        let keychain = KeychainService(inMemory: true)
        let state = AuthState(keychainService: keychain)
        if mode == "session" {
            let cookies = ["sessionid", "csrftoken"].map {
                HTTPCookie(properties: [.name: $0, .value: "synthetic", .domain: "queue.fixture.example", .path: "/", .secure: "TRUE"])!
            }
            try state.setSession(cookies: cookies, serverURL: base)
        } else { try state.setExistingToken("QUEUE_AUTH_FIXTURE_TOKEN", serverURL: base) }
        let router = AppRouter(authState: state); router.onLoginSuccess()
        let (api, _) = MockResponse.makeAPIClient(authState: state)
        let repo = DownloadRepositoryImpl(apiClient: api, authState: state)
        return (keychain, state, router, api, DownloadQueueViewModel(downloadRepository: repo, router: router))
    }

    @Test(arguments: ["token", "session"])
    func forbiddenQueueEntryRetainsConnectionAcrossFiltersAndRelaunch(_ mode: String) async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router, _, vm) = try connected(mode)
        let original = state.authorization
        MockURLProtocol.requestHandler = { request in
            let ping = request.url!.path.hasSuffix("ping") || request.url!.path.hasSuffix("ping/")
            let body: [String: Any] = ping ? ["response": "pong", "user": 7] : ["detail": "You do not have permission to perform this action."]
            let response = HTTPURLResponse(url: request.url!, statusCode: ping ? 200 : 403, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            return (response, MockResponse.json(body))
        }
        for _ in 0..<3 {
            router.selectedTab = .queue
            for filter in ["pending", "ignore"] {
                vm.filter = filter
                await vm.onFilterChanged()
                #expect(vm.errorMessage != nil)
                #expect(state.authorization === original)
                #expect(state.isAuthenticated)
                #expect(router.appState == .authenticated)
            }
            await vm.checkNotifications()
            router.selectedTab = .library
        }
        let restored = AuthState(keychainService: keychain)
        #expect(restored.isAuthenticated)
        #expect(restored.baseURL == base)
        #expect(original?.isActive == true)
    }
    private func endpoint(_ name: String) -> APIEndpoint {
        switch name {
        case "pending": .downloadList(page: 1, filter: "pending")
        case "ignore": .downloadList(page: 1, filter: "ignore")
        case "notifications": .notifications
        case "start": .startDownload
        case "rescan": .rescanSubscriptions
        case "kill": .killTask(id: "fixture-task")
        case "update": .updateDownloadStatus(id: "fixture-video")
        case "add": .addToDownloadQueue
        default: .deleteDownload(id: "fixture-video")
        }
    }

    private nonisolated static func reply(_ request: URLRequest, _ code: Int, _ body: [String: Any] = [:], contentType: String = "application/json") -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": contentType])!,
         try! JSONSerialization.data(withJSONObject: body))
    }
    private nonisolated static func isPing(_ request: URLRequest) -> Bool {
        request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("api/ping")
    }

    @Test(arguments: ["pending", "ignore", "notifications", "start", "rescan", "kill", "update", "add", "delete"])
    func permissionDenialNeverRetriesMutationOrClearsSession(_ name: String) async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router, api, _) = try connected("session")
        let original = state.authorization
        let log = QueueRequestLog()
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            return Self.isPing(request) ? Self.reply(request, 200, ["response": "pong", "user": 7]) :
                Self.reply(request, 403, ["detail": "You do not have permission to perform this action."])
        }
        do { try await api.requestVoid(endpoint: endpoint(name)); Issue.record("Denied request succeeded") }
        catch let error as AppError { if case .permissionDenied = error {} else { Issue.record("Wrong error: \(error)") } }
        #expect(state.authorization === original && original?.isActive == true)
        #expect(router.appState == .authenticated)
        #expect(AuthState(keychainService: keychain).isAuthenticated)
        #expect(log.requests.filter { Self.isPing($0) }.count == 1)
        #expect(log.requests.filter { !Self.isPing($0) }.count == 1)
        for request in log.requests {
            #expect(request.url?.host == base.host)
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=synthetic") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }

    @Test(arguments: ["pending", "ignore", "notifications", "start", "rescan", "kill", "update", "add", "delete"])
    func genuine401ClearsOnlyCurrentSessionWithoutProbe(_ name: String) async throws {
        defer { MockResponse.tearDown() }
        let (keychain, state, router, api, _) = try connected()
        let original = state.authorization; let log = QueueRequestLog()
        MockURLProtocol.requestHandler = { request in log.append(request); return Self.reply(request, 401, ["detail": "Invalid token."]) }
        do { try await api.requestVoid(endpoint: endpoint(name)); Issue.record("Expected authentication rejection") }
        catch let error as AppError { if case .unauthorized = error {} else { Issue.record("Wrong error") } }
        #expect(router.appState == .login && !state.isAuthenticated)
        #expect(original?.isActive == false)
        #expect(!AuthState(keychainService: keychain).isAuthenticated)
        #expect(log.requests.count == 1)
    }

    @Test(arguments: [401, 403, 302, 200])
    func deniedResourceWithRejectedAuthenticatedPingStillSignsOut(_ status: Int) async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, _, vm) = try connected("session")
        let log = QueueRequestLog()
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            if Self.isPing(request) { return Self.reply(request, status, ["response": "pong", "user": NSNull()]) }
            return Self.reply(request, 403, ["detail": "Authentication credentials were not provided."])
        }
        await vm.loadDownloads()
        #expect(!state.isAuthenticated && router.appState == .login)
        #expect(log.requests.count == 2) // A denied ping must not recurse.
    }

    @Test(arguments: [400, 404, 429, 500, 503])
    func nonAuthenticationErrorsNeverRevokeConnection(_ status: Int) async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, _, vm) = try connected()
        let original = state.authorization; let log = QueueRequestLog()
        MockURLProtocol.requestHandler = { request in log.append(request); return Self.reply(request, status, ["detail": "Fixture unavailable"], contentType: "text/html") }
        await vm.loadDownloads()
        #expect(state.authorization === original && state.isAuthenticated)
        #expect(router.appState == .authenticated && vm.errorMessage != nil)
        #expect(log.requests.count == 1)
    }

    @Test(arguments: ["network", "503", "malformed"])
    func unavailableRevalidationPreservesCredentialsAndStillDeniesAction(_ mode: String) async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, api, _) = try connected()
        let original = state.authorization
        MockURLProtocol.requestHandler = { request in
            if Self.isPing(request) {
                if mode == "network" { throw URLError(.notConnectedToInternet) }
                return Self.reply(request, mode == "503" ? 503 : 200, ["message": "maintenance"])
            }
            return Self.reply(request, 403, ["detail": "Forbidden"])
        }
        do { try await api.requestVoid(endpoint: .startDownload); Issue.record("Action must stay denied") }
        catch let error as AppError { if case .permissionDenied = error {} else { Issue.record("Wrong error") } }
        #expect(state.authorization === original && router.appState == .authenticated)
    }

    @Test func missingCSRFDoesNotEraseAValidReadSession() async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, api, _) = try connected("session")
        let cookie = HTTPCookie(properties: [.name: "sessionid", .value: "synthetic", .domain: base.host!, .path: "/"])!
        try state.setSession(cookies: [cookie], serverURL: base)
        let original = state.authorization
        do { try await api.requestVoid(endpoint: .startDownload); Issue.record("Missing CSRF must deny mutation") }
        catch let error as AppError { if case .permissionDenied = error {} else { Issue.record("Wrong error") } }
        #expect(state.authorization === original && router.appState == .authenticated)
        #expect(MockURLProtocol.lastRequest == nil)
    }

    @Test func cancellationAndLate401CannotSignOutReplacementConnection() async throws {
        defer { MockResponse.tearDown() }
        for cancel in [false, true] {
            let (keychain, state, router, _, vm) = try connected()
            let log = QueueRequestLog()
            MockURLProtocol.delayedHandler = { request in
                log.append(request)
                let (response, data) = Self.reply(request, 401)
                return (response, data, 0.25)
            }
            let load = Task { await vm.loadDownloads() }
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while log.requests.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(!log.requests.isEmpty)
            if cancel { load.cancel() }
            let other = URL(string: "https://replacement.fixture.example")!
            try state.setExistingToken("REPLACEMENT_FIXTURE_TOKEN", serverURL: other)
            router.onLoginSuccess()
            let replacement = state.authorization
            await load.value
            #expect(state.authorization === replacement && state.isAuthenticated)
            #expect(AuthState(keychainService: keychain).baseURL == other)
            #expect(router.appState == .authenticated && vm.errorMessage == nil)
        }
    }

    @Test func concurrent403sShareOneProbeAndOneCancellationDoesNotCancelOtherWaiters() async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, api, _) = try connected()
        let log = QueueRequestLog()
        MockURLProtocol.delayedHandler = { request in
            log.append(request)
            let ping = Self.isPing(request)
            let (response, data) = Self.reply(request, ping ? 200 : 403, ping ? ["response": "pong", "user": 7] : [:])
            return (response, data, ping ? 0.3 : 0.01)
        }
        let loads = (0..<12).map { _ in Task { () -> String in
            do { try await api.requestVoid(endpoint: .downloadList(page: 1, filter: "pending")); return "unexpected" }
            catch is CancellationError { return "cancelled" }
            catch let error as AppError { if case .permissionDenied = error { return "denied" }; return "wrong" }
            catch { return "wrong" }
        } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !log.requests.contains(where: Self.isPing) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        loads[0].cancel()
        #expect(await loads[0].value == "cancelled")
        for load in loads.dropFirst() { #expect(await load.value == "denied") }
        #expect(log.requests.filter(Self.isPing).count == 1)
        #expect(state.isAuthenticated && router.appState == .authenticated)
    }

    @Test func cancellationOrReplacementDuringPingDoesNotRevokeConnection() async throws {
        defer { MockResponse.tearDown() }
        for cancel in [false, true] {
            let (_, state, router, _, vm) = try connected()
            let log = QueueRequestLog()
            MockURLProtocol.delayedHandler = { request in
                log.append(request)
                let (response, data) = Self.reply(request, 403)
                return (response, data, Self.isPing(request) ? 2 : 0.01)
            }
            let load = Task { await vm.loadDownloads() }
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !log.requests.contains(where: Self.isPing) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(log.requests.contains(where: Self.isPing))
            if cancel { load.cancel() }
            else { try state.setExistingToken("NEW_FIXTURE_TOKEN", serverURL: base); router.onLoginSuccess() }
            let current = state.authorization
            let cancelledAt = ContinuousClock.now
            await load.value
            #expect(ContinuousClock.now - cancelledAt < .seconds(1))
            #expect(state.authorization === current && current?.isActive == true)
            #expect(router.appState == .authenticated && vm.errorMessage == nil)
        }
    }

    @Test(arguments: [200, 401])
    func deniedArtworkUsesSameSessionValidationWithoutSigningOutValidAccount(_ pingStatus: Int) async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, _, _) = try connected()
        let original = state.authorization; let log = QueueRequestLog()
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            return Self.isPing(request) ? Self.reply(request, pingStatus, ["response": "pong", "user": 7]) : Self.reply(request, 403)
        }
        let cache = ImageCache(configuration: MockResponse.makeConfiguration())
        let image = await cache.image(for: base.appendingPathComponent("cache/download/fixture.jpg"), token: nil, authorization: original)
        #expect(image == nil)
        if pingStatus == 200 { #expect(state.authorization === original && router.appState == .authenticated) }
        else { #expect(!state.isAuthenticated && router.appState == .login) }
        #expect(log.requests.count == 2)
        await cache.clear()
    }

    @Test func cancelledArtworkCannotPublishLateAuthenticationFailure() async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, _, _) = try connected()
        let original = state.authorization; let log = QueueRequestLog()
        MockURLProtocol.delayedHandler = { request in
            log.append(request)
            let (response, data) = Self.reply(request, 401)
            return (response, data, 0.3)
        }
        let cache = ImageCache(configuration: MockResponse.makeConfiguration())
        let load = Task { await cache.image(for: base.appendingPathComponent("cache/cancelled.jpg"), token: nil, authorization: original) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while log.requests.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        load.cancel()
        _ = await load.value
        try await Task.sleep(for: .milliseconds(350))
        #expect(state.authorization === original && state.isAuthenticated)
        #expect(router.appState == .authenticated)
        await cache.clear()
    }

    @Test(arguments: [200, 302, 403])
    func ambiguousArtworkResponseWithValidPingNeverRevokesSession(_ status: Int) async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, _, _) = try connected("session")
        let original = state.authorization; let log = QueueRequestLog()
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            if Self.isPing(request) { return Self.reply(request, 200, ["response": "pong", "user": 7]) }
            return Self.reply(request, status, ["shell": "server application"], contentType: status == 200 ? "text/html" : "application/json")
        }
        let cache = ImageCache(configuration: MockResponse.makeConfiguration())
        #expect(await cache.image(for: base.appendingPathComponent("media/thumb/video/fixture.jpg"), token: nil, authorization: original) == nil)
        #expect(state.authorization === original && router.appState == .authenticated)
        #expect(log.requests.count == 2)
        await cache.clear()
    }

    @Test func successfulRevalidationIsNotCachedAcrossLaterExpiry() async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, api, _) = try connected()
        let log = QueueRequestLog()
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            if Self.isPing(request) { return Self.reply(request, 200, ["response": "pong", "user": 7]) }
            return Self.reply(request, 403)
        }
        do { try await api.requestVoid(endpoint: .startDownload); Issue.record("Denied action accepted") }
        catch let error as AppError { if case .permissionDenied = error {} else { Issue.record("Wrong error") } }
        MockURLProtocol.requestHandler = { request in log.append(request); return Self.reply(request, 403) }
        do { try await api.requestVoid(endpoint: .startDownload); Issue.record("Expired session accepted") }
        catch let error as AppError { if case .unauthorized = error {} else { Issue.record("Wrong error") } }
        #expect(log.requests.filter(Self.isPing).count == 2)
        #expect(!state.isAuthenticated && router.appState == .login)
    }

    @Test func sharedArtworkConsumerSurvivesAnotherConsumerCancelling() async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, _, _) = try connected()
        let original = state.authorization
        let file = try #require(Bundle(for: QueueFixtureBundle.self).url(forResource: "offline-thumbnail", withExtension: "png"))
        let bytes = try Data(contentsOf: file)
        let log = QueueRequestLog()
        MockURLProtocol.delayedHandler = { request in
            log.append(request)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "image/png"])!, bytes, 0.3)
        }
        let cache = ImageCache(configuration: MockResponse.makeConfiguration())
        let url = base.appendingPathComponent("cache/shared.jpg")
        let first = Task { await cache.image(for: url, token: nil, authorization: original) }
        let second = Task { await cache.image(for: url, token: nil, authorization: original) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while log.requests.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(20))
        first.cancel()
        #expect(await first.value == nil)
        #expect(await second.value != nil)
        #expect(await cache.image(for: url, token: nil, authorization: original) != nil)
        #expect(log.requests.count == 1)
        #expect(state.authorization === original && router.appState == .authenticated)
        await cache.clear()
    }

    @Test func HTMLApplicationShellNeverCountsAsSuccessfulMutation() async throws {
        defer { MockResponse.tearDown() }
        let (_, state, router, api, _) = try connected()
        let original = state.authorization; let log = QueueRequestLog()
        MockURLProtocol.requestHandler = { request in
            log.append(request)
            if Self.isPing(request) { return Self.reply(request, 200, ["response": "pong", "user": 7]) }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "text/html"])!, Data("<!doctype html><title>Server app shell</title>".utf8))
        }
        do { try await api.requestVoid(endpoint: .startDownload); Issue.record("HTML incorrectly accepted as an API mutation") }
        catch let error as AppError { if case .decoding = error {} else { Issue.record("Wrong error") } }
        #expect(state.authorization === original && router.appState == .authenticated)
        #expect(log.requests.count == 2)
    }

}
}

private nonisolated final class QueueRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { storage.append(request) } }
    var requests: [URLRequest] { lock.withLock { storage } }
}

private final class QueueFixtureBundle: NSObject {}
