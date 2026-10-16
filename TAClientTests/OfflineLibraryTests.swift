import Foundation
import AVFoundation
import Testing
@testable import TAClient

private final class OfflineFixtureBundle: NSObject {}
private final class OfflineHoldProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {} // No network is performed; tests deliver completion explicitly.
    override func stopLoading() {}
}

// Auth expiry exercises AppRouter's shared media-cache cleanup, so share the existing
// serialized transport boundary with the cache and authentication suites.
extension DataLayerSuite {
@Suite(.serialized) struct OfflineLibraryTests {
    let base = URL(string: "https://example.com")!
    private func make(_ root: URL? = nil) -> (OfflineLibrary, AuthState, URL) {
        let state = AuthState(keychainService: KeychainService(inMemory: true), loadPersistedCredentials: false)
        try! state.setExistingToken("DUMMY_AUTH_SECRET", serverURL: base)
        let directory = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("OfflineTests-" + UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OfflineHoldProtocol.self]
        return (OfflineLibrary(authState: state, root: directory, configuration: config), state, directory)
    }
    private func clip() throws -> URL {
        try #require(Bundle(for: OfflineFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4"))
    }
    private func staged(_ library: OfflineLibrary) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: clip(), to: tmp)
        return try #require(library.disk).stage(tmp)
    }
    private func description(_ record: OfflineRecord) -> String {
        record.id.uuidString + "/" + record.attempt!.uuidString
    }
    private func response(_ size: Int, code: Int = 200, mime: String = "video/mp4") -> HTTPURLResponse {
        HTTPURLResponse(url: base.appendingPathComponent("video.mp4"), statusCode: code, httpVersion: nil,
                        headerFields: ["Content-Length": String(size), "Content-Type": mime])!
    }
    @discardableResult private func ready(_ library: OfflineLibrary) throws -> OfflineRecord {
        let id = try #require(library.enqueue(TestData.video()))
        let pending = try #require(library.records.first { $0.id == id })
        let file = try staged(library)
        let size = try Data(contentsOf: file).count
        library.finish(description(pending), response: response(size), staged: file)
        let record = try #require(library.records.first)
        #expect(record.status == .ready)
        return record
    }

    @Test func privateNonPurgeableStorageAndManifestNeverContainCredentials() throws {
        let (library, _, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try ready(library)
        let file = try #require(library.localURL(for: record))
        #expect(file.isFileURL && file.path.hasPrefix(root.path))
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let protection = (attrs[.protectionKey] as? FileProtectionType)
            ?? (attrs[.protectionKey] as? String).map(FileProtectionType.init(rawValue:))
        #if targetEnvironment(simulator)
        // Simulator may omit this device-only attribute; backup exclusion above is observable.
        if let protection { #expect(protection == .completeUntilFirstUserAuthentication) }
        #else
        #expect(protection == .completeUntilFirstUserAuthentication)
        #endif
        let manifest = try String(contentsOf: root.appendingPathComponent("library.json"), encoding: .utf8)
        #expect(!manifest.contains("DUMMY_AUTH_SECRET"))
        #expect(!manifest.contains("Cookie"))
        #expect(!manifest.contains("resumeData"))
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool != true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool != true)
    }
    @Test func restartKeepsReadyFilesWithoutAnySavedServerAuthentication() throws {
        let (library, _, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let saved = try ready(library)
        library.savePosition(saved.id, seconds: 1)
        let signedOut = AuthState(keychainService: KeychainService(inMemory: true), loadPersistedCredentials: false)
        let restored = OfflineLibrary(authState: signedOut, root: root)
        let record = try #require(restored.records.first)
        #expect(record.id == saved.id && record.status == .ready && record.position == 1)
        #expect(restored.localURL(for: record)?.isFileURL == true)
        #expect(!signedOut.isAuthenticated)
    }
    @Test func duplicateRequestsNeverCreateAnotherTransferOrCopy() throws {
        let (library, _, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let first = library.enqueue(TestData.video())
        let attempt = library.records.first?.attempt
        #expect(library.enqueue(TestData.video()) == first)
        #expect(library.records.count == 1 && library.records.first?.attempt == attempt)
        let record = try ready(library)
        #expect(library.enqueue(TestData.video()) == record.id)
        #expect(library.records.count == 1)
    }
    @Test func interruptionAndCancelDiscardLatePartialFilesAndPersistRetryableState() throws {
        let (library, _, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(library.enqueue(TestData.video()))
        let pending = try #require(library.records.first)
        library.progress(description(pending), bytes: 10, total: 100)
        let temporary = try staged(library)
        library.pauseAll()
        library.finish(description(pending), response: response(100), staged: temporary)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(library.records.first?.status == .interrupted)
        #expect(library.localURL(for: library.records[0]) == nil)
        let (restored, _, _) = make(root)
        #expect(restored.records.first?.status == .interrupted)
        restored.retry(id)
        #expect(restored.records.first?.status == .downloading)
        #expect(restored.records.first?.attempt != pending.attempt)
        restored.cancel(id)
        #expect(restored.records.first?.status == .canceled)
    }
    @Test func abandonedInFlightRecordBecomesInterruptedAfterRelaunch() throws {
        let (library, _, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        library.enqueue(TestData.video())
        let (restored, _, _) = make(root)
        #expect(restored.records.first?.status == .interrupted)
        #expect(restored.records.first?.attempt == nil)
        library.pauseAll()
    }
    @Test func localRemovalDeletesOnlyOurMediaAndMetadata() throws {
        let (library, _, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: sentinel)
        let record = try ready(library)
        let local = try #require(library.localURL(for: record))
        library.remove(record.id)
        #expect(library.records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: local.path))
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(try library.disk?.load().isEmpty == true)
    }
    @Test func unauthorizedResponseRequiresLoginButPreservesCompletedCopies() throws {
        let (library, state, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let saved = try ready(library)
        let router = AppRouter(authState: state); router.onLoginSuccess()
        library.enqueue(TestData.video(youtubeId: "second"))
        let pending = try #require(library.records.first)
        let file = try staged(library)
        library.finish(description(pending), response: response(0, code: 401, mime: "application/json"), staged: file)
        #expect(library.records.first?.status == .needsSignIn)
        #expect(!state.isAuthenticated && router.appState == .login)
        #expect(library.localURL(for: saved) != nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
    @Test func changedOrRevokedAuthorizationCannotFinishAnOldTransfer() throws {
        let (library, state, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        library.enqueue(TestData.video())
        let pending = try #require(library.records.first)
        state.handleUnauthorized(); library.authorizationChanged()
        let file = try staged(library)
        library.finish(description(pending), response: response(10), staged: file)
        #expect(library.records.first?.status == .needsSignIn)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
    @Test func requestUsesSameOriginAuthAndRejectsSignedURLsAndExpiredCookies() throws {
        let auth = RequestAuthorization(baseURL: base, token: "DUMMY_AUTH_SECRET")
        let request = try OfflineLibrary.request(url: base.appendingPathComponent("video.mp4"), authorization: auth)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token DUMMY_AUTH_SECRET")
        #expect(request.httpShouldHandleCookies == false)
        for url in ["https://evil.example/video.mp4", "http://example.com/video.mp4", "https://example.com:2000/video.mp4", "https://example.com/video.mp4?token=secret", "file:///tmp/video.mp4"] {
            #expect(throws: OfflineFailure.self) { try OfflineLibrary.request(url: URL(string: url)!, authorization: auth) }
        }
        let expired = HTTPCookie(properties: [.name: "sessionid", .value: "expired", .domain: "example.com", .path: "/", .expires: Date.distantPast])!
        #expect(throws: OfflineFailure.self) { try OfflineLibrary.request(url: base, authorization: RequestAuthorization(baseURL: base, cookies: [expired])) }
    }
    @Test func truncatedOrInvalidFilesAreNeverMarkedReady() throws {
        let (library, _, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        library.enqueue(TestData.video())
        var pending = try #require(library.records.first)
        var file = try staged(library)
        library.finish(description(pending), response: response(999999), staged: file)
        #expect(library.records.first?.status == .failed && library.records.first?.failure == .invalidMedia)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        library.retry(pending.id); pending = try #require(library.records.first)
        let temp = root.appendingPathComponent("garbage.tmp")
        try Data(repeating: 1, count: 100).write(to: temp)
        file = try #require(library.disk).stage(temp)
        library.finish(description(pending), response: response(100), staged: file)
        #expect(library.records.first?.status == .failed)
        #expect(library.records.first?.kind == nil)
    }
    @Test func corruptManifestIsPreservedAndStorageFailureIsVisible() throws {
        let (_, state, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("library.json")
        try Data("corrupt".utf8).write(to: manifest)
        let library = OfflineLibrary(authState: state, root: root)
        #expect(library.storageError != nil)
        #expect(library.enqueue(TestData.video()) == nil)
        #expect(try String(contentsOf: manifest, encoding: .utf8) == "corrupt")
    }
    @Test func failedMediaMoveCannotPublishReadyEntry() throws {
        let (library, _, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        library.enqueue(TestData.video()); let pending = try #require(library.records.first)
        let file = try staged(library); let size = try Data(contentsOf: file).count
        try FileManager.default.removeItem(at: root.appendingPathComponent("Media"))
        try Data().write(to: root.appendingPathComponent("Media"))
        library.finish(description(pending), response: response(size), staged: file)
        #expect(library.records.first?.status == .failed && library.records.first?.failure == .storage)
    }
    @Test(.timeLimit(.minutes(1)))
    func localPlayerStartsAndSeeksWithNoAuthenticationOrNetworkSession() async throws {
        let (library, state, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try ready(library)
        state.handleUnauthorized()
        let playback = OfflinePlayback(); defer { playback.stop() }
        await playback.load(record, library: library)
        let player = try #require(playback.player)
        #expect((player.currentItem?.asset as? AVURLAsset)?.url.isFileURL == true)
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while player.currentTime().seconds < 0.2 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(player.currentTime().seconds >= 0.2)
        #expect(await player.seek(to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero))
        #expect(player.currentTime().seconds >= 0.9)
        #expect(playback.error == nil)
    }
    @Test func offlineStartupDoesNotClearSavedServerCredentials() {
        let (_, state, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        let router = AppRouter(authState: state)
        router.onAutoLoginUnavailable()
        #expect(state.isAuthenticated && router.appState == .login)
    }
}
}
