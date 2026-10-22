import Foundation
import AVFoundation
import Network
import SwiftUI

nonisolated struct PlaybackReadContext {
    let authorizationID: UUID
    let refresh: PlaybackRefresh
}

protocol LibraryDeletionObserver: AnyObject {
    @MainActor func libraryVideoDeleted(_ identity: PlaybackIdentity)
}
private final class WeakLibraryDeletionObserver {
    weak var value: (any LibraryDeletionObserver)?
    init(_ value: any LibraryDeletionObserver) { self.value = value }
}

@Observable
final class PlaybackCoordinator {
    let history: PlaybackHistoryStore?
    private(set) var errorMessage: String?
    private(set) var syncDeferred = false
    @ObservationIgnored private var nextSyncAttempt = Date.distantPast
    @ObservationIgnored private let auth: AuthState
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let library: OfflineLibrary
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var verification: (id: UUID, generation: UUID, task: Task<PlaybackAccount, Error>)?
    @ObservationIgnored private var syncGeneration = UUID()
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var deleting: Set<PlaybackIdentity> = []
    @ObservationIgnored private var pendingCleanup: Set<PlaybackIdentity> = []
    @ObservationIgnored private var cleanupErrorShown = false
    @ObservationIgnored private var deletionObservers: [WeakLibraryDeletionObserver] = []

