import Foundation
import AVFoundation
import CoreMedia
import Testing
@testable import Fold

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

    // The initial standalone VLC probe is superseded by OfflineMediaPreparationTests,
    // which exercises the shipping encoder, teardown, completeness validation and
    // real native playback/seek with short, long, silent and color fixtures.

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
