import Foundation

extension RequestAuthorization {
    /// A rejected resource remains unusable even when the connection is valid.
    /// Only a rejected authenticated ping may invalidate the saved connection.
    nonisolated func rejectsMediaResponse(_ response: HTTPURLResponse, using session: URLSession,
                                         notificationObject: String? = nil) async throws -> Bool {
        guard Self.isAuthenticationFailure(response) else { return false }
        let rejected = try await isAuthenticationFailure(response, using: session)
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
        if rejected {
            NotificationCenter.default.post(name: .taAuthUnauthorized, object: notificationObject,
                userInfo: ["authorizationID": id])
        }
        return true
    }
}