    init(auth: AuthState, api: APIClient, library: OfflineLibrary, root: URL? = nil, monitorNetwork: Bool = true) {
        self.auth = auth; self.api = api; self.library = library
        do { history = try PlaybackHistoryStore(root: try root ?? PlaybackHistoryStore.defaultRoot()) }
        catch { history = nil; errorMessage = String(localized: "history_storage_error") }
        if monitorNetwork {
            let monitor = NWPathMonitor(); self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in self?.requestSync(force: true) }
            }
            monitor.start(queue: DispatchQueue(label: "Fold.PlaybackConnectivity"))
        }
        reconcileDeletedCopies()
    }
    deinit { monitor?.cancel(); syncTask?.cancel(); verification?.task.cancel() }

    /// Revalidate a persisted association before importing another server user's
    /// response. Coalesce with reconnect sync; a transient outage still permits
    /// reading this device's already-scoped offline copy.
    func confirmAccount() async throws -> PlaybackAccount {
        guard let authorization = auth.authorization else { throw AppError.unauthorized }
        if auth.accountConfirmed, let account = auth.playbackAccount { return account }
        if let verification, verification.id == authorization.id { return try await verification.task.value }
        let task = Task { [api, auth] () throws -> PlaybackAccount in
            let ping: PingDTO = try await api.request(endpoint: .ping)
            try Task.checkCancellation()
            guard auth.authorization?.id == authorization.id else { throw CancellationError() }
            guard ping.response == "pong", let user = ping.user, user > 0 else { throw AppError.unauthorized }
            auth.setVerifiedAccount(user, authorizationID: authorization.id)
            guard let account = auth.playbackAccount else { throw AppError.unauthorized }
            return account
        }
        let generation = UUID()
        verification = (authorization.id, generation, task)
        defer { if verification?.generation == generation { verification = nil } }
        let account = try await task.value
        try Task.checkCancellation()
        return account
    }

    func prepareRead() async throws -> PlaybackReadContext? {
        if !auth.accountConfirmed {
            do { _ = try await confirmAccount() }
            catch {
                if let appError = error as? AppError {
                    switch appError {
                    case .network: break
                    case .serverError(let code, _) where code >= 500: break
                    default: throw error
                    }
                } else { throw error }
            }
        }
        return beginRead()
    }

    func beginRead() -> PlaybackReadContext? {
        guard let history, let account = auth.playbackAccount, let id = auth.authorization?.id else { return nil }
        return PlaybackReadContext(authorizationID: id, refresh: history.beginRefresh(account: account))
    }

    func accept(_ video: Video, context: PlaybackReadContext?) throws -> Video {
        guard let context, let history else { return video }
        guard auth.authorization?.id == context.authorizationID, auth.playbackAccount == context.refresh.account,
              !Task.isCancelled else { throw CancellationError() }
        // A server response obtained while account revalidation was unavailable
        // cannot be attributed to the cached offline owner.
        guard auth.accountConfirmed else { return video }
        let identity = PlaybackIdentity(account: context.refresh.account, videoID: video.youtubeId)
        guard !pendingCleanup.contains(identity), !history.rejectsRead(identity, refresh: context.refresh) else {
            throw AppError.serverError(statusCode: 404, message: String(localized: "library_video_deleted"))
        }
        do {
            try history.observeRemote(identity: identity, position: video.position, duration: Double(video.duration),
                                      watched: video.watched, refresh: context.refresh)
        } catch { errorMessage = String(localized: "history_storage_error") }
        var result = video; result.playbackIdentity = identity
        return project(result)
    }

    func project(_ video: Video) -> Video {
        if let identity = video.playbackIdentity,
           pendingCleanup.contains(identity) || history?.deletions[identity] != nil {
            var deleted = video; deleted.position = 0; deleted.progress = 0; deleted.watched = false
            return deleted
        }
        guard let identity = video.playbackIdentity, let history,
              let bookmark = history.bookmark(for: identity) else { return video }
        // A stale view retained after switching accounts cannot expose its history.
        guard auth.playbackAccount == nil || auth.playbackAccount == identity.account else {
            var hidden = video; hidden.position = 0; hidden.progress = 0; hidden.watched = false
            return hidden
        }
        var result = video
        result.position = bookmark.position
        result.progress = bookmark.duration > 0 ? min(100, bookmark.position / bookmark.duration * 100) : 0
        result.watched = bookmark.watched
        return result
    }

    func display(_ record: OfflineRecord) -> Video {
        var video = record.displayVideo
        if let account = record.account {
            video.playbackIdentity = PlaybackIdentity(account: account, videoID: record.videoID)
            if let current = auth.playbackAccount, current != account {
                video.position = 0; video.progress = 0; video.watched = false
                return video
            }
            return project(video)
        }
        return video // Unattributed legacy bookmark remains device-only.
    }

    func identity(for record: OfflineRecord) -> PlaybackIdentity? {
        guard let account = record.account,
              auth.playbackAccount == nil || auth.playbackAccount == account else { return nil }
        return PlaybackIdentity(account: account, videoID: record.videoID)
    }

    func session(for identity: PlaybackIdentity) -> PlaybackSession? { history?.beginSession(for: identity) }

    @discardableResult
    func record(_ seconds: Double, duration: Double, session: PlaybackSession, ordinal: UInt64, ended: Bool = false) -> Bool {
        guard !pendingCleanup.contains(session.identity) else { return false }
        guard let history else { errorMessage = String(localized: "history_storage_error"); return false }
        guard auth.playbackAccount == nil || auth.playbackAccount == session.identity.account else { return false }
        do {
            try history.recordPosition(seconds, duration: duration, session: session, ordinal: ordinal, ended: ended)
            errorMessage = nil
            requestSync()
            return true
        } catch PlaybackHistoryFailure.staleSession { return false }
        catch { errorMessage = String(localized: "history_storage_error"); return false }
    }

    func setWatched(_ watched: Bool, videoID: String, duration: Double = 0) throws {
        guard let account = auth.playbackAccount, let history else { throw PlaybackHistoryFailure.storage }
        try setWatched(watched, identity: PlaybackIdentity(account: account, videoID: videoID), duration: duration)
    }

    func setWatched(_ watched: Bool, identity: PlaybackIdentity, duration: Double) throws {
        guard !pendingCleanup.contains(identity) else { throw PlaybackHistoryFailure.staleSession }
        guard auth.playbackAccount == nil || auth.playbackAccount == identity.account, let history else { throw PlaybackHistoryFailure.storage }
        try history.setWatched(watched, identity: identity, duration: duration)
        requestSync()
    }

    /// Always resolve before starting any network preloader or streaming player.
    /// A legacy file can only be linked after the user explicitly identifies its account.
    func localSource(videoID: String, recordID: UUID? = nil, matching video: Video? = nil) async -> LocalVideoPlayback? {
        if auth.isAuthenticated && !auth.accountConfirmed {
            do { _ = try await prepareRead() } catch { return nil }
        }
        let account = auth.playbackAccount
        if let account {
            let identity = PlaybackIdentity(account: account, videoID: videoID)
            if pendingCleanup.contains(identity) || history?.deletions[identity] != nil { return nil }
        }
        guard let record = library.records.first(where: {
            if let recordID { return $0.id == recordID && ($0.account == nil || account == nil || $0.account == account) }
            guard $0.videoID == videoID else { return false }
            if $0.account != nil { return $0.account == account }
            guard let video, let account, video.playbackIdentity?.account == account,
                  let url = URL(string: video.mediaUrl), url.query == nil, url.fragment == nil,
                  RequestAuthorization.origin(url) == $0.origin else { return false }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == $0.mediaPath
        }), library.disk?.isValidPlaybackFile(record) == true, let url = library.localURL(for: record) else { return nil }
        if record.nativePlaybackVerified == true {
            guard (try? await AVURLAsset(url: url).load(.isPlayable)) == true else { return nil }
        }
        guard !Task.isCancelled, library.localURL(for: record) == url else { return nil }
        return LocalVideoPlayback(record: record, library: library)
    }

    func artwork(for video: Video) -> LocalVideoArtwork? {
        guard let identity = video.playbackIdentity,
              auth.playbackAccount == nil || auth.playbackAccount == identity.account,
              let record = library.records.first(where: { $0.account == identity.account && $0.videoID == identity.videoID }) else { return nil }
        return LocalVideoArtwork(thumbnail: library.thumbnailURL(record.id), channel: library.channelArtworkURL(record.id), revision: library.artworkRevision)
    }

    func offlineVideos(context: PlaybackReadContext, watch: String?, channel: String?, vidType: String?) -> [Video] {
        guard auth.authorization?.id == context.authorizationID, auth.playbackAccount == context.refresh.account else { return [] }
        return library.records.filter { $0.account == context.refresh.account && $0.status == .ready }.map { record in
            var video = record.libraryVideo; video.playbackIdentity = identity(for: record)
            return project(video)
        }.filter { video in
            (channel == nil || video.channelId == channel) && (vidType == nil || video.vidType == vidType) &&
            (watch != "watched" || video.watched) &&
            (watch != "unwatched" || !video.watched || PlaybackCompletion.resumePosition(position: video.position, duration: Double(video.duration), watched: video.watched) > 0) &&
            (watch != "continue" || PlaybackCompletion.resumePosition(position: video.position, duration: Double(video.duration), watched: video.watched) > 0)
        }
    }

    func continuingVideos(in videos: [Video]) -> [Video] {
        let account = auth.playbackAccount
        var candidates = videos.map(project)
        let ids = Set(videos.map(\.id))
        for record in library.records where record.account == account && account != nil && !ids.contains(record.videoID) {
            var video = record.libraryVideo
            video.playbackIdentity = identity(for: record)
            candidates.append(project(video))
        }
        return candidates.filter {
            if let identity = $0.playbackIdentity,
               pendingCleanup.contains(identity) || history?.deletions[identity] != nil { return false }
            return PlaybackCompletion.resumePosition(position: $0.position, duration: Double($0.duration), watched: $0.watched) > 0
        }.sorted {
            let a = $0.playbackIdentity.flatMap { history?.bookmark(for: $0)?.revision } ?? 0
            let b = $1.playbackIdentity.flatMap { history?.bookmark(for: $0)?.revision } ?? 0
            return a > b
        }
    }

    func shutdown() {
        monitor?.cancel(); monitor = nil
        syncTask?.cancel(); syncTask = nil; syncGeneration = UUID()
        verification?.task.cancel(); verification = nil
        history?.invalidateSessions()
    }

    func connectionChanged() {
        syncTask?.cancel(); syncTask = nil; syncGeneration = UUID()
        verification?.task.cancel(); verification = nil
        history?.invalidateSessions()
        nextSyncAttempt = .distantPast
        requestSync(force: true)
    }

    func requestSync(force: Bool = false) {
        reconcileDeletedCopies()
        guard force || Date() >= nextSyncAttempt else { return }
        guard syncTask == nil, let account = auth.playbackAccount,
              let authorization = auth.authorization, let history,
              !history.pendingWrites(for: account).isEmpty else { return }
        let generation = UUID(); syncGeneration = generation
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.syncGeneration == generation { self.syncTask = nil } }
            // Coalesce adjacent time/seek events; locally they are already durable.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            if !self.auth.accountConfirmed {
                do {
                    let confirmed = try await self.confirmAccount()
                    guard authorization.id == self.auth.authorization?.id, !Task.isCancelled, confirmed == account else { return }
                } catch {
                    guard self.syncGeneration == generation, !Task.isCancelled, self.auth.authorization?.id == authorization.id else { return }
                    self.syncDeferred = true; self.nextSyncAttempt = Date().addingTimeInterval(10)
                    return
                }
            }
            var attempted: Set<PlaybackIdentity> = []
            var writes = 0
            while writes < 32, !Task.isCancelled, authorization.id == self.auth.authorization?.id,
                  account == self.auth.playbackAccount, self.auth.accountConfirmed {
                guard let sent = history.pendingWrites(for: account).first(where: {
                    !attempted.contains($0.identity) && !self.deleting.contains($0.identity) && !self.pendingCleanup.contains($0.identity)
                }) else { break }
                writes += 1
                do {
                    try await self.send(sent, authorizationID: authorization.id)
                    guard authorization.id == self.auth.authorization?.id, account == self.auth.playbackAccount, !Task.isCancelled else { return }
                    let acknowledged = try history.acknowledge(sent)
                    // If a newer action arrived during the request, send it in order.
                    if acknowledged { attempted.insert(sent.identity); self.syncDeferred = false; self.nextSyncAttempt = .distantPast }
                } catch {
                    guard self.syncGeneration == generation, !Task.isCancelled, self.auth.authorization?.id == authorization.id else { return }
                    // Keep the journal. Permissions, deleted server media and outages
                    // cannot erase local history or cause an infinite retry loop.
                    attempted.insert(sent.identity)
                    self.syncDeferred = true; self.nextSyncAttempt = Date().addingTimeInterval(10)
                }
            }
        }
    }

    private func send(_ sent: PlaybackBookmark, authorizationID: UUID) async throws {
        func check() throws {
            try Task.checkCancellation()
            guard auth.authorization?.id == authorizationID, auth.playbackAccount == sent.identity.account,
                  auth.accountConfirmed, !deleting.contains(sent.identity), !pendingCleanup.contains(sent.identity),
                  history?.deletions[sent.identity] == nil else { throw CancellationError() }
        }
        try check()
        if sent.needsWatchedWrite {
            try await api.requestVoid(endpoint: .setWatched, body: WatchedDTO(id: sent.identity.videoID, isWatched: sent.watched), expectedAuthorizationID: authorizationID)
        }
        try check()
        if sent.needsProgressReset || sent.position <= 5 {
            try await api.requestVoid(endpoint: .deleteVideoProgress(id: sent.identity.videoID), expectedAuthorizationID: authorizationID)
        }
        try check()
        if sent.position > 5 {
            try await api.requestVoid(endpoint: .videoProgress(id: sent.identity.videoID), body: VideoProgressDTO(position: sent.position), expectedAuthorizationID: authorizationID)
        }
    }

    func registerDeletionObserver(_ observer: any LibraryDeletionObserver) {
        deletionObservers.removeAll { $0.value == nil }
        deletionObservers.append(WeakLibraryDeletionObserver(observer))
    }

    var deletionConnectionID: UUID? { auth.authorization?.id }

    /// Delete on the captured connection first. Failure/cancellation leaves local
    /// media and history intact. A confirmed response always finishes cleanup for
    /// that captured account, even if the user switched accounts while waiting.
    func deleteVideo(id: String) async throws {
        guard history != nil else { throw PlaybackHistoryFailure.storage }
        let connection = auth.authorization?.id
        let account = try await confirmAccount()
        guard let authorization = auth.authorization, authorization.id == connection, auth.playbackAccount == account else { throw CancellationError() }
        let identity = PlaybackIdentity(account: account, videoID: id)
        guard !deleting.contains(identity) else { throw CancellationError() }
        deleting.insert(identity)
        defer { deleting.remove(identity); requestSync() }
        // Stop any old progress drain before DELETE, retaining its durable outbox
        // if deletion fails. A late acknowledgement cannot resurrect the journal.
        syncTask?.cancel(); syncTask = nil; syncGeneration = UUID()
        try await api.confirmVideoDeletion(id: id, authorizationID: authorization.id)
        syncTask?.cancel(); syncTask = nil; syncGeneration = UUID()
        pendingCleanup.insert(identity)
        reconcileDeletedCopies()
        // Existing cache is a playback optimization, never the durable download.
        await VideoCachePreloader.shared.removeDeletedVideo(id, authorization: authorization)
        guard auth.authorization?.id == authorization.id else { throw CancellationError() }
    }

    private func reconcileDeletedCopies() {
        guard let history else { return }
        let targets = Set(history.deletions.keys).union(pendingCleanup).filter { identity in
            pendingCleanup.contains(identity) || library.records.contains { $0.account == identity.account && $0.videoID == identity.videoID }
        }
        for identity in targets {
            pendingCleanup.insert(identity)
            deletionObservers.removeAll { $0.value == nil }
            for observer in deletionObservers { observer.value?.libraryVideoDeleted(identity) }
            do {
                try history.markDeleted(identity)
                guard library.removeCopies(for: identity) else { throw PlaybackHistoryFailure.storage }
                pendingCleanup.remove(identity)
            } catch { cleanupErrorShown = true; errorMessage = String(localized: "library_delete_cleanup_pending") }
        }
        if pendingCleanup.isEmpty, cleanupErrorShown { cleanupErrorShown = false; errorMessage = nil }
    }
}

private struct PlaybackCoordinatorKey: EnvironmentKey {
    static let defaultValue: PlaybackCoordinator? = nil
}
extension EnvironmentValues {
    var playbackCoordinator: PlaybackCoordinator? {
        get { self[PlaybackCoordinatorKey.self] }
        set { self[PlaybackCoordinatorKey.self] = newValue }
    }
}
