import Foundation

nonisolated struct PlaybackBookmark: Codable, Hashable, Sendable {
    let identity: PlaybackIdentity
    var position: Double
    var duration: Double
    var watched: Bool
    /// Monotonic on this device. Wall-clock changes cannot make a rewind lose.
    var revision: UInt64
    var actedAt: Date?
    var pendingSync: Bool
    var awaitingServerEcho: Bool
    /// Watched writes clear server progress; synchronize them before position.
    var needsWatchedWrite: Bool
    /// Server ignores <=5-second POSTs; deleting its old point is necessary.
    var needsProgressReset: Bool
}

nonisolated enum PlaybackHistoryFailure: Error, Equatable {
    case invalidData, unsupportedVersion, staleSession, invalidPosition, storage
}

nonisolated struct PlaybackSession: Hashable, Sendable {
    let identity: PlaybackIdentity
    let id: UUID
}

nonisolated struct PlaybackRefresh: Sendable {
    let account: PlaybackAccount
    let revision: UInt64
    let order: UInt64
}

/// One durable journal for both presentation surfaces and both player engines.
/// Local actions are committed before publication; network acknowledgement is a
/// separate operation. Removing a download never touches this store.
@Observable
final class PlaybackHistoryStore {
    private(set) var bookmarks: [PlaybackIdentity: PlaybackBookmark]
    private(set) var deletions: [PlaybackIdentity: UInt64] = [:]
    private(set) var storageFailure: PlaybackHistoryFailure?
    @ObservationIgnored private var readOrder: UInt64 = 0
    @ObservationIgnored private var acceptedReadOrders: [PlaybackIdentity: UInt64] = [:]
    @ObservationIgnored private var revision: UInt64
    @ObservationIgnored private let file: URL
    @ObservationIgnored private var sessions: [PlaybackIdentity: (id: UUID, ordinal: UInt64)] = [:]

    private struct Archive: Codable {
        let version: Int
        let revision: UInt64
        let bookmarks: [PlaybackBookmark]
        var deletions: [Deletion]? = nil
    }
    private struct Deletion: Codable { let identity: PlaybackIdentity; let revision: UInt64 }

