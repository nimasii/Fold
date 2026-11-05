#if targetEnvironment(macCatalyst)
import Foundation
import CLibVLC

/// File-only metadata inspection. Read the libVLC track fields directly because
/// SwiftVLC's public Track omits the profile and rotation conversion safety checks.
enum MacOfflineMediaInspector {
    static func inspect(_ url: URL) async throws -> OfflineMediaPreparer.Source {
        guard url.isFileURL, let instance = libvlc_new(0, nil) else { throw OfflineFailure.invalidMedia }
        defer { libvlc_release(instance) }
        guard let media = libvlc_media_new_path(url.path) else { throw OfflineFailure.invalidMedia }
        defer { libvlc_media_parse_stop(instance, media); libvlc_media_release(media) }
        guard libvlc_media_parse_request(instance, media, libvlc_media_parse_local, 5_000) == 0 else { throw OfflineFailure.invalidMedia }
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        while true {
            try Task.checkCancellation()
            let status = libvlc_media_get_parsed_status(media)
            if status == libvlc_media_parsed_status_done { break }
            guard (status == libvlc_media_parsed_status_none || status == libvlc_media_parsed_status_pending),
                  ContinuousClock.now < deadline else { throw OfflineFailure.invalidMedia }
            try await Task.sleep(for: .milliseconds(50))
        }
        let duration = Double(libvlc_media_get_duration(media)) / 1000
        var streams: [OfflineVideoMetadata.Stream] = []
        var unsafe = false
        for type in [libvlc_track_video, libvlc_track_audio] {
            guard let list = libvlc_media_get_tracklist(media, type) else { continue }
            defer { libvlc_media_tracklist_delete(list) }
            for index in 0..<libvlc_media_tracklist_count(list) {
                guard let pointer = libvlc_media_tracklist_at(list, index) else { continue }
                let track = pointer.pointee
                let code = track.i_codec
                let codec = (String(bytes: [UInt8(code & 255), UInt8((code >> 8) & 255), UInt8((code >> 16) & 255), UInt8((code >> 24) & 255)], encoding: .ascii) ?? "unknown").lowercased()
                let video = type == libvlc_track_video
                if video {
                    guard let info = track.video else { throw OfflineFailure.invalidMedia }
                    unsafe = unsafe || info.pointee.i_orientation.rawValue != 0
                        || (codec.contains("vp9") && track.i_profile >= 2) || codec.contains("av01")
                }
                streams.append(.init(type: video ? "video" : "audio",
                    codec: ["mp4a", "aac "].contains(codec) ? "aac" : codec, bitrate: Int(track.i_bitrate),
                    width: video ? track.video.map { Int($0.pointee.i_width) } : nil,
                    height: video ? track.video.map { Int($0.pointee.i_height) } : nil))
            }
        }
        guard duration.isFinite, duration > 0, streams.contains(where: { $0.type == "video" }) else { throw OfflineFailure.invalidMedia }
        return .init(duration: duration, streams: streams, nativeCompatible: false, unsafeColorOrRotation: unsafe)
    }
}
#endif
