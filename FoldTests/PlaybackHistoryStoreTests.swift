import Foundation
import Testing
@testable import Fold

@MainActor
struct PlaybackHistoryStoreTests {
    @Test func delayedVLCPreSeekSamplesCannotOverwritePausedSeekOrResumePoint() {
        var gate = PlaybackSeekGate()
        func accepts(_ seconds: Double) -> Bool { gate.accept(seconds) }
        gate.begin(120)
        #expect(!accepts(0))
        #expect(!accepts(25))
        #expect(accepts(120.1))
        #expect(accepts(121))
        gate.begin(30)
        #expect(!accepts(121))
        #expect(!accepts(29))
        #expect(accepts(30))
        gate.begin(0)
        #expect(!accepts(30))
        #expect(accepts(0))
        #expect(!accepts(.nan))
    }
    @Test func coalescedClockAfterResumeUsesPlayingTimeButPausedTimeCannotConfirmOldSamples() {
        var gate = PlaybackSeekGate()
        gate.begin(30, now: 0)
        #expect(gate.target == 30)
        let pausedOld = gate.accept(120, now: 60)
        #expect(!pausedOld)
        gate.setPlaying(true, now: 60)
        let oldAfterResume = gate.accept(120, now: 61)
        #expect(!oldAfterResume)
        let coalesced = gate.accept(39, now: 69)
        #expect(coalesced)
        gate.setPlaying(false, now: 70)
        gate.begin(0, now: 71)
        let stalePaused = gate.accept(9, now: 200)
        #expect(!stalePaused)
        let exactZero = gate.accept(0, now: 201)
        #expect(exactZero)
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("PlaybackHistoryTests-" + UUID().uuidString) }
    private func account(_ user: Int = 1, _ base: String = "https://fold.example") -> PlaybackAccount {
        PlaybackAccount(baseURL: URL(string: base)!, userID: user)!
    }
    private func identity(_ user: Int = 1, _ base: String = "https://fold.example", video: String = "same-video-id") -> PlaybackIdentity {
        PlaybackIdentity(account: account(user, base), videoID: video)
    }

    @Test func canonicalIdentitySeparatesAccountInstallationAndServerWithoutCredentials() {
        #expect(account(1, "https://FOLD.example:443/archive/") == account(1, "https://fold.example/archive"))
        #expect(account(1) != account(2))
        #expect(account(1) != account(1, "http://fold.example"))
        #expect(account(1) != account(1, "https://fold.example:8443"))
        #expect(account(1, "https://fold.example/a") != account(1, "https://fold.example/b"))
        #expect(account(1, "https://fold.example/A") != account(1, "https://fold.example/a"))
        #expect(PlaybackAccount(baseURL: URL(string: "https://user:secret@fold.example")!, userID: 1) == nil)
        #expect(PlaybackAccount(baseURL: URL(string: "https://fold.example?token=secret")!, userID: 1) == nil)
        #expect(PlaybackAccount(baseURL: URL(string: "https://fold.example")!, userID: 0) == nil)
    }