    init(root: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw PlaybackHistoryFailure.storage }
        var directory = root
        var protection = URLResourceValues(); protection.isExcludedFromBackup = true
        try directory.setResourceValues(protection)
        try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
        file = root.appendingPathComponent("history.json")
        if files.fileExists(atPath: file.path) {
            let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw PlaybackHistoryFailure.storage }
            let archive: Archive
            do { archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file)) }
            catch { throw PlaybackHistoryFailure.invalidData }
            guard archive.version == 1 else { throw PlaybackHistoryFailure.unsupportedVersion }
            var loaded: [PlaybackIdentity: PlaybackBookmark] = [:]
            for bookmark in archive.bookmarks {
                guard !bookmark.identity.videoID.isEmpty, bookmark.identity.account.userID > 0,
                      let url = URL(string: bookmark.identity.account.server),
                      PlaybackAccount(baseURL: url, userID: bookmark.identity.account.userID) == bookmark.identity.account,
                      bookmark.position.isFinite, bookmark.position >= 0,
                      bookmark.duration.isFinite, bookmark.duration >= 0,
                      bookmark.revision <= archive.revision, loaded[bookmark.identity] == nil else {
                    throw PlaybackHistoryFailure.invalidData
                }
                loaded[bookmark.identity] = bookmark
            }
            bookmarks = loaded; revision = archive.revision
            for deletion in archive.deletions ?? [] {
                guard !deletion.identity.videoID.isEmpty, deletion.identity.account.userID > 0,
                      let url = URL(string: deletion.identity.account.server),
                      PlaybackAccount(baseURL: url, userID: deletion.identity.account.userID) == deletion.identity.account,
                      deletion.revision > 0, deletion.revision <= archive.revision,
                      loaded[deletion.identity] == nil, deletions[deletion.identity] == nil else { throw PlaybackHistoryFailure.invalidData }
                deletions[deletion.identity] = deletion.revision
            }
        } else { bookmarks = [:]; revision = 0 }
    }

    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PlaybackHistory-v1", isDirectory: true)
    }

    func bookmark(for identity: PlaybackIdentity) -> PlaybackBookmark? { bookmarks[identity] }

    func beginSession(for identity: PlaybackIdentity) -> PlaybackSession {
        let session = PlaybackSession(identity: identity, id: UUID())
        sessions[identity] = (session.id, 0)
        return session
    }

    func endSession(_ session: PlaybackSession) {
        if sessions[session.identity]?.id == session.id { sessions[session.identity] = nil }
    }

    func invalidateSessions() { sessions.removeAll() }

    /// Ordinals are captured at the observation/action source, before starting
    /// asynchronous work. An old player or delayed callback cannot rewind a new
    /// session. A genuine backwards seek with a newer ordinal does replace it.
    @discardableResult
    func recordPosition(_ seconds: Double, duration: Double, session: PlaybackSession,
                        ordinal: UInt64, ended: Bool = false, at date: Date = .now) throws -> PlaybackBookmark {
        guard let active = sessions[session.identity], active.id == session.id, ordinal > active.ordinal else {
            throw PlaybackHistoryFailure.staleSession
        }
        guard deletions[session.identity] == nil else { throw PlaybackHistoryFailure.staleSession }
        guard seconds.isFinite, seconds >= 0, duration.isFinite, duration >= 0 else { throw PlaybackHistoryFailure.invalidPosition }
        let previous = bookmarks[session.identity]
        let total = duration > 0 ? duration : (previous?.duration ?? 0)
        let position = ended && total > 0 ? total : (total > 0 ? min(seconds, total) : seconds)
        let watched = (previous?.watched ?? false) || ended || PlaybackCompletion.isWatched(position: position, duration: total)
        if let previous, previous.position == position, previous.duration == total, previous.watched == watched {
            sessions[session.identity] = (session.id, ordinal)
            return previous
        }
        let bookmark = PlaybackBookmark(identity: session.identity, position: position, duration: total,
            watched: watched, revision: try nextRevision(), actedAt: date, pendingSync: true, awaitingServerEcho: false,
            needsWatchedWrite: (previous?.needsWatchedWrite ?? false) || watched != (previous?.watched ?? false),
            needsProgressReset: (previous?.needsProgressReset ?? false) || position <= 5)
        try commit(bookmark)
        sessions[session.identity] = (session.id, ordinal)
        return bookmark
    }

    @discardableResult
    func setWatched(_ watched: Bool, identity: PlaybackIdentity, duration: Double, at date: Date = .now) throws -> PlaybackBookmark {
        guard deletions[identity] == nil else { throw PlaybackHistoryFailure.staleSession }
        guard duration.isFinite, duration >= 0 else { throw PlaybackHistoryFailure.invalidPosition }
        let total = duration > 0 ? duration : (bookmarks[identity]?.duration ?? 0)
        let bookmark = PlaybackBookmark(identity: identity, position: watched ? total : 0, duration: total,
            watched: watched, revision: try nextRevision(), actedAt: date, pendingSync: true,
            awaitingServerEcho: false, needsWatchedWrite: true, needsProgressReset: true)
        try commit(bookmark)
        // A late pause/stop from the old player must not undo this explicit action.
        sessions[identity] = nil
        return bookmark
    }

    func beginRefresh(account: PlaybackAccount) -> PlaybackRefresh {
        readOrder &+= 1
        return PlaybackRefresh(account: account, revision: revision, order: readOrder)
    }

    /// The API exposes no action timestamp/version. Keep a local action until it
    /// is acknowledged AND observed back from the server. Never use max(position).
    func observeRemote(identity: PlaybackIdentity, position: Double, duration: Double, watched: Bool,
                       refresh: PlaybackRefresh) throws {
        guard !rejectsRead(identity, refresh: refresh) else { throw PlaybackHistoryFailure.staleSession }
        guard identity.account == refresh.account, position.isFinite, position >= 0, duration.isFinite, duration >= 0 else {
            throw PlaybackHistoryFailure.invalidData
        }
        guard refresh.order >= (acceptedReadOrders[identity] ?? 0) else { return }
        if var previous = bookmarks[identity] {
            guard previous.revision <= refresh.revision, !previous.pendingSync else { return }
            if previous.awaitingServerEcho {
                guard abs(previous.position - position) < 0.5, previous.watched == watched else { return }
                previous.awaitingServerEcho = false
                try commit(previous)
                acceptedReadOrders[identity] = refresh.order
                return
            }
            // TubeArchivist exposes no viewing-action timestamp and may expire
            // watched resume entries. An unversioned GET cannot prove it is a
            // newer action than a genuine local view/rewind/reset, even after echo.
            if previous.actedAt != nil { return }
            if previous.position == position, previous.duration == duration, previous.watched == watched {
                acceptedReadOrders[identity] = refresh.order
                return
            }
        }
        let bookmark = PlaybackBookmark(identity: identity, position: duration > 0 ? min(position, duration) : position,
            duration: duration, watched: watched, revision: try nextRevision(), actedAt: nil,
            pendingSync: false, awaitingServerEcho: false, needsWatchedWrite: false, needsProgressReset: false)
        try commit(bookmark)
        acceptedReadOrders[identity] = refresh.order
    }

    func pendingWrites(for account: PlaybackAccount) -> [PlaybackBookmark] {
        bookmarks.values.filter { $0.identity.account == account && $0.pendingSync }.sorted { $0.revision < $1.revision }
    }

    func rejectsRead(_ identity: PlaybackIdentity, refresh: PlaybackRefresh) -> Bool {
        deletions[identity].map { refresh.revision < $0 } ?? false
    }

    /// Persist deletion before removing bytes. This also serves as a recovery
    /// marker for interrupted/failed local cleanup on the next launch.
    func markDeleted(_ identity: PlaybackIdentity) throws {
        guard !identity.videoID.isEmpty else { throw PlaybackHistoryFailure.invalidData }
        sessions[identity] = nil
        if deletions[identity] != nil { return }
        var updated = bookmarks; updated[identity] = nil
        var removed = deletions; let next = try nextRevision(); removed[identity] = next
        try persist(updated, deletions: removed, revision: next)
        acceptedReadOrders[identity] = nil
    }

    /// A response for revision N never acknowledges revision N+1, even if that
    /// newer action rewound to a smaller position or reset it to zero.
    @discardableResult
    func acknowledge(_ sent: PlaybackBookmark) throws -> Bool {
        guard var current = bookmarks[sent.identity], current.revision == sent.revision, current.pendingSync else { return false }
        current.pendingSync = false
        current.awaitingServerEcho = true
        current.needsWatchedWrite = false
        current.needsProgressReset = false
        try commit(current)
        return true
    }

    private func nextRevision() throws -> UInt64 {
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else { throw PlaybackHistoryFailure.storage }
        return next
    }

    private func commit(_ bookmark: PlaybackBookmark) throws {
        guard !bookmark.identity.videoID.isEmpty else { throw PlaybackHistoryFailure.invalidData }
        var updated = bookmarks
        updated[bookmark.identity] = bookmark
        let next = max(revision, bookmark.revision)
        var removed = deletions; removed[bookmark.identity] = nil
        try persist(updated, deletions: removed, revision: next)
    }

    private func persist(_ updated: [PlaybackIdentity: PlaybackBookmark], deletions removed: [PlaybackIdentity: UInt64], revision next: UInt64) throws {
        do {
            // Refuse a symlink that appeared after initialization too.
            // Foundation URLs cache resource values. Recreate the URL so a
            // repaired file can retry and a newly introduced link is rechecked.
            let destination = URL(fileURLWithPath: file.path)
            if (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw PlaybackHistoryFailure.storage }
            let archive = Archive(version: 1, revision: next, bookmarks: updated.values.sorted { $0.revision < $1.revision },
                deletions: removed.map { Deletion(identity: $0.key, revision: $0.value) })
            try JSONEncoder().encode(archive).write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            bookmarks = updated; deletions = removed; revision = next; storageFailure = nil
        } catch {
            storageFailure = .storage
            throw PlaybackHistoryFailure.storage
        }
    }
}
