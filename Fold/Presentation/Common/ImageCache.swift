import UIKit

actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var failedURLs: [String: Date] = [:]
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private static let failureCooldown: TimeInterval = 60

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }

    func clear() {
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        failedURLs.removeAll()
        cache.removeAllObjects()
    }

    func image(for url: URL, token: String?, authorization: RequestAuthorization? = nil) async -> UIImage? {
        guard authorization?.isActive != false else { return nil }
        let taskKey = url.absoluteString + (authorization?.id.uuidString ?? "")
        let key = taskKey as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let failedAt = failedURLs[taskKey], Date().timeIntervalSince(failedAt) < Self.failureCooldown {
            return nil
        }

        if let existing = inFlightTasks[taskKey] {
            return await existing.value
        }

        let session = self.session
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            if let authorization {
                do { try authorization.apply(to: &request) } catch { return nil }
            } else if let token { request.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }

            guard let (data, response) = try? await session.data(for: request),
                  let httpResponse = response as? HTTPURLResponse else { return nil }
            if RequestAuthorization.isAuthenticationFailure(httpResponse) {
                NotificationCenter.default.post(name: .taAuthUnauthorized, object: nil, userInfo: authorization.map { ["authorizationID": $0.id] })
                return nil
            }
            guard
                  (200...299).contains(httpResponse.statusCode),
                  let image = ArtworkDecoder.image(from: data) else {
                return nil
            }

            guard authorization?.isActive != false else { return nil }
            cache.setObject(image, forKey: key, cost: ArtworkDecoder.cost(of: image))
            return image
        }

        inFlightTasks[taskKey] = task
        let result = await task.value
        inFlightTasks[taskKey] = nil

        if result == nil {
            failedURLs[taskKey] = Date()
        }

        return result
    }
}
