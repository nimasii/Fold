import UIKit
import Testing
@testable import Fold

@MainActor
struct ArtworkDecoderTests {
    @Test func largePosterIsBoundedAndChargedForDecodedPixels() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4096, height: 2048), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4096, height: 2048))
        }
        let compressed = try #require(image.jpegData(compressionQuality: 0.8))
        let result = try #require(ArtworkDecoder.image(from: compressed))
        let bitmap = try #require(result.cgImage)
        #expect(bitmap.width == 1280)
        #expect(bitmap.height == 640)
        #expect(ArtworkDecoder.cost(of: result) == bitmap.bytesPerRow * bitmap.height)
        #expect(ArtworkDecoder.cost(of: result) > compressed.count)
    }

    @Test func malformedAndInvalidSizeAreRejected() {
        #expect(ArtworkDecoder.image(from: Data("not an image".utf8)) == nil)
        #expect(ArtworkDecoder.image(from: Data(), maxPixelSize: 0) == nil)
    }
}
