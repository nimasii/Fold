import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import AudioToolbox
#if !UI_REVIEW_PREVIEW
import MobileVLCKit
#endif

nonisolated struct OfflinePreparedMedia: Sendable {
    let url: URL
    let streams: [OfflineVideoMetadata.Stream]
    let converted: Bool
}

/// File-only preparation. No URL, cookie, token or server capability enters VLC.
/// One library owns one preparer, so expensive encodes are serialized.
final class OfflineMediaPreparer {
    private var busy = false

    nonisolated struct Source: Sendable {
        var duration: Double
        var streams: [OfflineVideoMetadata.Stream]
        var nativeCompatible: Bool
        var unsafeColorOrRotation: Bool = false
        var audioDuration: Double?
    }

    /// A source-relative budget avoids converting a small AV1/VP9 file at a fixed
    /// 5 Mbps. AVC may need more bits; allow up to 1.6x source video, capped at 5 Mbps.
    nonisolated static func videoBitrate(sourceVideo: Int, fileBytes: Int64, duration: Double, audio: Int) -> Int {
        let aggregate = duration > 0 ? Double(fileBytes) * 8 / duration : 0
        let estimate = sourceVideo > 0 ? Double(sourceVideo) : max(0, aggregate - Double(max(0, audio)))
        return Int(min(5_000_000, max(256_000, estimate * 1.6)))
    }
    nonisolated static func durationMatches(_ actual: Double, expected: Double, serverMetadata: Bool = false) -> Bool {
        guard actual.isFinite, expected.isFinite, actual > 0, expected > 0 else { return false }
        let tolerance = serverMetadata ? max(1.5, min(3, expected * 0.002)) : max(0.15, min(1.5, expected * 0.002))
        return abs(actual - expected) <= tolerance
    }

