import Foundation

/// Bounded foreground artwork fetch, using the same request and redirect boundary as media.
enum OfflineArtworkFetch {
    static func data(url: URL, authorization: RequestAuthorization,
                     configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        let request = try OfflineLibrary.request(url: url, authorization: authorization)
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30
        let stream = StreamingSession()
        defer { stream.cancelUpstream() }
        return try await withTaskCancellationHandler {
            let (response, chunks) = try await stream.stream(request: request, configuration: configuration)
            guard response.statusCode == 200, !RequestAuthorization.isAuthenticationFailure(response),
                  response.url.map(RequestAuthorization.origin) == RequestAuthorization.origin(authorization.baseURL),
                  response.expectedContentLength <= 4 * 1024 * 1024 else { throw OfflineFailure.invalidMedia }
            var data = Data()
            for try await chunk in chunks {
                try Task.checkCancellation()
                guard data.count + chunk.count <= 4 * 1024 * 1024 else { throw OfflineFailure.invalidMedia }
                data.append(chunk)
            }
            guard authorization.isActive else { throw OfflineFailure.signIn }
            return data
        } onCancel: { stream.cancelUpstream() }
    }
}
