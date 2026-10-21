import UIKit

actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var failedURLs: [String: Date] = [:]
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<UIImage?, Never>]
    }
    private var inFlightTasks: [String: Flight] = [:]
    private let session: URLSession

    private static let failureCooldown: TimeInterval = 60

    init(configuration: URLSessionConfiguration = .default) {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
        let config = configuration
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }

    func clear() {
        let pending = inFlightTasks
        inFlightTasks.removeAll()
        for flight in pending.values {
            flight.task.cancel()
            for waiter in flight.waiters.values { waiter.resume(returning: nil) }
        }
        failedURLs.removeAll()
        cache.removeAllObjects()
    }

    func image(for url: URL, token: String?, authorization: RequestAuthorization? = nil) async -> UIImage? {
        guard !Task.isCancelled, authorization?.isActive != false else { return nil }
        let key = url.absoluteString + (authorization?.id.uuidString ?? "")
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let failedAt = failedURLs[key], Date().timeIntervalSince(failedAt) < Self.failureCooldown { return nil }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, authorization?.isActive != false else {
                    continuation.resume(returning: nil); return
                }
                if var existing = inFlightTasks[key] {
                    existing.waiters[waiterID] = continuation
                    inFlightTasks[key] = existing
                    return
                }
                let id = UUID()
                let task = Task {
                    let image = await fetch(url: url, token: token, authorization: authorization)
                    finish(key: key, id: id, image: image, authorization: authorization)
                }
                inFlightTasks[key] = Flight(id: id, task: task, waiters: [waiterID: continuation])
            }
        } onCancel: {
            Task { await self.cancel(key: key, waiterID: waiterID) }
        }
    }

    private func cancel(key: String, waiterID: UUID) {
        guard var flight = inFlightTasks[key], let waiter = flight.waiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(returning: nil)
        if flight.waiters.isEmpty { inFlightTasks[key] = nil; flight.task.cancel() }
        else { inFlightTasks[key] = flight }
    }

    private func finish(key: String, id: UUID, image: UIImage?, authorization: RequestAuthorization?) {
        guard let flight = inFlightTasks[key], flight.id == id else { return }
        inFlightTasks[key] = nil
        let current = !Task.isCancelled && authorization?.isActive != false
        if current, let image { cache.setObject(image, forKey: key as NSString, cost: ArtworkDecoder.cost(of: image)) }
        else if current { failedURLs[key] = Date() }
        for waiter in flight.waiters.values { waiter.resume(returning: current ? image : nil) }
    }

    private func fetch(url: URL, token: String?, authorization: RequestAuthorization?) async -> UIImage? {
        var request = URLRequest(url: url)
        if let authorization {
            do { try authorization.apply(to: &request) } catch { return nil }
        } else if let token { request.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              !Task.isCancelled, authorization?.isActive != false else { return nil }
        let authenticationFailed: Bool
        if let authorization {
            do { authenticationFailed = try await authorization.isAuthenticationFailure(httpResponse, using: session) }
            catch { return nil }
        } else { authenticationFailed = RequestAuthorization.isAuthenticationFailure(httpResponse) }
        guard !Task.isCancelled, authorization?.isActive != false else { return nil }
        if authenticationFailed {
            NotificationCenter.default.post(name: .taAuthUnauthorized, object: nil,
                userInfo: authorization.map { ["authorizationID": $0.id] })
            return nil
        }
        guard (200...299).contains(httpResponse.statusCode) else { return nil }
        return ArtworkDecoder.image(from: data)
    }
}
