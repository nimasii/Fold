import Foundation
import SwiftUI
import Testing
@testable import TAClient

@MainActor
struct SessionRestorationTests {
    private let url = URL(string: "https://fixture.example:8079")!

    private func storedSession() throws -> (KeychainService, AuthState, AppRouter) {
        let keychain = KeychainService(inMemory: true)
        let cookie = HTTPCookie(properties: [.name: "sessionid", .value: "synthetic", .domain: "fixture.example", .path: "/", .secure: "TRUE"])!
        try AuthState(keychainService: keychain).setSession(cookies: [cookie], serverURL: url)
        let restored = AuthState(keychainService: keychain)
        return (keychain, restored, AppRouter(authState: restored))
    }

    @Test func sessionOnlyCredentialsSurviveNewAuthStateAndRestore() async throws {
        let (_, state, router) = try storedSession()
        let repo = MockAuthRepository()
        await SessionRestorer.restore(authState: state, repository: repo, router: router)
        #expect(router.appState == .authenticated)
        #expect(state.token == nil)
        var request = URLRequest(url: url.appendingPathComponent("media/fixture.mp4"))
        try state.authorization?.apply(to: &request)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionid=synthetic")
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotConnectToHost])
    func temporaryOutageKeepsRestoredSessionAndMainNavigation(_ code: URLError.Code) async throws {
        let (keychain, state, router) = try storedSession()
        let repo = MockAuthRepository()
        repo.pingHandler = { throw URLError(code) }
        await SessionRestorer.restore(authState: state, repository: repo, router: router)
        #expect(router.appState == .authenticated)
        #expect(state.isAuthenticated)
        #expect(AuthState(keychainService: keychain).isAuthenticated)
        router.navigate(to: .offlineDownloads)
        #expect(router.path.count == 1)
    }

    @Test func genuineExpiryClearsSavedCredentialsAndKeepsReloginAddress() async throws {
        let (keychain, state, router) = try storedSession()
        let snapshot = state.authorization
        let repo = MockAuthRepository()
        repo.pingHandler = { throw AppError.unauthorized }
        await SessionRestorer.restore(authState: state, repository: repo, router: router)
        #expect(router.appState == .login)
        #expect(!AuthState(keychainService: keychain).isAuthenticated)
        #expect(snapshot?.isActive == false)
        #expect(state.reloginURL == url.absoluteString)
    }

    @Test func staleLaunchFailureCannotSignOutReplacementServer() async throws {
        let (keychain, state, router) = try storedSession()
        let old = state.authorization
        let repo = MockAuthRepository()
        let other = URL(string: "https://other.example:8079")!
        repo.pingHandler = {
            try state.setExistingToken("synthetic-new-server", serverURL: other)
            router.onLoginSuccess()
            throw AppError.unauthorized
        }
        await SessionRestorer.restore(authState: state, repository: repo, router: router)
        #expect(state.baseURL == other)
        #expect(AuthState(keychainService: keychain).baseURL == other)
        #expect(old?.isActive == false)
        #expect(router.appState == .authenticated)
        var request = URLRequest(url: url)
        #expect(throws: AppError.self) { try state.authorization?.apply(to: &request) }
    }

    @Test func navigationToPrivateCopyIsNotInterruptedByLaunchCheck() async throws {
        let (_, state, router) = try storedSession()
        let repo = MockAuthRepository()
        repo.pingHandler = { router.navigate(to: .offlineDownloads); return true }
        await SessionRestorer.restore(authState: state, repository: repo, router: router)
        #expect(router.path.count == 1)
        #expect(state.isAuthenticated)
    }

    @Test func accountAuthenticationFailureStillRequiresSignIn() async throws {
        let (_, state, router) = try storedSession()
        let repo = MockAuthRepository()
        repo.fetchUserAccountHandler = { throw AppError.unauthorized }
        await SessionRestorer.restore(authState: state, repository: repo, router: router)
        #expect(router.appState == .login)
        #expect(!state.isAuthenticated)
    }

    @Test(arguments: [
        ("https://fixture.example", "https://fixture.example"),
        ("https://fixture.example:443/base", "https://fixture.example"),
        ("http://fixture.example", "http://fixture.example"),
        ("http://fixture.example:80/base", "http://fixture.example"),
        ("https://fixture.example:8079/base", "https://fixture.example:8079")
    ])
    func sessionMutationUsesBrowserOriginWithoutDefaultPort(_ pair: (String, String)) throws {
        let base = URL(string: pair.0)!
        let cookie = HTTPCookie(properties: [.name: "csrftoken", .value: "synthetic", .domain: "fixture.example", .path: "/"])!
        var request = URLRequest(url: base.appendingPathComponent("api/video/fixture/progress/"))
        request.httpMethod = "POST"
        try RequestAuthorization(baseURL: base, cookies: [cookie]).apply(to: &request)
        #expect(request.value(forHTTPHeaderField: "Origin") == pair.1)
        #expect(request.value(forHTTPHeaderField: "X-CSRFToken") == "synthetic")
    }

    @Test func maintenanceHTMLDoesNotRevokeSavedAuthentication() {
        for status in [408, 429, 500, 502, 503, 504] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
            #expect(!RequestAuthorization.isAuthenticationFailure(response))
        }
        for status in [200, 302, 401, 403] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
            #expect(RequestAuthorization.isAuthenticationFailure(response))
        }
    }
}
