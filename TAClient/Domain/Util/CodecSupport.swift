import Foundation

enum PlayerType {
    case avPlayer
    case vlcPlayer
}

enum CodecSupport {
    private static let unsupportedVideoCodecs: Set<String> = [
        "vp9", "vp09", "vp8", "vp08"
    ]

    private static let unsupportedAudioCodecs: Set<String> = []

    static func requiredPlayer(for streams: [StreamInfo], fileExtension: String? = nil) -> PlayerType {
        // Older downloads may lack stream metadata. Use the same conservative
        // WebM fallback for a remote URL and a private local file.
        if streams.isEmpty && fileExtension?.lowercased() == "webm" { return .vlcPlayer }
        for stream in streams {
            let codec = stream.codec.lowercased()
            if stream.type.lowercased() == "video" && unsupportedVideoCodecs.contains(codec) {
                return .vlcPlayer
            }
            if stream.type.lowercased() == "audio" && unsupportedAudioCodecs.contains(codec) {
                return .vlcPlayer
            }
        }
        return .avPlayer
    }
}
