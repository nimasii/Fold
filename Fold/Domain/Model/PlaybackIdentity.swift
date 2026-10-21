import Foundation

/// Public server identity, never a token/cookie or a hash of credentials. The
/// base path matters: two installations behind one host are separate libraries.
nonisolated struct PlaybackAccount: Codable, Hashable, Sendable {
    let server: String
    let userID: Int

    init?(baseURL: URL, userID: Int) {
        guard userID > 0,
              let normalized = RequestAuthorization.normalizedURL(baseURL.absoluteString),
              let scheme = normalized.scheme?.lowercased(), let host = normalized.host?.lowercased() else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        let port = normalized.port ?? (scheme == "https" ? 443 : 80)
        if port != (scheme == "https" ? 443 : 80) { components.port = port }
        // Preserve encoded path boundaries and case. Only trailing separators
        // are immaterial to the API base URL, as they are for appending paths.
        var path = URLComponents(url: normalized, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        guard let server = components.string else { return nil }
        self.server = server
        self.userID = userID
    }
}

nonisolated struct PlaybackIdentity: Codable, Hashable, Sendable {
    let account: PlaybackAccount
    let videoID: String
}

/// Uses TubeArchivist's duration-dependent completion rule. A completed video
/// starts at zero when played again; explicit seeks/rewinds remain real actions.
nonisolated enum PlaybackCompletion {
    static func isWatched(position: Double, duration: Double) -> Bool {
        guard position.isFinite, duration.isFinite, duration > 0 else { return false }
        let threshold = duration < 60 ? 0.5 : (duration > 900 ? 1 - 180 / duration : 0.9)
        return position >= duration * threshold
    }

    static func resumePosition(position: Double, duration: Double, watched: Bool) -> Double {
        guard position.isFinite, position > 0 else { return 0 }
        // Watched is independent of a resumed rewatch: retain a partial rewatch
        // point even when the library's watched checkbox is still checked.
        if duration.isFinite, duration > 0, position >= duration - min(1, duration * 0.01) { return 0 }
        return duration > 0 ? min(position, duration) : position
    }
}
