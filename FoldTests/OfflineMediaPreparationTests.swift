import Foundation
import AVFoundation
import Testing
import CoreMedia
@testable import Fold

private final class PreparationFixtures: NSObject {}

@MainActor @Suite(.serialized)
struct OfflineMediaPreparationTests {
    func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle(for: PreparationFixtures.self).url(forResource: name, withExtension: ext))
    }
    @Test func compatibleCopyIsByteIdenticalAndInspectedWithoutTrustingMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = try OfflineDiskStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try fixture("conversion-h264-aac", "mp4")
        let copy = root.appendingPathComponent("source.part")
        try FileManager.default.copyItem(at: original, to: copy)
        let output = try disk.preparationOutput()
        let result = try await OfflineMediaPreparer().prepare(input: copy, output: output, expectedDuration: 1,
            checkSpace: { try disk.checkCapacity($0) }, progress: { _ in })
        #expect(!result.converted && result.url == copy)
        #expect(try Data(contentsOf: copy) == Data(contentsOf: original))
        #expect(result.streams.contains { $0.codec == "h264" })
        #expect(result.streams.contains { $0.codec == "aac" })
    }
    @Test(arguments: [("conversion-vp9-opus", "webm"), ("conversion-vp9-opus", "mp4"), ("conversion-av1-opus", "mp4")])
    func incompatibleCopyBecomesValidatedNativeMedia(_ sample: (String, String)) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = try OfflineDiskStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = try fixture(sample.0, sample.1)
        let bytes = try Data(contentsOf: input)
        let output = try disk.preparationOutput()
        let result: OfflinePreparedMedia
        do {
            result = try await OfflineMediaPreparer().prepare(input: input, output: output, expectedDuration: 1,
                checkSpace: { try disk.checkCapacity($0) }, progress: { _ in })
        } catch {
            let diagnostic = FileManager.default.temporaryDirectory.appendingPathComponent("PreparationFailure-" + UUID().uuidString + ".mp4")
            try? FileManager.default.copyItem(at: output, to: diagnostic)
            print("[SyntheticPreparationFailure] \(sample) \(diagnostic.path)")
            throw error
        }
        #expect(try Data(contentsOf: input) == bytes)
        if result.converted {
            #expect(result.url == output)
            #expect(result.streams.filter { $0.type == "video" }.allSatisfy { $0.codec == "h264" })
            #expect(result.streams.filter { $0.type == "audio" }.allSatisfy { $0.codec == "aac" })
        } else { #expect(result.url == input) }
        #expect(try await AVURLAsset(url: result.url).load(.isPlayable))
    }
    @Test(arguments: [("conversion-long-vp9", "webm", 30), ("conversion-two-minute-vp9", "webm", 120), ("conversion-h264-opus", "mp4", 8), ("conversion-vertical-silent", "webm", 8)])
    func longerMediaAndAudioOnlyConversion(_ sample: (String, String, Int)) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = try OfflineDiskStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = try fixture(sample.0, sample.1)
        let original = try Data(contentsOf: input)
        let output = try disk.preparationOutput()
        let clock = ContinuousClock.now
        let result = try await OfflineMediaPreparer().prepare(input: input, output: output, expectedDuration: sample.2,
            checkSpace: { try disk.checkCapacity($0) }, progress: { _ in })
        #expect(result.converted || result.url == input)
        #expect(try Data(contentsOf: input) == original)
        let duration = try await AVURLAsset(url: result.url).load(.duration).seconds
        #expect(OfflineMediaPreparer.durationMatches(duration, expected: Double(sample.2)))
        if sample.0 == "conversion-h264-opus" && result.converted {
            #expect(result.streams.contains { $0.codec == "aac" })
        }
        if sample.0 == "conversion-vertical-silent" {
            #expect(!result.streams.contains { $0.type == "audio" })
            let video = try #require(result.streams.first { $0.type == "video" })
            #expect(video.width == 180 && video.height == 320)
        }
        let player = AVPlayer(url: result.url)
        player.play()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while player.currentTime().seconds < 0.1 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(player.currentTime().seconds >= 0.1)
        player.pause()
        let target = duration / 2
        let sought = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        #expect(sought && abs(player.currentTime().seconds - target) < 0.15)
        player.replaceCurrentItem(with: nil)
        let size = try result.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        print("[PreparedMedia] \(sample.0) source=\(original.count) output=\(size) duration=\(duration) elapsed=\(ContinuousClock.now - clock)")
    }
    @Test func spaceFailureAndDurationMismatchNeverReturnReadyMedia() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = try OfflineDiskStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = try fixture("conversion-vp9-opus", "webm")
        let output = try disk.preparationOutput()
        await #expect(throws: OfflineFailure.self) {
            try await OfflineMediaPreparer().prepare(input: input, output: output, expectedDuration: 1,
                checkSpace: { _ in throw OfflineFailure.storage }, progress: { _ in })
        }
        await #expect(throws: OfflineFailure.self) {
            try await OfflineMediaPreparer().prepare(input: input, output: output, expectedDuration: 30,
                checkSpace: { _ in }, progress: { _ in })
        }
    }
    @Test(arguments: ["conversion-hdr-hevc", "conversion-high-bit-depth-hevc"])
    func knownHDRIsNeverConvertedWithoutColorValidation(_ name: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = try OfflineDiskStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = try fixture(name, "mp4")
        let bytes = try Data(contentsOf: input)
        let output = try disk.preparationOutput()
        do {
            let result = try await OfflineMediaPreparer().prepare(input: input, output: output, expectedDuration: 1,
                checkSpace: { _ in }, progress: { _ in })
            #expect(!result.converted && result.url == input)
        } catch { #expect((error as? OfflineFailure) == .unsupportedConversion) }
        #expect(try Data(contentsOf: input) == bytes)
    }
    @Test func bitrateBudgetTracksLowBitrateSourcesAndCapsHighOnes() {
        #expect(OfflineMediaPreparer.videoBitrate(sourceVideo: 800_000, fileBytes: 100_000_000, duration: 600, audio: 128_000) == 1_280_000)
        #expect(OfflineMediaPreparer.videoBitrate(sourceVideo: 40_000_000, fileBytes: 0, duration: 1, audio: 0) == 5_000_000)
        #expect(OfflineMediaPreparer.videoBitrate(sourceVideo: 0, fileBytes: 10_000_000, duration: 100, audio: 128_000) < 1_300_000)
        #expect(!OfflineMediaPreparer.durationMatches(28, expected: 60))
    }
}
