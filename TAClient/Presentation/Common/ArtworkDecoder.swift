import UIKit
import ImageIO

/// Decode a bounded display bitmap off the main actor, including camera rotation.
/// Cost the decoded pixels rather than the much smaller compressed JPEG payload.
enum ArtworkDecoder {
    nonisolated static func image(from data: Data, maxPixelSize: Int = 1280) -> UIImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: bitmap)
    }

    nonisolated static func cost(of image: UIImage) -> Int {
        guard let bitmap = image.cgImage else { return 0 }
        return bitmap.bytesPerRow * bitmap.height
    }
}