    func prepare(input: URL, output: URL, expectedDuration: Int,
                 checkSpace: (Int64) throws -> Void,
                 progress: (Double?) -> Void) async throws -> OfflinePreparedMedia {
        guard input.isFileURL, output.isFileURL, input != output else { throw OfflineFailure.invalidMedia }
        while busy { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(100)) }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        progress(nil)
        var source = try await inspect(input)
        if expectedDuration > 0, !Self.durationMatches(source.duration, expected: Double(expectedDuration), serverMetadata: true) {
            throw OfflineFailure.invalidMedia
        }
        if source.nativeCompatible && Self.hasMP4Header(input) {
            do {
                try await Self.validate(input, source: source)
                try Task.checkCancellation()
                return OfflinePreparedMedia(url: input, streams: source.streams, converted: false)
            } catch is CancellationError { throw CancellationError() }
            catch { source.nativeCompatible = false } // A playable flag alone is not proof that every track decodes.
        }
        guard !source.unsafeColorOrRotation else { throw OfflineFailure.unsupportedConversion }
        let bytes = Int64(try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let sourceVideo = source.streams.first { $0.type == "video" }?.bitrate ?? 0
        let sourceAudio = source.streams.first { $0.type == "audio" }?.bitrate ?? 0
        let bitrate = Self.videoBitrate(sourceVideo: sourceVideo, fileBytes: bytes, duration: source.duration, audio: sourceAudio)
        // Source is already on disk. Reserve output plus mux overhead; check again
        // during encoding so a parallel download cannot consume this margin.
        let estimate = ceil(source.duration * Double(bitrate + 128_000) / 8 * 1.15)
        guard estimate.isFinite, estimate > 0, estimate < Double(Int64.max / 2) else { throw OfflineFailure.invalidMedia }
        let budget = Int64(estimate) + 8_000_000
        try checkSpace(budget)
        #if !UI_REVIEW_PREVIEW
        try await convert(input: input, output: output, source: source, bitrate: bitrate, budget: budget,
                          checkSpace: checkSpace, progress: progress)
        #else
        throw OfflineFailure.unsupportedConversion
        #endif
        // stop() is asynchronous. A momentarily stable file size is not proof
        // that the muxer finished its index; retry full validation, never accept
        // a partially closed file or relax completeness/duration requirements.
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while true {
            try Task.checkCancellation()
            do {
                let result = try await inspectNative(output)
                let size = Int64(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                guard size <= budget, result.nativeCompatible,
                      result.streams.allSatisfy({ $0.type == "video" ? $0.codec == "h264" : $0.codec == "aac" }),
                      Self.durationMatches(result.duration, expected: source.duration),
                      result.streams.filter({ $0.type == "audio" }).isEmpty == source.streams.filter({ $0.type == "audio" }).isEmpty else {
                    throw OfflineFailure.invalidMedia
                }
                try await Self.validate(output, source: Source(duration: source.duration, streams: result.streams,
                                                              nativeCompatible: true, audioDuration: source.audioDuration))
                try Task.checkCancellation()
                progress(1)
                return OfflinePreparedMedia(url: output, streams: result.streams, converted: true)
            } catch is CancellationError { throw CancellationError() }
            catch {
                guard ContinuousClock.now < deadline else { throw error }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func inspect(_ url: URL) async throws -> Source {
        do { return try await inspectNative(url) }
        catch is CancellationError { throw CancellationError() }
        catch {
            #if !UI_REVIEW_PREVIEW
            let media = VLCMedia(url: url)
            defer { media.parseStop() }
            guard media.parse(options: VLCMediaParsingOptions(rawValue: 0), timeout: 5_000) == 0 else { throw OfflineFailure.invalidMedia }
            let deadline = ContinuousClock.now.advanced(by: .seconds(6))
            while media.parsedStatus.rawValue == 0 && ContinuousClock.now < deadline {
                try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(50))
            }
            guard media.parsedStatus.rawValue == 4 else { throw OfflineFailure.invalidMedia }
            let duration = Double(media.length.intValue) / 1000
            let tracks = media.tracksInformation as? [[String: Any]] ?? []
            var unsafe = false
            let streams = tracks.compactMap { track -> OfflineVideoMetadata.Stream? in
                let type = track[VLCMediaTracksInformationType] as? String
                guard type == VLCMediaTracksInformationTypeVideo || type == VLCMediaTracksInformationTypeAudio else { return nil }
                let video = type == VLCMediaTracksInformationTypeVideo
                let code = (track[VLCMediaTracksInformationCodec] as? NSNumber)?.uint32Value ?? 0
                // libVLC fourcc is little-endian; only display metadata uses this.
                let codec = String(bytes: [UInt8(code & 255), UInt8((code >> 8) & 255), UInt8((code >> 16) & 255), UInt8((code >> 24) & 255)], encoding: .ascii) ?? "unknown"
                if video {
                    let profile = (track[VLCMediaTracksInformationCodecProfile] as? NSNumber)?.intValue ?? 0
                    let orientation = (track[VLCMediaTracksInformationVideoOrientation] as? NSNumber)?.intValue ?? 0
                    // Known high-bit-depth VP9 and rotated sources require a
                    // separately verified color/rotation conversion path.
                    unsafe = unsafe || orientation != 0 || (codec.lowercased().contains("vp9") && profile >= 2) || codec.lowercased().contains("av01")
                }
                return .init(type: video ? "video" : "audio", codec: ["mp4a", "aac "].contains(codec.lowercased()) ? "aac" : codec.lowercased(),
                    bitrate: (track[VLCMediaTracksInformationBitrate] as? NSNumber)?.intValue ?? 0,
                    width: video ? (track[VLCMediaTracksInformationVideoWidth] as? NSNumber)?.intValue : nil,
                    height: video ? (track[VLCMediaTracksInformationVideoHeight] as? NSNumber)?.intValue : nil)
            }
            guard duration.isFinite, duration > 0, streams.contains(where: { $0.type == "video" }) else { throw OfflineFailure.invalidMedia }
            return Source(duration: duration, streams: streams, nativeCompatible: false, unsafeColorOrRotation: unsafe)
            #else
            throw OfflineFailure.invalidMedia
            #endif
        }
    }

    private func inspectNative(_ url: URL) async throws -> Source {
        let asset = Self.privateAsset(url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw OfflineFailure.invalidMedia }
        let playable = try await asset.load(.isPlayable)
        var streams: [OfflineVideoMetadata.Stream] = []
        let compatible = playable
        var unsafe = false
        var audioDuration: Double?
        for track in try await asset.load(.tracks) {
            let type = track.mediaType
            guard type == .video || type == .audio else { continue }
            let formats = try await track.load(.formatDescriptions)
            guard let format = formats.first else { throw OfflineFailure.invalidMedia }
            let subtype = CMFormatDescriptionGetMediaSubType(format)
            let codec: String
            if type == .video {
                codec = subtype == kCMVideoCodecType_H264 ? "h264" : Self.fourCC(subtype)
                // Runtime validation decides native compatibility, not a codec-name blacklist.
                let transform = try await track.load(.preferredTransform)
                let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
                let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String ?? ""
                let depth = (extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? NSNumber)?.intValue ?? 8
                let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String ?? ""
                // Some unsupported HEVC files expose depth/matrix but omit the
                // transfer function. Do not silently flatten these into SDR.
                unsafe = unsafe || transform != .identity || depth > 8 || matrix == (kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String)
                    || transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
                    || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
            } else {
                codec = subtype == kAudioFormatMPEG4AAC ? "aac" : Self.fourCC(subtype)
                // PCM decoding below verifies the actual audio support on this device.
                audioDuration = try await track.load(.timeRange).duration.seconds
            }
            let size = type == .video ? try await track.load(.naturalSize) : .zero
            let rate = try await track.load(.estimatedDataRate)
            guard size.width.isFinite, size.height.isFinite,
                  abs(size.width) < Double(Int.max / 2), abs(size.height) < Double(Int.max / 2) else { throw OfflineFailure.invalidMedia }
            let bitrate = rate.isFinite && rate > 0 && Double(rate) < Double(Int.max / 2) ? Int(rate) : 0
            streams.append(.init(type: type == .video ? "video" : "audio", codec: codec,
                bitrate: bitrate,
                width: type == .video ? Int(abs(size.width)) : nil, height: type == .video ? Int(abs(size.height)) : nil))
        }
        guard streams.contains(where: { $0.type == "video" }) else { throw OfflineFailure.invalidMedia }
        return Source(duration: duration, streams: streams, nativeCompatible: compatible,
                      unsafeColorOrRotation: unsafe, audioDuration: audioDuration)
    }

    #if !UI_REVIEW_PREVIEW
    private func convert(input: URL, output: URL, source: Source, bitrate: Int, budget: Int64,
                         checkSpace: (Int64) throws -> Void, progress: (Double?) -> Void) async throws {
        // Output is a protected, precreated UUID path, never an untrusted title.
        guard !output.path.contains("'"), !output.path.contains("}") else { throw OfflineFailure.storage }
        let duration = source.duration
        let media = VLCMedia(url: input)
        let audioNeedsEncoding = source.streams.contains { $0.type == "audio" && $0.codec != "aac" }
        var options: [String] = []
        options += ["vcodec=h264", "venc=avcodec{codec=h264_videotoolbox,bframes=0,options={realtime=1}}", "vb=\(bitrate / 1000)", "maxwidth=1920", "maxheight=1080"]
        if audioNeedsEncoding { options += ["acodec=mp4a", "ab=128", "channels=2", "samplerate=48000"] }
        let conversion = "transcode{\(options.joined(separator: ","))}:"
        media.addOption(":sout=#\(conversion)standard{access=file,mux=mp4{faststart=0},dst='\(output.path)'}")
        media.addOption(":no-sout-all")
        media.addOption(":no-drop-late-frames")
        media.addOption(":no-skip-frames")
        media.addOption(":sout-mux-caching=0")
        media.addOption(":file-caching=0")
        media.addOption(":avcodec-threads=1")
        let player = VLCMediaPlayer(options: ["--sout-mux-caching=0", "--avcodec-threads=1", "--dav1d-thread-frames=1", "--dav1d-thread-tiles=1", "--no-drop-late-frames", "--no-skip-frames", "--file-caching=0"])
        player.media = media
        defer { player.stop(); player.media = nil }
        player.play()
        let start = ContinuousClock.now
        var lastActivity = start, lastSize: Int64 = 0, lastTime: Int32 = 0
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(200))
            let size = Int64((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let time = player.time.intValue
            if size > lastSize || time > lastTime { lastActivity = .now; lastSize = max(lastSize, size); lastTime = max(lastTime, time) }
            let fraction = min(0.99, max(0, Double(lastTime) / 1000 / duration))
            progress(fraction)
            guard size <= budget else { throw OfflineFailure.conversion }
            try checkSpace(max(0, budget - size))
            guard player.state != .error else { throw OfflineFailure.conversion }
            if (player.state == .ended || player.state == .stopped) && !player.isPlaying && size > 16,
               ContinuousClock.now - start > .seconds(1.5),
               ContinuousClock.now - lastActivity > .seconds(1.0) { break }
            if ContinuousClock.now - lastActivity > .seconds(90) || ContinuousClock.now - start > .seconds(max(300, duration * 10)) {
                throw OfflineFailure.conversion
            }
        }
        // VLCKit's stop dispatches teardown; wait for the MP4 muxer to close and
        // write its final index before asking AVFoundation to inspect the file.
        player.stop()
        let closing = ContinuousClock.now
        var changed = closing
        var closingSize: Int64 = -1
        while ContinuousClock.now - closing < .seconds(15) {
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            let size = Int64((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if size != closingSize { closingSize = size; changed = .now }
            if ContinuousClock.now - closing > .seconds(0.5), ContinuousClock.now - changed > .seconds(0.4) { break }
        }
    }
    #endif

    /// Read complete streams off the main actor, including decoded audio and
    /// final timestamps. Header/duration alone can describe a truncated file.
    @concurrent nonisolated static func validate(_ url: URL, source: Source) async throws {
        let asset = Self.privateAsset(url)
        let tracks = try await asset.load(.tracks).filter { $0.mediaType == .video || $0.mediaType == .audio }
        let reader = try AVAssetReader(asset: asset)
        var outputs: [(AVAssetReaderTrackOutput, Bool)] = []
        for track in tracks {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: track.mediaType == .audio ? [AVFormatIDKey: kAudioFormatLinearPCM] : nil)
            guard reader.canAdd(output) else { throw OfflineFailure.invalidMedia }
            reader.add(output); outputs.append((output, track.mediaType == .video))
        }
        guard reader.startReading() else { throw OfflineFailure.invalidMedia }
        defer { reader.cancelReading() }
        for (output, video) in outputs {
            var count = 0, end: Double = 0
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                count += 1
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let length = CMSampleBufferGetDuration(sample).seconds
                if time.isFinite { end = max(end, time + (length.isFinite ? max(0, length) : 0)) }
            }
            let expected = video ? source.duration : (source.audioDuration ?? source.duration)
            guard count > 0, end >= expected - max(0.25, min(1.5, expected * 0.002)) else { throw OfflineFailure.invalidMedia }
        }
        guard reader.status == .completed else { throw OfflineFailure.invalidMedia }
        // Decode actual head/tail frames, not just MP4 atoms or codec labels.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 96, height: 96)
        generator.appliesPreferredTrackTransform = true
        for time in [min(0.1, source.duration / 2), max(0, source.duration - 0.15)] {
            try Task.checkCancellation()
            _ = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        }
    }
    nonisolated private static func privateAsset(_ url: URL) -> AVURLAsset {
        var options: [String: Any] = [AVURLAssetReferenceRestrictionsKey: NSNumber(value: AVAssetReferenceRestrictions.forbidAll.rawValue)]
        // URLSession staging uses .part. Infer the type from verified bytes,
        // otherwise AVFoundation can reject a compatible MP4 just by extension.
        if hasMP4Header(url) { options[AVURLAssetOverrideMIMETypeKey] = "video/mp4" }
        return AVURLAsset(url: url, options: options)
    }
    nonisolated private static func hasMP4Header(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8), data.count == 8 else { return false }
        return Array(data[4..<8]) == Array("ftyp".utf8)
    }
    nonisolated private static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)], encoding: .ascii) ?? "unknown"
    }
}
