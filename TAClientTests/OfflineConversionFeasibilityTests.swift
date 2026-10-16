import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import AudioToolbox
import MobileVLCKit
import Testing
@testable import TAClient

private final class ConversionFixtureBundle: NSObject {}

/// Synthetic local-only experiments. These are not wired to production downloads.
@MainActor @Suite(.serialized)
struct OfflineConversionFeasibilityTests {
    private let samples = [
        ("conversion-h264-aac", "mp4"),
        ("conversion-vp9-opus", "webm"),
        ("conversion-vp9-opus", "mp4"),
        ("conversion-av1-opus", "mp4")
    ]

    @Test func nativeExportCapabilities() async throws {
        var results: [[String: String]] = []
        for (name, ext) in samples {
            let input = try #require(Bundle(for: ConversionFixtureBundle.self).url(forResource: name, withExtension: ext))
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            let asset = AVURLAsset(url: input)
            var row = ["input": name + "." + ext]
            do {
                row["nativePlayable"] = String(try await asset.load(.isPlayable))
                let compatible = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPreset1280x720, with: asset, outputFileType: .mp4)
                row["exportCompatible"] = String(compatible)
                if compatible, let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) {
                    if #available(iOS 18, *) {
                        try await exporter.export(to: output, as: .mp4)
                        row["outputCodecs"] = try await codecs(output)
                    }
                }
            } catch { row["errorCode"] = String((error as NSError).code) }
            if name == "conversion-h264-aac" {
                #expect(row["outputCodecs"]?.contains("avc1") == true)
                #expect(row["outputCodecs"]?.contains("aac ") == true)
            }
            results.append(row)
        }
        print("[NativeConversionProbe] " + String(data: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), encoding: .utf8)!)
    }

    @Test func bundledVLCConversionCapabilities() async throws {
        var results: [[String: String]] = []
        for (name, ext) in samples {
            let input = try #require(Bundle(for: ConversionFixtureBundle.self).url(forResource: name, withExtension: ext))
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            let original = try Data(contentsOf: input)
            let media = VLCMedia(url: input)
            // Explicit H.264/AAC output; never rename/copy a file and call it conversion.
            media.addOption(":sout=#transcode{vcodec=h264,venc=vtenc_h264,vb=5000,fps=30,maxwidth=1920,maxheight=1080,acodec=mp4a,ab=128,channels=2,samplerate=48000}:standard{access=file,mux=mp4,dst='\(output.path)'}")
            media.addOption(":no-sout-all")
            let player = VLCMediaPlayer()
            player.media = media
            player.play()
            let deadline = ContinuousClock.now.advanced(by: .seconds(12))
            try await Task.sleep(for: .milliseconds(300))
            while player.state != .ended && player.state != .error && ContinuousClock.now < deadline {
                if player.state == .stopped, (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 16 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            var row = ["input": name + "." + ext, "state": String(describing: player.state)]
            player.stop()
            player.media = nil
            let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            row["outputBytes"] = String(size)
            if size > 0 {
                do {
                    row["outputCodecs"] = try await codecs(output)
                    let asset = AVURLAsset(url: output)
                    row["outputDuration"] = String(try await asset.load(.duration).seconds)
                    row["decodedAudioBuffers"] = String(try await decodedAudioBuffers(asset))
                    let generator = AVAssetImageGenerator(asset: asset)
                    _ = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
                    row["decodedVideoFrame"] = "true"
                    row["nativePlaybackAndSeek"] = String(await playsAndSeeks(output))
                }
                catch { row["errorCode"] = String((error as NSError).code) }
            }
            #expect(try Data(contentsOf: input) == original)
            #expect(row["outputCodecs"]?.contains("avc1") == true)
            #expect(row["outputCodecs"]?.contains("aac ") == true)
            #expect(Double(row["outputDuration"] ?? "0") ?? 0 >= 0.9)
            #expect(Int(row["decodedAudioBuffers"] ?? "0") ?? 0 > 0)
            #expect(row["decodedVideoFrame"] == "true")
            #expect(row["nativePlaybackAndSeek"] == "true")
            results.append(row)
        }
        print("[VLCConversionProbe] " + String(data: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), encoding: .utf8)!)
    }

    private func playsAndSeeks(_ url: URL) async -> Bool {
        let player = AVPlayer(url: url)
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        player.play()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while player.currentTime().seconds < 0.15 && player.currentItem?.status != .failed && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard player.currentTime().seconds >= 0.15 else { return false }
        player.pause()
        let sought = await player.seek(to: CMTime(seconds: 0.5, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        return sought && player.currentTime().seconds >= 0.49
    }

    private func decodedAudioBuffers(_ asset: AVAsset) async throws -> Int {
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? OfflineFailure.invalidMedia }
        var count = 0
        while output.copyNextSampleBuffer() != nil { count += 1 }
        #expect(reader.status == .completed)
        return count
    }

    private func codecs(_ url: URL) async throws -> String {
        let tracks = try await AVURLAsset(url: url).load(.tracks)
        var values: [String] = []
        for track in tracks {
            for format in try await track.load(.formatDescriptions) {
                let value = CMFormatDescriptionGetMediaSubType(format)
                let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
                values.append(String(bytes: bytes, encoding: .ascii) ?? "unknown")
            }
        }
        return values.sorted().joined(separator: ",")
    }
}
