import Foundation

@Observable
final class OfflineLibrary {
    private(set) var records: [OfflineRecord] = []
    private(set) var storageError: String?
    private(set) var refreshingDetails: Set<UUID> = []
    private(set) var artworkRevision = 0
    @ObservationIgnored private let authState: AuthState
    @ObservationIgnored let disk: OfflineDiskStore?
    @ObservationIgnored private let delegate: OfflineTransferDelegate?
    @ObservationIgnored private let session: URLSession?
    @ObservationIgnored private let artworkConfiguration: URLSessionConfiguration
    @ObservationIgnored private var tasks: [UUID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var authorizations: [UUID: RequestAuthorization] = [:]
    @ObservationIgnored private var lastProgressSave: Date = .distantPast
    @ObservationIgnored private var artworkTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var artworkAttempts: [UUID: UUID] = [:]

    init(authState: AuthState, root: URL? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        self.authState = authState
        artworkConfiguration = configuration.copy() as! URLSessionConfiguration
        var created: OfflineDiskStore?
        do {
            let store = try OfflineDiskStore(root: try root ?? OfflineDiskStore.defaultRoot())
            var loaded = try store.load()
            guard Set(loaded.map(\.id)).count == loaded.count else { throw OfflineFailure.storage }
            for i in loaded.indices {
                if loaded[i].status == .downloading {
                    loaded[i].status = .interrupted; loaded[i].attempt = nil; loaded[i].bytes = 0
                } else if loaded[i].status == .ready && !store.exists(loaded[i]) {
                    loaded[i].status = .failed; loaded[i].failure = .missingFile; loaded[i].bytes = 0
                }
            }
            try store.save(loaded)
            try store.cleanOrphans(keeping: loaded)
            records = loaded; created = store
        } catch { storageError = OfflineFailure.storage.message }
        disk = created
        delegate = created.map(OfflineTransferDelegate.init)
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = delegate.map { URLSession(configuration: configuration, delegate: $0, delegateQueue: queue) }
        delegate?.owner = self
    }
    deinit { session?.invalidateAndCancel(); artworkTasks.values.forEach { $0.cancel() } }

    var totalSize: String { ByteCountFormatter.string(fromByteCount: records.filter { $0.status == .ready }.reduce(0) { $0 + $1.bytes }, countStyle: .file) }
    func record(for video: Video) -> OfflineRecord? {
        guard let url = URL(string: video.mediaUrl) else { return nil }
        return records.first { $0.videoID == video.youtubeId && $0.origin == RequestAuthorization.origin(url) }
    }
    func localURL(for record: OfflineRecord) -> URL? {
        guard record.status == .ready, disk?.exists(record) == true else { return nil }
        return disk?.file(for: record)
    }
    @discardableResult func enqueue(_ video: Video) -> UUID? {
        if let existing = record(for: video) {
            if existing.status != .ready && existing.status != .downloading { retry(existing.id) }
            return existing.id
        }
        guard let auth = authState.authorization, let url = URL(string: video.mediaUrl),
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else {
            storageError = OfflineFailure.signIn.message; return nil
        }
        let record = OfflineRecord(video: video, origin: RequestAuthorization.origin(auth.baseURL), mediaPath: path)
        // Validate the actual media URL before storing a candidate, including origin and query restrictions.
        do { _ = try Self.request(url: url, authorization: auth) }
        catch { storageError = OfflineFailure.signIn.message; return nil }
        records.insert(record, at: 0)
        guard persist() else { records.removeAll { $0.id == record.id }; return nil }
        retry(record.id)
        return record.id
    }
    func retry(_ id: UUID) {
        guard let i = records.firstIndex(where: { $0.id == id }), records[i].status != .ready,
              let disk, let session else { return }
        if let attempt = records[i].attempt, tasks[attempt] != nil { return }
        do {
            guard let auth = authState.authorization, let url = URL(string: records[i].origin + records[i].mediaPath) else { throw OfflineFailure.signIn }
            let request = try Self.request(url: url, authorization: auth)
            try disk.checkCapacity(records[i].expectedSize)
            let attempt = UUID()
            records[i].status = .downloading; records[i].failure = nil; records[i].bytes = 0
            records[i].totalBytes = records[i].expectedSize; records[i].attempt = attempt
            guard persist() else { records[i].status = .failed; records[i].failure = .storage; records[i].attempt = nil; return }
            let task = session.downloadTask(with: request)
            task.taskDescription = id.uuidString + "/" + attempt.uuidString
            task.countOfBytesClientExpectsToReceive = records[i].expectedSize
            tasks[attempt] = task; authorizations[attempt] = auth
            task.resume()
            queueArtwork(id)
        } catch {
            records[i].status = (error as? OfflineFailure) == .signIn ? .needsSignIn : .failed
            records[i].failure = (error as? OfflineFailure) ?? .storage
            records[i].attempt = nil
            persist()
            if (error as? OfflineFailure) == .signIn, let auth = authState.authorization,
               RequestAuthorization.origin(auth.baseURL) == records[i].origin {
                NotificationCenter.default.post(name: .taAuthUnauthorized, object: nil, userInfo: ["authorizationID": auth.id])
            }
        }
    }
    nonisolated static func request(url: URL, authorization: RequestAuthorization) throws -> URLRequest {
        guard url.query == nil, url.fragment == nil, ["http", "https"].contains(url.scheme),
              url.user == nil, url.password == nil else { throw OfflineFailure.signIn }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        do { try authorization.apply(to: &request) } catch { throw OfflineFailure.signIn }
        guard request.value(forHTTPHeaderField: "Authorization") != nil || request.value(forHTTPHeaderField: "Cookie") != nil else { throw OfflineFailure.signIn }
        return request
    }
    func cancel(_ id: UUID) { interrupt(id, status: .canceled) }
    func pauseAll() {
        artworkTasks.values.forEach { $0.cancel() }; artworkTasks.removeAll(); artworkAttempts.removeAll()
        for record in records where record.status == .downloading { interrupt(record.id, status: .interrupted) }
    }
    func authorizationChanged() {
        artworkTasks.values.forEach { $0.cancel() }; artworkTasks.removeAll(); artworkAttempts.removeAll()
        for record in records where record.status == .downloading {
            if record.attempt.flatMap({ authorizations[$0]?.id }) != authState.authorization?.id {
                interrupt(record.id, status: .needsSignIn)
            }
        }
    }
    private func interrupt(_ id: UUID, status: OfflineStatus) {
        guard let i = records.firstIndex(where: { $0.id == id }), records[i].status == .downloading else { return }
        release(records[i].attempt, cancel: true)
        artworkTasks[id]?.cancel(); artworkTasks[id] = nil; artworkAttempts[id] = nil
        records[i].status = status; records[i].attempt = nil; records[i].bytes = 0
        records[i].failure = status == .needsSignIn ? .signIn : nil
        persist()
    }
    func remove(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }), let disk else { return }
        cancel(id)
        artworkTasks[id]?.cancel(); artworkTasks[id] = nil; artworkAttempts[id] = nil
        do {
            try disk.remove(record)
            records.removeAll { $0.id == id }
            persist()
        } catch { storageError = OfflineFailure.storage.message }
    }
    func savePosition(_ id: UUID, seconds: Double) {
        guard seconds.isFinite, let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].position = max(0, seconds); persist()
    }
    func thumbnailURL(_ id: UUID) -> URL? { _ = artworkRevision; return disk?.artworkURL(id, kind: .thumbnail) }
    func channelArtworkURL(_ id: UUID) -> URL? { _ = artworkRevision; return disk?.artworkURL(id, kind: .channel) }
    func canRefreshDetails(_ record: OfflineRecord) -> Bool {
        guard let auth = authState.authorization, auth.isActive else { return false }
        return RequestAuthorization.origin(auth.baseURL) == record.origin
    }
    /// Explicit read-only upgrade path for Build 4 copies with no saved display metadata.
    func refreshDetails(_ id: UUID, using repository: VideoRepositoryProtocol) async {
        guard let record = records.first(where: { $0.id == id }), canRefreshDetails(record),
              let auth = authState.authorization, !refreshingDetails.contains(id) else { return }
        refreshingDetails.insert(id); defer { refreshingDetails.remove(id) }
        do {
            let video = try await repository.getVideo(id: record.videoID)
            guard !Task.isCancelled, auth.isActive, auth.id == authState.authorization?.id,
                  video.youtubeId == record.videoID, let i = records.firstIndex(where: { $0.id == id }) else { return }
            records[i].metadata = OfflineVideoMetadata(video: video, origin: record.origin)
            if persist() { queueArtwork(id, replace: true) }
        } catch {
            guard auth.id == authState.authorization?.id else { return }
            storageError = OfflineFailure.network.message
            if let error = error as? AppError, case .unauthorized = error {
                NotificationCenter.default.post(name: .taAuthUnauthorized, object: nil, userInfo: ["authorizationID": auth.id])
            }
        }
    }
    private func queueArtwork(_ id: UUID, replace: Bool = false) {
        if replace { artworkTasks[id]?.cancel(); artworkTasks[id] = nil; artworkAttempts[id] = nil }
        guard artworkTasks[id] == nil, let record = records.first(where: { $0.id == id }),
              let metadata = record.metadata, let auth = authState.authorization, canRefreshDetails(record), let disk else { return }
        let candidates: [(OfflineArtworkKind, String?)] = [(.thumbnail, metadata.thumbnailPath), (.channel, metadata.channelArtworkPath)]
        let attempt = UUID(); artworkAttempts[id] = attempt
        artworkTasks[id] = Task { [weak self] in
            defer {
                // A revoked request can finish synchronously. Release its retained Task
                // on the next main-queue turn, after this task has finished unwinding.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.artworkAttempts[id] == attempt else { return }
                    self.artworkTasks[id] = nil; self.artworkAttempts[id] = nil
                }
            }
            for (kind, path) in candidates {
                guard !Task.isCancelled, auth.isActive, self?.artworkAttempts[id] == attempt, self?.authState.authorization?.id == auth.id,
                      self?.records.contains(where: { $0.id == id }) == true else { return }
                guard let path, let url = URL(string: record.origin + path), replace || disk.artworkURL(id, kind: kind) == nil else { continue }
                do {
                    guard let configuration = self?.artworkConfiguration.copy() as? URLSessionConfiguration else { return }
                    let data = try await OfflineArtworkFetch.data(url: url, authorization: auth, configuration: configuration)
                    guard !Task.isCancelled, auth.isActive, self?.artworkAttempts[id] == attempt, self?.authState.authorization?.id == auth.id,
                          self?.records.contains(where: { $0.id == id }) == true else { return }
                    try disk.saveArtwork(data, id: id, kind: kind)
                    // Trigger presentation refresh only after the private image was committed.
                    self?.artworkRevision += 1
                } catch { /* Optional artwork never invalidates a completed local video. */ }
            }
        }
    }
    private func index(_ description: String?) -> Int? {
        let parts = description?.split(separator: "/") ?? []
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let attempt = UUID(uuidString: String(parts[1])) else { return nil }
        return records.firstIndex { $0.id == id && $0.attempt == attempt && $0.status == .downloading }
    }
    func progress(_ description: String?, bytes: Int64, total: Int64) {
        guard let i = index(description) else { return }
        records[i].bytes = max(0, bytes); records[i].totalBytes = max(0, total)
        if Date().timeIntervalSince(lastProgressSave) >= 1 { lastProgressSave = .now; persist() }
    }
    func finish(_ description: String?, response: HTTPURLResponse?, staged: URL) {
        guard let disk else { return }
        defer { disk.discard(staged) }
        guard let i = index(description) else { return }
        guard let attempt = records[i].attempt, let auth = authorizations[attempt], auth.isActive,
              auth.id == authState.authorization?.id else { fail(description, failure: .signIn); return }
        guard let response, let url = response.url, RequestAuthorization.origin(url) == records[i].origin else {
            fail(description, failure: .server); return
        }
        if RequestAuthorization.isAuthenticationFailure(response) { fail(description, failure: .signIn); return }
        guard response.statusCode == 200 else { fail(description, failure: .server); return }
        do {
            let (kind, size) = try disk.commit(staged, record: records[i], response: response)
            records[i].kind = kind; records[i].bytes = size; records[i].totalBytes = size
            records[i].status = .ready; records[i].attempt = nil; records[i].failure = nil
            release(attempt)
            if !persist() {
                try? disk.remove(records[i]); records[i].status = .failed; records[i].failure = .storage
                records[i].bytes = 0
            }
        } catch { fail(description, failure: (error as? OfflineFailure) ?? .storage) }
    }
    func fail(_ description: String?, failure: OfflineFailure) {
        guard let i = index(description) else { return }
        let auth = records[i].attempt.flatMap { authorizations[$0] }
        release(records[i].attempt, cancel: true)
        records[i].status = failure == .signIn ? .needsSignIn : .failed
        records[i].failure = failure; records[i].attempt = nil; records[i].bytes = 0
        persist()
        if failure == .signIn, let auth, auth.id == authState.authorization?.id {
            NotificationCenter.default.post(name: .taAuthUnauthorized, object: nil, userInfo: ["authorizationID": auth.id])
        }
    }
    private func release(_ attempt: UUID?, cancel: Bool = false) {
        guard let attempt else { return }
        if cancel { tasks[attempt]?.cancel() }
        tasks[attempt] = nil; authorizations[attempt] = nil
    }
    @discardableResult private func persist() -> Bool {
        guard let disk else { storageError = OfflineFailure.storage.message; return false }
        do { try disk.save(records); storageError = nil; return true }
        catch { storageError = OfflineFailure.storage.message; return false }
    }
}
