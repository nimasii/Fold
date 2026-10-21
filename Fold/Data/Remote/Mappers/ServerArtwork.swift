import Foundation

/// Tube Archivist has used both cache paths and authenticated media routes.
/// Never send the server's authorization to a public YouTube thumbnail host.
nonisolated enum ServerArtwork {
    static func resolve(_ raw: String?, baseURL: String) -> String? {
        guard let raw, !raw.isEmpty, let base = URL(string: baseURL) else { return nil }
        let origin = RequestAuthorization.origin(base)
        let path: String
        if let url = URL(string: raw), url.scheme != nil {
            guard RequestAuthorization.origin(url) == origin, url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { return nil }
            path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        } else if raw.hasPrefix("videos/") || raw.hasPrefix("channels/") || raw.hasPrefix("playlists/") {
            path = "/cache/" + raw
        } else { path = raw.hasPrefix("/") ? raw : "/" + raw }
        guard OfflineVideoMetadata.artworkURL(path: path, origin: origin) != nil else { return nil }
        return URL(string: RequestAuthorization.csrfOrigin(base) + path)?.absoluteString
    }

    static func videoFallbacks(_ id: String, baseURL: String) -> [String] {
        guard validID(id, count: 11), let first = id.first else { return [] }
        return ["/media/thumb/video/\(id).jpg", "/cache/videos/\(String(first).lowercased())/\(id).jpg"]
            .compactMap { resolve($0, baseURL: baseURL) }
    }

    static func channelFallbacks(_ id: String, baseURL: String) -> [String] {
        guard id.hasPrefix("UC"), validID(id, count: 24) else { return [] }
        return ["/media/thumb/channel/\(id)/thumb.jpg", "/cache/channels/\(id)_thumb.jpg"]
            .compactMap { resolve($0, baseURL: baseURL) }
    }

    private static func validID(_ id: String, count: Int) -> Bool {
        id.utf8.count == count && id.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