    @Test func rewindAndClockRollbackUseActionOrderRatherThanMaximumPosition() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let session = store.beginSession(for: identity())
        let forward = try store.recordPosition(130, duration: 300, session: session, ordinal: 1, at: Date(timeIntervalSince1970: 200))
        let rewind = try store.recordPosition(40, duration: 300, session: session, ordinal: 2, at: Date(timeIntervalSince1970: 100))
        #expect(rewind.position == 40 && rewind.revision > forward.revision)
        #expect(store.pendingWrites(for: account()).count == 1)
        let loaded = try PlaybackHistoryStore(root: directory)
        #expect(loaded.bookmark(for: identity()) == rewind)
    }

    @Test func accountAndServerScopesStaySeparateAcrossRelaunch() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let ids = [identity(), identity(2), identity(1, "https://other.example"), identity(1, "https://fold.example/archive")]
        for (index, id) in ids.enumerated() {
            let session = store.beginSession(for: id)
            try store.recordPosition(Double(index + 1) * 10, duration: 100, session: session, ordinal: 1)
        }
        let loaded = try PlaybackHistoryStore(root: directory)
        for (index, id) in ids.enumerated() {
            #expect(loaded.bookmark(for: id)?.position == Double(index + 1) * 10)
            #expect(loaded.pendingWrites(for: id.account).count == 1)
        }
    }

    @Test func callbackOrdinalsAndPlayerGenerationsRejectDelayedEvents() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let old = store.beginSession(for: identity())
        try store.recordPosition(100, duration: 300, session: old, ordinal: 2)
        #expect(throws: PlaybackHistoryFailure.staleSession) { try store.recordPosition(20, duration: 300, session: old, ordinal: 1) }
        let current = store.beginSession(for: identity())
        #expect(throws: PlaybackHistoryFailure.staleSession) { try store.recordPosition(200, duration: 300, session: old, ordinal: 3) }
        try store.recordPosition(30, duration: 300, session: current, ordinal: 1)
        store.endSession(old) // Closing the superseded player cannot close the new one.
        try store.recordPosition(31, duration: 300, session: current, ordinal: 2)
        store.invalidateSessions()
        #expect(throws: PlaybackHistoryFailure.staleSession) { try store.recordPosition(32, duration: 300, session: current, ordinal: 3) }
        #expect(store.bookmark(for: identity())?.position == 31)
    }

    @Test func delayedRefreshAndAcknowledgementCannotUndoNewerRewind() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let session = store.beginSession(for: identity())
        let sent = try store.recordPosition(150, duration: 300, session: session, ordinal: 1)
        let refresh = store.beginRefresh(account: account())
        let rewind = try store.recordPosition(20, duration: 300, session: session, ordinal: 2)
        #expect(try store.acknowledge(sent) == false)
        try store.observeRemote(identity: identity(), position: 150, duration: 300, watched: false, refresh: refresh)
        #expect(store.bookmark(for: identity()) == rewind)
    }

    @Test func pendingLocalActionAndUnconfirmedServerEchoSurviveRefreshAndRelaunch() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let session = store.beginSession(for: identity())
        let local = try store.recordPosition(60, duration: 300, session: session, ordinal: 1)
        try store.observeRemote(identity: identity(), position: 1, duration: 300, watched: false, refresh: store.beginRefresh(account: account()))
        #expect(store.bookmark(for: identity()) == local)
        #expect(try store.acknowledge(local))
        let loaded = try PlaybackHistoryStore(root: directory)
        try loaded.observeRemote(identity: identity(), position: 1, duration: 300, watched: false, refresh: loaded.beginRefresh(account: account()))
        #expect(loaded.bookmark(for: identity())?.position == 60)
        #expect(loaded.bookmark(for: identity())?.awaitingServerEcho == true)
        try loaded.observeRemote(identity: identity(), position: 60, duration: 300, watched: false, refresh: loaded.beginRefresh(account: account()))
        #expect(loaded.bookmark(for: identity())?.awaitingServerEcho == false)
        // No server action clock exists: a later GET (including TTL expiry) is
        // not evidence of a newer genuine viewing action.
        try loaded.observeRemote(identity: identity(), position: 45, duration: 300, watched: false, refresh: loaded.beginRefresh(account: account()))
        #expect(loaded.bookmark(for: identity())?.position == 60)
    }

    @Test func remoteSeedDoesNotCreateAnOutgoingViewingAction() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        try store.observeRemote(identity: identity(), position: 50, duration: 300, watched: false, refresh: store.beginRefresh(account: account()))
        #expect(store.bookmark(for: identity())?.position == 50)
        #expect(store.pendingWrites(for: account()).isEmpty)
        #expect(store.bookmark(for: identity())?.actedAt == nil)
        #expect(throws: PlaybackHistoryFailure.invalidData) {
            try store.observeRemote(identity: identity(2), position: 50, duration: 300, watched: false, refresh: store.beginRefresh(account: account()))
        }
        #expect(store.bookmark(for: identity(2)) == nil)
    }

    @Test func olderOverlappingReadCannotUndoNewerEchoOrRemoteObservation() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let session = store.beginSession(for: identity())
        let action = try store.recordPosition(60, duration: 300, session: session, ordinal: 1)
        #expect(try store.acknowledge(action))
        let older = store.beginRefresh(account: account())
        let echo = store.beginRefresh(account: account())
        try store.observeRemote(identity: identity(), position: 60, duration: 300, watched: false, refresh: echo)
        try store.observeRemote(identity: identity(), position: 10, duration: 300, watched: false, refresh: older)
        #expect(store.bookmark(for: identity())?.position == 60)
        let remoteOnly = identity(video: "remote-only")
        let first = store.beginRefresh(account: account())
        let second = store.beginRefresh(account: account())
        try store.observeRemote(identity: remoteOnly, position: 20, duration: 300, watched: false, refresh: second)
        try store.observeRemote(identity: remoteOnly, position: 90, duration: 300, watched: false, refresh: first)
        #expect(store.bookmark(for: remoteOnly)?.position == 20)
    }

    @Test func completionUnwatchedAndRestartInvalidateOldStopAndPreserveServerResetIntent() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let old = store.beginSession(for: identity())
        let ended = try store.recordPosition(299, duration: 300, session: old, ordinal: 1, ended: true)
        #expect(ended.watched && ended.position == 300)
        #expect(PlaybackCompletion.resumePosition(position: ended.position, duration: 300, watched: true) == 0)
        let reset = try store.setWatched(false, identity: identity(), duration: 300)
        #expect(reset.position == 0 && !reset.watched && reset.needsWatchedWrite && reset.needsProgressReset)
        #expect(throws: PlaybackHistoryFailure.staleSession) { try store.recordPosition(299, duration: 300, session: old, ordinal: 2) }
        let rewatch = store.beginSession(for: identity())
        let point = try store.recordPosition(35, duration: 300, session: rewatch, ordinal: 1)
        #expect(point.position == 35 && !point.watched && point.needsWatchedWrite && point.needsProgressReset)
        #expect(try store.acknowledge(ended) == false)
    }

    @Test func rewindToFirstSecondsIsDurableEvenThoughServerCannotRetainIt() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let session = store.beginSession(for: identity())
        try store.recordPosition(80, duration: 300, session: session, ordinal: 1)
        let rewind = try store.recordPosition(2, duration: 300, session: session, ordinal: 2)
        #expect(rewind.needsProgressReset)
        #expect(try store.acknowledge(rewind))
        try store.observeRemote(identity: identity(), position: 0, duration: 300, watched: false, refresh: store.beginRefresh(account: account()))
        #expect(try PlaybackHistoryStore(root: directory).bookmark(for: identity())?.position == 2)
    }

    @Test func invalidSamplesDoNotReplaceConfirmedBookmarkAndDurationIsClamped() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let session = store.beginSession(for: identity())
        let point = try store.recordPosition(50, duration: 300, session: session, ordinal: 1)
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            #expect(throws: PlaybackHistoryFailure.invalidPosition) { try store.recordPosition(invalid, duration: 300, session: session, ordinal: 2) }
        }
        #expect(store.bookmark(for: identity()) == point)
        let end = try store.recordPosition(999, duration: 300, session: session, ordinal: 2)
        #expect(end.position == 300 && end.watched)
    }

    @Test func completionRulesMatchServerAndPartialRewatchRetainsItsResume() {
        #expect(!PlaybackCompletion.isWatched(position: 14, duration: 30))
        #expect(PlaybackCompletion.isWatched(position: 15, duration: 30))
        #expect(!PlaybackCompletion.isWatched(position: 269, duration: 300))
        #expect(PlaybackCompletion.isWatched(position: 270, duration: 300))
        #expect(!PlaybackCompletion.isWatched(position: 1019, duration: 1200))
        #expect(PlaybackCompletion.isWatched(position: 1020, duration: 1200))
        #expect(!PlaybackCompletion.isWatched(position: 10, duration: 0))
        #expect(PlaybackCompletion.resumePosition(position: 100, duration: 300, watched: true) == 100)
        #expect(PlaybackCompletion.resumePosition(position: .nan, duration: 300, watched: false) == 0)
    }

    @Test func storageFailureIsVisibleAndDoesNotPublishOrAcknowledgeUnsavedState() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let session = store.beginSession(for: identity())
        let saved = try store.recordPosition(50, duration: 300, session: session, ordinal: 1)
        let file = directory.appendingPathComponent("history.json")
        let original = try Data(contentsOf: file)
        let protectedCopy = directory.appendingPathComponent("preserved.json")
        try original.write(to: protectedCopy)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: protectedCopy)
        #expect(throws: PlaybackHistoryFailure.storage) { try store.recordPosition(20, duration: 300, session: session, ordinal: 2) }
        #expect(throws: PlaybackHistoryFailure.storage) { try store.acknowledge(saved) }
        #expect(store.storageFailure == .storage)
        #expect(store.bookmark(for: identity()) == saved)
        #expect(try Data(contentsOf: protectedCopy) == original)
        try FileManager.default.removeItem(at: file)
        try original.write(to: file)
        // Failed persistence did not consume the event; the exact action can retry.
        let retried = try store.recordPosition(20, duration: 300, session: session, ordinal: 2)
        #expect(retried.position == 20 && store.storageFailure == nil)
    }

    @Test func emptyVideoIdentityCannotCreateAnUnreadableArchive() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackHistoryStore(root: directory)
        let session = store.beginSession(for: identity(video: ""))
        #expect(throws: PlaybackHistoryFailure.invalidData) { try store.recordPosition(20, duration: 300, session: session, ordinal: 1) }
        #expect(store.bookmarks.isEmpty)
        #expect(try PlaybackHistoryStore(root: directory).bookmarks.isEmpty)
    }

    @Test func corruptAndFutureArchivesArePreservedInsteadOfResettingHistory() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PlaybackHistoryStore(root: directory)
        let file = directory.appendingPathComponent("history.json")
        let corrupt = Data("old bookmark that must not be overwritten".utf8)
        try corrupt.write(to: file)
        #expect(throws: PlaybackHistoryFailure.invalidData) { try PlaybackHistoryStore(root: directory) }
        #expect(try Data(contentsOf: file) == corrupt)
        let future = Data(#"{"version":2,"revision":0,"bookmarks":[]}"#.utf8)
        try future.write(to: file)
        #expect(throws: PlaybackHistoryFailure.unsupportedVersion) { try PlaybackHistoryStore(root: directory) }
        #expect(try Data(contentsOf: file) == future)
    }
}
