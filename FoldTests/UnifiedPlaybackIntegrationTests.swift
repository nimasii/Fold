import Foundation
import Testing
@testable import Fold

private final class HistoryFixtureBundle: NSObject {}

extension DataLayerSuite {
@MainActor @Suite(.serialized) struct UnifiedPlaybackIntegrationTests {
    private let base = URL(string: "https://ta.example.com")!
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("UnifiedPlaybackTests-" + UUID().uuidString) }
    private func state(_ user: Int = 7, keychain: KeychainService = KeychainService(inMemory: true)) throws -> AuthState {
        let auth = AuthState(keychainService: keychain, loadPersistedCredentials: false)
        try auth.setExistingToken("SYNTHETIC_ONLY", serverURL: base, userID: user)
        return auth
    }
    private func make(_ root: URL, auth: AuthState) -> (PlaybackCoordinator, OfflineLibrary, APIClient) {
        let config = MockResponse.makeConfiguration()
        let api = APIClient(authState: auth, configuration: config)
        let library = OfflineLibrary(authState: auth, root: root.appendingPathComponent("Downloads"), configuration: config)
        let coordinator = PlaybackCoordinator(auth: auth, api: api, library: library, root: root.appendingPathComponent("History"), monitorNetwork: false)
        return (coordinator, library, api)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }

    @Test func verifiedAccountPersistsWithoutTrustingOldConnectionOrAssumingLegacyOwner() throws {
        let keychain = KeychainService(inMemory: true)
        let auth = try state(keychain: keychain)
        let original = try #require(auth.authorization?.id)
        let restored = AuthState(keychainService: keychain)
        #expect(restored.playbackAccount == auth.playbackAccount)
        #expect(!restored.accountConfirmed) // Offline identity can read; network sync waits for verification.
        try auth.setExistingToken("SECOND_SYNTHETIC_ONLY", serverURL: base, userID: 8)
        auth.setVerifiedAccount(7, authorizationID: original)
        #expect(auth.userID == 8)
        let legacy = StoredSession(serverURL: base, cookies: [], token: "LEGACY_SYNTHETIC_ONLY")
        keychain.save(String(data: try JSONEncoder().encode(legacy), encoding: .utf8)!, for: .sessionCookies)
        let unowned = AuthState(keychainService: keychain)
        #expect(unowned.isAuthenticated && unowned.playbackAccount == nil)
    }

    @Test func scopedMutationsCannotAccidentallyUseReplacementCredentials() async throws {
        defer { MockResponse.tearDown() }
        let auth = try state(); let (api, _) = MockResponse.makeAPIClient(authState: auth)
        let id = try #require(auth.authorization?.id)
        try auth.setExistingToken("SECOND_SYNTHETIC_ONLY", serverURL: base, userID: 8)
        var requests = 0
        MockURLProtocol.requestHandler = { _ in requests += 1; return (MockResponse.httpResponse(), Data()) }
        do {
            try await api.requestVoid(endpoint: .videoProgress(id: "video"), body: VideoProgressDTO(position: 40), expectedAuthorizationID: id)
            Issue.record("A stale account write must be canceled")
        } catch is CancellationError {} catch { Issue.record("Unexpected error type") }
        #expect(requests == 0)
    }

