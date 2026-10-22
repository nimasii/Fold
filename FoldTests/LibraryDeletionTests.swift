import Foundation
import Testing
@testable import Fold

private final class DeletionFixtureBundle: NSObject {}
private final class DeletionHoldProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

extension DataLayerSuite {
@MainActor @Suite(.serialized) struct LibraryDeletionTests {
    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FoldDelete-" + UUID().uuidString)
        let auth = AuthState(keychainService: KeychainService(inMemory: true), loadPersistedCredentials: false)
        let library: OfflineLibrary
        let coordinator: PlaybackCoordinator
        let repository: VideoRepositoryImpl
        let identity: PlaybackIdentity
        let records: [OfflineRecord]
        init() throws {
            let base = URL(string: "https://example.com/archive")!
            try auth.setExistingToken("DELETE_FIXTURE_ONLY", serverURL: base, userID: 7)
            identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: "same-id")
            let disk = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
            let media = try Data(contentsOf: #require(Bundle(for: DeletionFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4")))
            let accounts: [PlaybackAccount?] = [auth.playbackAccount, PlaybackAccount(baseURL: base, userID: 8),
                PlaybackAccount(baseURL: URL(string: "https://different.example/archive")!, userID: 7),
                PlaybackAccount(baseURL: URL(string: "https://example.com/other")!, userID: 7), nil]
            records = try accounts.map { account in
                var record = OfflineRecord(video: TestData.video(youtubeId: "same-id", duration: 2), origin: account.flatMap { URL(string: $0.server) }.map(RequestAuthorization.origin) ?? RequestAuthorization.origin(base), mediaPath: "/media/video.mp4")
                record.account = account; record.status = .ready; record.kind = .mp4
                record.bytes = Int64(media.count); record.nativePlaybackVerified = true
                try media.write(to: disk.file(for: record)!)
                let art = disk.root.appendingPathComponent("Artwork/" + record.id.uuidString + "-thumbnail.jpg")
                try Data("disposable artwork".utf8).write(to: art)
                return record
            }
            try disk.save(records)
            let localConfig = URLSessionConfiguration.ephemeral; localConfig.protocolClasses = [DeletionHoldProtocol.self]
            library = OfflineLibrary(authState: auth, root: disk.root, configuration: localConfig)
            let api = APIClient(authState: auth, configuration: MockResponse.makeConfiguration())
            coordinator = PlaybackCoordinator(auth: auth, api: api, library: library, root: root.appendingPathComponent("History"), monitorNetwork: false)
            repository = VideoRepositoryImpl(apiClient: api, authState: auth, history: coordinator)
        }
        func seed() throws -> PlaybackSession {
            let session = coordinator.session(for: identity)!
            try coordinator.history!.recordPosition(0.4, duration: 2, session: session, ordinal: 1)
            return session
        }
        func close() {
            coordinator.shutdown(); library.pauseAll(); MockResponse.tearDown()
            try? FileManager.default.removeItem(at: root)
        }
    }
    nonisolated private func response(_ request: URLRequest, code: Int = 204) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
    }
    private func waitForRequest() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while MockURLProtocol.lastRequest == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(MockURLProtocol.lastRequest != nil)
    }

    @Test func confirmedDeletionRemovesOnlyOwnedBytesArtworkManifestAndHistoryAcrossRelaunch() async throws {
        let f = try Fixture(); defer { f.close() }
        let session = try f.seed()
        let stale = f.coordinator.beginRead()!
        MockURLProtocol.requestHandler = { request in (response(request), Data()) }
        try await f.repository.deleteVideo(id: "same-id")
        #expect(f.library.records.map(\.id) == Array(f.records.dropFirst()).map(\.id))
        #expect(!FileManager.default.fileExists(atPath: f.library.disk!.file(for: f.records[0])!.path))
        #expect(!FileManager.default.fileExists(atPath: f.library.disk!.root.appendingPathComponent("Artwork/" + f.records[0].id.uuidString + "-thumbnail.jpg").path))
        #expect(f.coordinator.history!.bookmark(for: f.identity) == nil)
        #expect(f.coordinator.history!.pendingWrites(for: f.identity.account).isEmpty)
        #expect(!f.coordinator.record(1, duration: 2, session: session, ordinal: 2))
        var staleVideo = f.records[0].libraryVideo; staleVideo.playbackIdentity = f.identity
        #expect(throws: (any Error).self) { try f.coordinator.accept(staleVideo, context: stale) }
        #expect(f.coordinator.continuingVideos(in: [staleVideo]).isEmpty)
        let restored = try PlaybackHistoryStore(root: f.root.appendingPathComponent("History"))
        #expect(restored.deletions[f.identity] != nil && restored.bookmark(for: f.identity) == nil)
        #expect(try f.library.disk!.load().map(\.id) == f.library.records.map(\.id))
        for record in f.records.dropFirst() { #expect(FileManager.default.fileExists(atPath: f.library.disk!.file(for: record)!.path)) }
    }

    @Test(arguments: [401, 403, 404, 500]) func failedServerDeletionKeepsAllCopiesAndBookmark(_ code: Int) async throws {
        let f = try Fixture(); defer { f.close() }; _ = try f.seed()
        MockURLProtocol.requestHandler = { request in (response(request, code: code), Data()) }
        do { try await f.repository.deleteVideo(id: "same-id"); Issue.record("Expected server failure") } catch {}
        #expect(f.library.records.count == f.records.count)
        #expect(f.coordinator.history!.bookmark(for: f.identity)?.position == 0.4)
        #expect(f.coordinator.history!.deletions.isEmpty)
        #expect(FileManager.default.fileExists(atPath: f.library.disk!.file(for: f.records[0])!.path))
    }

    @Test func offlineAndCanceledDeletionNeverRemoveTheLocalCopy() async throws {
        let f = try Fixture(); defer { f.close() }; _ = try f.seed()
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        do { try await f.repository.deleteVideo(id: "same-id"); Issue.record("Expected offline failure") } catch {}
        MockURLProtocol.delayedHandler = { request in (response(request), Data(), 0.4) }
        MockURLProtocol.lastRequest = nil
        let deletion = Task { try await f.repository.deleteVideo(id: "same-id") }
        try await waitForRequest(); deletion.cancel()
        do { try await deletion.value; Issue.record("Expected cancellation") } catch {}
        #expect(f.library.records.count == f.records.count)
        #expect(f.coordinator.history!.bookmark(for: f.identity)?.position == 0.4)
    }

    @Test func accountSwitchAfterTransmissionCleansCapturedOwnerOnlyWithoutNavigatingNewAccount() async throws {
        let f = try Fixture(); defer { f.close() }; _ = try f.seed()
        MockURLProtocol.delayedHandler = { request in (response(request), Data(), 0.2) }
        let deletion = Task { try await f.repository.deleteVideo(id: "same-id") }
        try await waitForRequest()
        try f.auth.setExistingToken("DIFFERENT_SYNTHETIC", serverURL: URL(string: "https://example.com/archive")!, userID: 8)
        do { try await deletion.value; Issue.record("Old UI must not navigate the new account") } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(!f.library.records.contains { $0.id == f.records[0].id })
        #expect(f.library.records.contains { $0.id == f.records[1].id })
        #expect(f.auth.userID == 8)
    }

    @Test func activeMatchingPlayerStopsAndCannotSaveOrRestartDeletedMedia() async throws {
        let f = try Fixture(); defer { f.close() }; _ = try f.seed()
        let router = AppRouter(authState: f.auth)
        let model = VideoDetailViewModel(videoId: "same-id", videoRepository: f.repository, authState: f.auth, router: router, playbackCoordinator: f.coordinator)
        await model.loadVideo(); model.startPlayback()
        #expect(model.isLocalPlayback && model.isPlaying)
        MockURLProtocol.requestHandler = { request in (response(request), Data()) }
        try await f.repository.deleteVideo(id: "same-id")
        #expect(!model.isPlaying && model.video == nil && !model.isLocalPlayback)
        let saved = await model.saveProgress(position: 1); #expect(!saved)
        model.startPlayback(); #expect(!model.isPlaying)
        #expect(f.coordinator.history!.bookmark(for: f.identity) == nil)
    }

    @Test(arguments: [false, true]) func lateDownloadOrPreparationCannotRestoreDeletedRecord(_ preparing: Bool) async throws {
        let f = try Fixture(); defer { f.close() }
        var video = TestData.video(youtubeId: "in-flight", duration: 2); video.playbackIdentity = PlaybackIdentity(account: f.identity.account, videoID: "in-flight")
        let id = try #require(f.library.enqueue(video))
        let record = try #require(f.library.records.first { $0.id == id })
        let description = id.uuidString + "/" + record.attempt!.uuidString
        let staged = try f.library.disk!.preparationOutput()
        let bytes = try Data(contentsOf: #require(Bundle(for: DeletionFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4")))
        try bytes.write(to: staged)
        let http = HTTPURLResponse(url: URL(string: record.origin + record.mediaPath)!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(bytes.count)])!
        if preparing { f.library.finish(description, response: http, staged: staged) }
        MockURLProtocol.requestHandler = { request in (response(request), Data()) }
        try await f.repository.deleteVideo(id: "in-flight")
        if !preparing { f.library.finish(description, response: http, staged: staged) }
        f.library.progress(description, bytes: 99, total: 100)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!f.library.records.contains { $0.id == id })
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func failedCleanupIsVisibleRetriesAndDurableMarkerRecoversAfterRelaunch() async throws {
        let f = try Fixture(); defer { f.close() }; _ = try f.seed()
        let manifest = f.library.disk!.root.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: manifest); try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: true)
        MockURLProtocol.requestHandler = { request in (response(request), Data()) }
        try await f.repository.deleteVideo(id: "same-id")
        #expect(f.coordinator.errorMessage != nil && f.library.records.contains { $0.id == f.records[0].id })
        #expect(f.coordinator.history!.deletions[f.identity] != nil)
        try FileManager.default.removeItem(at: manifest)
        f.coordinator.requestSync(force: true)
        #expect(!f.library.records.contains { $0.id == f.records[0].id })
        #expect(f.coordinator.errorMessage == nil)
        // Simulate an interruption after journaling but before bytes cleanup.
        try f.library.disk!.save(f.records)
        let bytes = try Data(contentsOf: f.library.disk!.file(for: f.records[1])!)
        try bytes.write(to: f.library.disk!.file(for: f.records[0])!)
        let restored = OfflineLibrary(authState: f.auth, root: f.library.disk!.root)
        let api = APIClient(authState: f.auth, configuration: MockResponse.makeConfiguration())
        let resumed = PlaybackCoordinator(auth: f.auth, api: api, library: restored, root: f.root.appendingPathComponent("History"), monitorNetwork: false)
        defer { resumed.shutdown(); restored.pauseAll() }
        #expect(!restored.records.contains { $0.id == f.records[0].id })
        #expect(restored.records.count == 4)
    }

    @Test func journalFailureRetainsBytesAndBlocksLateProgressUntilCleanupRetries() async throws {
        let f = try Fixture(); defer { f.close() }; let old = try f.seed()
        let journal = f.root.appendingPathComponent("History/history.json")
        try FileManager.default.removeItem(at: journal); try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        MockURLProtocol.requestHandler = { request in (response(request), Data()) }
        try await f.repository.deleteVideo(id: "same-id")
        #expect(f.coordinator.errorMessage != nil)
        #expect(FileManager.default.fileExists(atPath: f.library.disk!.file(for: f.records[0])!.path))
        #expect(!f.coordinator.record(1, duration: 2, session: old, ordinal: 2))
        try FileManager.default.removeItem(at: journal)
        f.coordinator.requestSync(force: true)
        #expect(f.coordinator.errorMessage == nil && f.coordinator.history!.bookmark(for: f.identity) == nil)
        #expect(!f.library.records.contains { $0.id == f.records[0].id })
    }

    @Test func deleteAndIgnoreFailureStillMarksDeletionAndRemovesTheOwnedCopy() async throws {
        let f = try Fixture(); defer { f.close() }; _ = try f.seed()
        let router = AppRouter(authState: f.auth)
        let model = VideoDetailViewModel(videoId: "same-id", videoRepository: f.repository, authState: f.auth, router: router, playbackCoordinator: f.coordinator)
        await model.loadVideo()
        MockURLProtocol.requestHandler = { request in
            (response(request, code: request.httpMethod == "DELETE" ? 204 : 500), Data())
        }
        await model.deleteAndIgnoreVideo()
        #expect(router.deletedVideoIds.contains("same-id"))
        #expect(!f.library.records.contains { $0.id == f.records[0].id })
        #expect(model.errorMessage != nil)
    }

    @Test func freshServerReacquisitionCanSeedNewHistoryButOldReadCannotResurrectIt() async throws {
        let f = try Fixture(); defer { f.close() }; _ = try f.seed()
        let old = f.coordinator.beginRead()!
        MockURLProtocol.requestHandler = { request in (response(request), Data()) }
        try await f.repository.deleteVideo(id: "same-id")
        var video = f.records[0].libraryVideo; video.playbackIdentity = f.identity
        #expect(throws: (any Error).self) { try f.coordinator.accept(video, context: old) }
        let reacquired = try f.coordinator.accept(video, context: f.coordinator.beginRead())
        #expect(reacquired.playbackIdentity == f.identity)
        #expect(f.coordinator.history!.deletions[f.identity] == nil)
    }

    @Test func downloadsOnlyRemovalPreservesSharedHistoryAndNeverDeletesOnServer() async throws {
        let f = try Fixture(); defer { f.close() }; _ = try f.seed()
        MockURLProtocol.lastRequest = nil
        #expect(f.library.remove(f.records[0].id))
        #expect(f.coordinator.history!.bookmark(for: f.identity)?.position == 0.4)
        #expect(f.coordinator.history!.deletions.isEmpty)
        #expect(MockURLProtocol.lastRequest == nil)
    }
}
}
