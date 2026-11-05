#if targetEnvironment(macCatalyst)
import Foundation
import Testing
@testable import Fold

private final class MacFixtureBundle: NSObject {}

@MainActor @Suite(.serialized)
struct MacCompatibilityTests {
    @Test func keychainPersistsAcrossServiceInstances() throws {
        let keychain = KeychainService(persistentFixture: true)
        defer { keychain.clearAll() }
        let saved = keychain.save("MAC_SYNTHETIC_TOKEN", for: .authToken)
        #expect(saved, "Keychain OSStatus: \(keychain.lastStatus ?? 0)")
        #expect(KeychainService(persistentFixture: true).load(for: .authToken) == "MAC_SYNTHETIC_TOKEN")
    }

    @Test func webMInspectionPreservesCodecAndConversionSafetyMetadata() async throws {
        let file = try #require(Bundle(for: MacFixtureBundle.self).url(forResource: "conversion-vp9-opus", withExtension: "webm"))
        let source = try await MacOfflineMediaInspector.inspect(file)
        #expect(source.duration > 0)
        #expect(source.streams.contains { $0.type == "video" && $0.codec.contains("vp9") })
        #expect(!source.unsafeColorOrRotation)
    }

    @Test func inspectionRejectsNetworkLocations() async {
        do {
            _ = try await MacOfflineMediaInspector.inspect(URL(string: "https://example.com/private.webm")!)
            Issue.record("Metadata inspector must remain file-only")
        } catch { #expect(error as? OfflineFailure == .invalidMedia) }
    }
}
#endif