    @Test func offlineRewindRelaunchAndReconnectSendExactLatestPointAndResetInOrder() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state(); let (coordinator, _, _) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let account = try #require(auth.playbackAccount)
        let identity = PlaybackIdentity(account: account, videoID: "video")
        let session = try #require(coordinator.session(for: identity))
        MockResponse.setUpError(URLError(.notConnectedToInternet))
        #expect(coordinator.record(80, duration: 300, session: session, ordinal: 1))
        #expect(coordinator.record(2, duration: 300, session: session, ordinal: 2))
        try await Task.sleep(for: .milliseconds(500))
        #expect(coordinator.history?.pendingWrites(for: account).count == 1)
        let restored = make(root, auth: auth).0
        defer { restored.shutdown() }
        #expect(restored.history?.bookmark(for: identity)?.position == 2)
        var methods: [String] = []
        MockURLProtocol.requestHandler = { request in
            methods.append(request.httpMethod ?? "")
            return (MockResponse.httpResponse(url: request.url!.absoluteString), Data())
        }
        restored.requestSync()
        try await wait { restored.history?.pendingWrites(for: account).isEmpty == true }
        #expect(methods == ["DELETE"])
        #expect(restored.history?.bookmark(for: identity)?.position == 2)
        let otherAccount = PlaybackAccount(baseURL: base, userID: 8)!
        #expect(restored.history?.pendingWrites(for: otherAccount).isEmpty == true)
    }

    @Test func watchedResetThenNewProgressKeepsIntentAndDoesNotUseMaximumPosition() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state(); let (coordinator, _, _) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: "video")
        try coordinator.setWatched(false, videoID: "video", duration: 300)
        let session = try #require(coordinator.session(for: identity))
        #expect(coordinator.record(40, duration: 300, session: session, ordinal: 1))
        var actions: [String] = []
        MockURLProtocol.requestHandler = { request in
            actions.append((request.httpMethod ?? "") + " " + (request.url?.path ?? ""))
            return (MockResponse.httpResponse(url: request.url!.absoluteString), Data())
        }
        try await wait { coordinator.history?.pendingWrites(for: identity.account).isEmpty == true }
        #expect(actions == ["POST /api/watched", "DELETE /api/video/video/progress", "POST /api/video/video/progress"])
        #expect(coordinator.history?.bookmark(for: identity)?.position == 40)
        #expect(coordinator.history?.bookmark(for: identity)?.watched == false)
    }

    @Test func permissionDenialKeepsHistoryAndExistingSessionWithoutInfiniteRetry() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state(); let (coordinator, _, _) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: "video")
        var denied = 0
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/ping" {
                return (MockResponse.httpResponse(url: request.url!.absoluteString), MockResponse.json(["response": "pong", "user": 7]))
            }
            denied += 1
            return (MockResponse.httpResponse(url: request.url!.absoluteString, statusCode: 403), Data())
        }
        let session = try #require(coordinator.session(for: identity))
        #expect(coordinator.record(40, duration: 300, session: session, ordinal: 1))
        try await wait { denied == 1 }
        try await Task.sleep(for: .milliseconds(300))
        #expect(denied == 1 && auth.isAuthenticated)
        #expect(coordinator.history?.pendingWrites(for: identity.account).count == 1)
    }

    @Test func sessionChangeBeforeSyncCannotLeakOldAccountsPendingHistory() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state(); let (coordinator, _, _) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: "video")
        let session = try #require(coordinator.session(for: identity))
        #expect(coordinator.record(70, duration: 300, session: session, ordinal: 1))
        try auth.setExistingToken("SECOND_SYNTHETIC_ONLY", serverURL: base, userID: 8)
        coordinator.connectionChanged()
        var requests = 0
        MockURLProtocol.requestHandler = { _ in requests += 1; return (MockResponse.httpResponse(), Data()) }
        try await Task.sleep(for: .milliseconds(500))
        #expect(requests == 0)
        #expect(coordinator.history?.pendingWrites(for: identity.account).count == 1)
        #expect(!coordinator.record(80, duration: 300, session: session, ordinal: 2))
    }

    @Test func readyLocalMediaWinsBeforeRepositoryOrStreamAndRemovalKeepsHistory() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state()
        let store = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
        let fixture = try #require(Bundle(for: HistoryFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4"))
        var record = OfflineRecord(video: TestData.video(youtubeId: "video", duration: 2), origin: RequestAuthorization.origin(base), mediaPath: "/media/video.mp4")
        record.account = auth.playbackAccount; record.kind = .mp4; record.status = .ready; record.nativePlaybackVerified = true
        record.bytes = Int64(try Data(contentsOf: fixture).count)
        try FileManager.default.copyItem(at: fixture, to: store.file(for: record)!)
        try store.save([record])
        let (coordinator, library, api) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: "video")
        let session = try #require(coordinator.session(for: identity))
        MockResponse.setUpError(URLError(.notConnectedToInternet))
        #expect(coordinator.record(0.7, duration: 2, session: session, ordinal: 1))
        let model = VideoDetailViewModel(videoId: "video", videoRepository: VideoRepositoryImpl(apiClient: api, authState: auth, history: coordinator), authState: auth, router: AppRouter(authState: auth), playbackCoordinator: coordinator)
        await model.loadVideo()
        #expect(model.isLocalPlayback)
        #expect(model.localPlayback?.mediaURL?.isFileURL == true)
        #expect(model.startPosition == 0.7)
        #expect(MockURLProtocol.lastRequest == nil) // No detail request, preloader or stream.
        #expect(coordinator.display(record).position == 0.7)
        library.remove(record.id)
        #expect(coordinator.history?.bookmark(for: identity)?.position == 0.7)
        #expect(await coordinator.localSource(videoID: "video") == nil)
    }

    @Test func legacyBookmarkOnlyLinksOnExplicitActionAndRetainsOriginalPosition() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state()
        let store = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
        var record = OfflineRecord(video: TestData.video(youtubeId: "video"), origin: RequestAuthorization.origin(base), mediaPath: "/media/video.mp4")
        record.status = .canceled; record.position = 123
        try store.save([record])
        let (coordinator, library, _) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        #expect(coordinator.identity(for: record) == nil)
        #expect(coordinator.display(record).position == 123)
        #expect(coordinator.history?.bookmarks.isEmpty == true)
        #expect(library.linkHistory(record.id, account: auth.playbackAccount!, position: 45))
        let linked = try #require(library.records.first)
        #expect(linked.position == 45 && linked.legacyPosition == 123)
        #expect(linked.account == auth.playbackAccount)
        #expect(try store.load().first?.legacyPosition == 123)
    }

    @Test func canceledOldSyncCannotAcknowledgeOrDeferNewAccountsSuccessfulSync() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state(); let (coordinator, _, _) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let old = PlaybackIdentity(account: auth.playbackAccount!, videoID: "old-video")
        var oldStarted = false
        MockURLProtocol.delayedHandler = { request in
            if request.url?.path == "/api/video/old-video/progress" { oldStarted = true }
            return (MockResponse.httpResponse(url: request.url!.absoluteString), Data(), 1)
        }
        #expect(coordinator.record(40, duration: 300, session: coordinator.session(for: old)!, ordinal: 1))
        try await wait { oldStarted }
        try auth.setExistingToken("SECOND_SYNTHETIC_ONLY", serverURL: base, userID: 8)
        coordinator.connectionChanged()
        MockURLProtocol.delayedHandler = nil
        var sentIDs: [String] = []
        MockURLProtocol.requestHandler = { request in
            sentIDs.append(request.url!.path)
            return (MockResponse.httpResponse(url: request.url!.absoluteString), Data())
        }
        let current = PlaybackIdentity(account: auth.playbackAccount!, videoID: "new-video")
        #expect(coordinator.record(30, duration: 300, session: coordinator.session(for: current)!, ordinal: 1))
        try await wait { coordinator.history?.pendingWrites(for: current.account).isEmpty == true }
        try await Task.sleep(for: .milliseconds(1100))
        #expect(!coordinator.syncDeferred)
        #expect(sentIDs == ["/api/video/new-video/progress"])
        #expect(coordinator.history?.pendingWrites(for: old.account).count == 1)
    }

    @Test func offlineRestoredAccountIsReverifiedBeforeSendingAndDifferentUserCannotReceiveItsPoint() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let keychain = KeychainService(inMemory: true)
        let original = try state(keychain: keychain)
        let restored = AuthState(keychainService: keychain)
        let (coordinator, _, _) = make(root, auth: restored)
        defer { coordinator.shutdown() }
        let identity = PlaybackIdentity(account: original.playbackAccount!, videoID: "video")
        var actions: [String] = []
        MockURLProtocol.requestHandler = { request in
            actions.append(request.httpMethod! + " " + request.url!.path)
            return (MockResponse.httpResponse(url: request.url!.absoluteString), MockResponse.json(["response": "pong", "user": 8]))
        }
        #expect(coordinator.record(40, duration: 300, session: coordinator.session(for: identity)!, ordinal: 1))
        try await wait { restored.userID == 8 }
        #expect(actions == ["GET /api/ping"])
        #expect(coordinator.history?.pendingWrites(for: identity.account).count == 1)
    }

    @Test func missingCorruptAndPartialCopiesFallBackWithoutDeletingBytesOrLosingHistory() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state()
        let disk = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
        let fixture = try #require(Bundle(for: HistoryFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4"))
        let bytes = try Data(contentsOf: fixture)
        var records: [OfflineRecord] = []
        for id in ["missing", "corrupt", "partial"] {
            var record = OfflineRecord(video: TestData.video(youtubeId: id, duration: 300), origin: RequestAuthorization.origin(base), mediaPath: "/media/" + id + ".mp4")
            record.account = auth.playbackAccount; record.status = .ready; record.kind = .mp4
            record.bytes = Int64(bytes.count); record.nativePlaybackVerified = true
            try bytes.write(to: disk.file(for: record)!)
            records.append(record)
        }
        try disk.save(records)
        let (coordinator, _, api) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        try FileManager.default.removeItem(at: disk.file(for: records[0])!)
        try Data(repeating: 0, count: bytes.count).write(to: disk.file(for: records[1])!)
        try bytes.prefix(16).write(to: disk.file(for: records[2])!)
        MockURLProtocol.requestHandler = { request in
            let id = request.url!.path.split(separator: "/").last.map(String.init)!
            return (MockResponse.httpResponse(url: request.url!.absoluteString), MockResponse.json([
                "youtube_id": id, "title": "Remote fallback", "media_url": "/media/" + id + ".webm",
                "player": ["duration": 300, "position": 0, "watched": false], "streams": [["type": "video", "codec": "vp9"]]
            ]))
        }
        for record in records {
            let identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: record.videoID)
            #expect(coordinator.record(40, duration: 300, session: coordinator.session(for: identity)!, ordinal: 1))
            let model = VideoDetailViewModel(videoId: record.videoID, videoRepository: VideoRepositoryImpl(apiClient: api, authState: auth, history: coordinator), authState: auth, router: AppRouter(authState: auth), playbackCoordinator: coordinator)
            await model.loadVideo()
            #expect(!model.isLocalPlayback)
            #expect(model.video?.mediaUrl.hasSuffix(".webm") == true)
            #expect(model.startPosition == 40)
        }
        #expect(try Data(contentsOf: disk.file(for: records[1])!) == Data(repeating: 0, count: bytes.count))
        #expect(try Data(contentsOf: disk.file(for: records[2])!).count == 16)
    }

    @Test func deviceOnlyLegacyPauseRewindZeroAndReplayNeverIssueServerProgress() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state()
        let disk = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
        var record = OfflineRecord(video: TestData.video(youtubeId: "legacy", duration: 300), origin: RequestAuthorization.origin(base), mediaPath: "/media/legacy.mp4")
        record.status = .canceled; record.position = 100
        try disk.save([record])
        let (_, library, _) = make(root, auth: auth)
        let source = LocalVideoPlayback(record: record, library: library)
        let model = VideoDetailViewModel(videoId: record.id.uuidString, videoRepository: LocalVideoRepository(source: source), authState: auth, router: AppRouter(authState: auth), localPlayback: source)
        await model.loadVideo()
        model.onVLCTimeChanged(seconds: 120)
        model.onVLCTimeChanged(seconds: 20)
        model.onVLCTimeChanged(seconds: 0)
        #expect(try disk.load().first?.position == 0)
        model.playbackDidEnd()
        model.onVLCTimeChanged(seconds: 294) // Artificial end rewind cannot replace completion.
        #expect(try disk.load().first?.position == 300)
        model.playbackDidResume()
        model.onVLCTimeChanged(seconds: 2)
        #expect(try disk.load().first?.position == 2)
        #expect(MockURLProtocol.lastRequest == nil)
    }

    @Test func localMetadataPreservesSponsorBlockAndPlaylistMembership() throws {
        let segment = SponsorBlockSegment(category: .sponsor, startTime: 12, endTime: 15)
        let video = TestData.video(sponsorblock: [segment], playlists: ["playlist"])
        let record = OfflineRecord(video: video, origin: RequestAuthorization.origin(base), mediaPath: "/video.mp4")
        let restored = try JSONDecoder().decode(OfflineRecord.self, from: JSONEncoder().encode(record))
        #expect(restored.libraryVideo.sponsorblock == [segment])
        #expect(restored.libraryVideo.playlists == ["playlist"])
    }

    @Test func serverReadRevalidatesPersistedOwnerBeforeImportingProgress() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let keychain = KeychainService(inMemory: true)
        _ = try state(keychain: keychain)
        let auth = AuthState(keychainService: keychain)
        let (coordinator, _, api) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let old = PlaybackIdentity(account: auth.playbackAccount!, videoID: "video")
        try coordinator.history?.recordPosition(50, duration: 300, session: coordinator.session(for: old)!, ordinal: 1)
        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url!.path)
            let data = request.url!.path == "/api/ping" ? MockResponse.json(["response": "pong", "user": 8]) : MockResponse.json([
                "youtube_id": "video", "title": "New account video", "player": ["duration": 300, "position": 12, "watched": false]
            ])
            return (MockResponse.httpResponse(url: request.url!.absoluteString), data)
        }
        let result = try await VideoRepositoryImpl(apiClient: api, authState: auth, history: coordinator).getVideo(id: "video")
        #expect(paths == ["/api/ping", "/api/video/video"])
        #expect(result.playbackIdentity?.account.userID == 8)
        #expect(result.position == 12)
        #expect(coordinator.history?.bookmark(for: old)?.position == 50)
        coordinator.connectionChanged()
    }

    @Test func libraryReusesLegacyBytesWithoutAdoptingItsUnownedBookmark() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state()
        let disk = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
        let fixture = try #require(Bundle(for: HistoryFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4"))
        let bytes = try Data(contentsOf: fixture)
        var record = OfflineRecord(video: TestData.video(youtubeId: "legacy", duration: 2), origin: RequestAuthorization.origin(base), mediaPath: "/media/legacy.mp4")
        record.status = .ready; record.kind = .mp4; record.nativePlaybackVerified = true
        record.bytes = Int64(bytes.count); record.position = 1.5
        try bytes.write(to: disk.file(for: record)!)
        try disk.save([record])
        let (coordinator, library, api) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url!.path)
            return (MockResponse.httpResponse(url: request.url!.absoluteString), MockResponse.json([
                "youtube_id": "legacy", "title": "Library copy", "media_url": "/media/legacy.mp4",
                "player": ["duration": 2, "position": 0.3, "watched": false], "streams": [["type": "video", "codec": "h264"]]
            ]))
        }
        let model = VideoDetailViewModel(videoId: "legacy", videoRepository: VideoRepositoryImpl(apiClient: api, authState: auth, history: coordinator), authState: auth, router: AppRouter(authState: auth), playbackCoordinator: coordinator)
        await model.loadVideo()
        #expect(model.isLocalPlayback && !model.isPrivatePlayback)
        #expect(model.startPosition == 0.3)
        #expect(library.records.first?.account == nil && library.records.first?.position == 1.5)
        #expect(paths == ["/api/video/legacy"])
    }

    @Test func offlineLibraryFallbackDoesNotMaskDeniedOrExpiredServerAccess() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state()
        let disk = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
        var record = OfflineRecord(video: TestData.video(youtubeId: "video"), origin: RequestAuthorization.origin(base), mediaPath: "/media/video.mp4")
        record.account = auth.playbackAccount; record.status = .ready; record.kind = .mp4
        let fixture = try #require(Bundle(for: HistoryFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4"))
        let bytes = try Data(contentsOf: fixture); record.bytes = Int64(bytes.count)
        try bytes.write(to: disk.file(for: record)!); try disk.save([record])
        let (coordinator, _, api) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let repository = VideoRepositoryImpl(apiClient: api, authState: auth, history: coordinator)
        MockResponse.setUpError(URLError(.notConnectedToInternet))
        let offline = try await repository.getVideos(page: 1, sort: "", order: "", watch: nil, channel: nil, vidType: nil)
        #expect(offline.videos.first?.playbackIdentity?.account == auth.playbackAccount)
        for status in [403, 401] {
            MockURLProtocol.requestHandler = { request in
                if request.url!.path == "/api/ping" {
                    return (MockResponse.httpResponse(url: request.url!.absoluteString), MockResponse.json(["response": "pong", "user": 7]))
                }
                return (MockResponse.httpResponse(url: request.url!.absoluteString, statusCode: status), Data())
            }
            do {
                _ = try await repository.getVideos(page: 1, sort: "", order: "", watch: nil, channel: nil, vidType: nil)
                Issue.record("A permission/authentication response must not be replaced with cached success")
            } catch let error as AppError {
                if status == 403 { if case .permissionDenied = error {} else { Issue.record("Expected permission denial") } }
                else { if case .unauthorized = error {} else { Issue.record("Expected expiry") } }
            }
        }
    }

    @Test func ownedOfflineWatchedActionRemainsScopedWhenSignedOut() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state(); let (coordinator, _, _) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: "video")
        auth.handleUnauthorized()
        try coordinator.setWatched(true, identity: identity, duration: 300)
        #expect(coordinator.history?.bookmark(for: identity)?.watched == true)
        #expect(coordinator.history?.pendingWrites(for: identity.account).count == 1)
        #expect(coordinator.history?.bookmarks.count == 1)
    }
    @Test func retryingAnotherAccountsCopyCannotDownloadWithOrExpireCurrentSession() throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state(7)
        let disk = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
        var record = OfflineRecord(video: TestData.video(), origin: RequestAuthorization.origin(base), mediaPath: "/media/video.mp4")
        record.account = auth.playbackAccount; record.status = .canceled
        try disk.save([record])
        try auth.setExistingToken("SECOND_SYNTHETIC_ONLY", serverURL: base, userID: 8)
        let (_, library, _) = make(root, auth: auth)
        library.retry(record.id)
        #expect(library.records.first?.status == .needsSignIn)
        #expect(auth.isAuthenticated && auth.userID == 8)
        #expect(MockURLProtocol.lastRequest == nil)
    }

    @Test func allCollectionViewModelsReadLiveWatchedAndRewindState() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state(); let (coordinator, _, _) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        var video = TestData.video(youtubeId: "video", duration: 300)
        let identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: "video")
        video.playbackIdentity = identity
        let router = AppRouter(authState: auth); let repository = MockVideoRepository()
        let list = VideoListViewModel(videoRepository: repository, authRepository: MockAuthRepository(), downloadRepository: MockDownloadRepository(), router: router, playbackCoordinator: coordinator)
        let channel = ChannelDetailViewModel(channelId: "channel", channelRepository: MockChannelRepository(), videoRepository: repository, router: router, playbackCoordinator: coordinator)
        let playlist = PlaylistDetailViewModel(playlistId: "playlist", playlistRepository: MockPlaylistRepository(), videoRepository: repository, router: router, playbackCoordinator: coordinator)
        list.videos = [video]; channel.videos = [video]; playlist.videos = [video]
        try coordinator.setWatched(true, identity: identity, duration: 300)
        #expect(list.videos[0].watched && channel.videos[0].watched && playlist.videos[0].watched)
        try coordinator.setWatched(false, identity: identity, duration: 300)
        let session = coordinator.session(for: identity)!
        #expect(coordinator.record(30, duration: 300, session: session, ordinal: 1))
        #expect(coordinator.record(10, duration: 300, session: session, ordinal: 2))
        #expect(list.videos[0].position == 10 && channel.videos[0].position == 10 && playlist.videos[0].position == 10)
        #expect(!list.videos[0].watched)
    }

    @Test func libraryChannelPlaylistSearchAndSimilarShareIdentityAndLocalSource() async throws {
        defer { MockResponse.tearDown() }
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let auth = try state()
        let disk = try OfflineDiskStore(root: root.appendingPathComponent("Downloads"))
        let fixture = try #require(Bundle(for: HistoryFixtureBundle.self).url(forResource: "session-playback", withExtension: "mp4"))
        let bytes = try Data(contentsOf: fixture)
        var record = OfflineRecord(video: TestData.video(youtubeId: "video", duration: 2), origin: RequestAuthorization.origin(base), mediaPath: "/media/video.mp4")
        record.account = auth.playbackAccount; record.status = .ready; record.kind = .mp4
        record.bytes = Int64(bytes.count); record.nativePlaybackVerified = true
        try bytes.write(to: disk.file(for: record)!); try disk.save([record])
        let (coordinator, _, api) = make(root, auth: auth)
        defer { coordinator.shutdown() }
        let identity = PlaybackIdentity(account: auth.playbackAccount!, videoID: "video")
        try coordinator.history?.recordPosition(0.4, duration: 2, session: coordinator.session(for: identity)!, ordinal: 1)
        let incoming: [String: Any] = ["youtube_id": "video", "title": "Fixture", "player": ["duration": 2, "position": 0, "watched": false]]
        var requests = 0
        MockURLProtocol.requestHandler = { request in
            requests += 1
            let body: Any
            if request.url!.path.contains("search") { body = ["results": ["video_results": [incoming]]] }
            else if request.url!.path.contains("similar") { body = [incoming] }
            else { body = ["data": [incoming]] }
            return (MockResponse.httpResponse(url: request.url!.absoluteString), MockResponse.json(body))
        }
        let videos = VideoRepositoryImpl(apiClient: api, authState: auth, history: coordinator)
        let library = try await videos.getVideos(page: 1, sort: "", order: "", watch: nil, channel: nil, vidType: nil).videos
        let channel = try await videos.getVideos(page: 1, sort: "", order: "", watch: nil, channel: "channel", vidType: nil).videos
        let playlist = try await PlaylistRepositoryImpl(apiClient: api, authState: auth, history: coordinator).getPlaylistVideos(playlistId: "playlist", page: 1).videos
        let search = try await SearchRepositoryImpl(apiClient: api, authState: auth, history: coordinator).search(query: "fixture", page: 1).videos
        let similar = try await videos.getSimilarVideos(videoId: "video")
        let candidates = library + channel + playlist + search + similar + coordinator.continuingVideos(in: library)
        #expect(candidates.count == 6)
        let beforePlayback = requests
        for candidate in candidates {
            #expect(candidate.playbackIdentity == identity && candidate.position == 0.4)
            let model = VideoDetailViewModel(videoId: candidate.id, videoRepository: videos, authState: auth, router: AppRouter(authState: auth), playbackCoordinator: coordinator)
            await model.loadVideo()
            #expect(model.isLocalPlayback && model.startPosition == 0.4)
        }
        #expect(requests == beforePlayback, "No detail/preloader/stream request is needed from any route")
    }
}
}
