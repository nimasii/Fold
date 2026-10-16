import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum OfflineArtworkKind: String, CaseIterable { case thumbnail, channel }

/// Owns only its private directory. File paths use UUIDs and a closed extension enum.
nonisolated final class OfflineDiskStore: @unchecked Sendable {
    let root: URL
    private let files: FileManager
    private var manifest: URL { root.appendingPathComponent("library.json") }
    private var media: URL { root.appendingPathComponent("Media", isDirectory: true) }
    private var staging: URL { root.appendingPathComponent("Staging", isDirectory: true) }
    private var artwork: URL { root.appendingPathComponent("Artwork", isDirectory: true) }

    init(root: URL, files: FileManager = .default) throws {
        self.root = root; self.files = files
        for url in [root, media, staging, artwork] {
            try files.createDirectory(at: url, withIntermediateDirectories: true)
            try protect(url)
        }
    }
    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("OfflineDownloads-v1", isDirectory: true)
    }
    private func protect(_ url: URL) throws {
        var url = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }
    func load() throws -> [OfflineRecord] {
        guard files.fileExists(atPath: manifest.path) else { return [] }
        return try JSONDecoder().decode([OfflineRecord].self, from: Data(contentsOf: manifest))
    }
    func save(_ records: [OfflineRecord]) throws {
        try JSONEncoder().encode(records).write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try protect(manifest)
    }
    func file(for record: OfflineRecord) -> URL? {
        record.kind.map { media.appendingPathComponent(record.id.uuidString + "." + $0.rawValue) }
    }
    func exists(_ record: OfflineRecord) -> Bool {
        guard let url = file(for: record), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size > 0 && Int64(size) == record.bytes
    }
    func checkCapacity(_ expected: Int64) throws {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           expected > max(0, available - 16_000_000) { throw OfflineFailure.storage }
    }
    /// Must run synchronously before URLSession's temporary-file callback returns.
    func stage(_ temporary: URL) throws -> URL {
        let destination = staging.appendingPathComponent(UUID().uuidString + ".part")
        try files.moveItem(at: temporary, to: destination)
        do { try protect(destination) } catch { try? files.removeItem(at: destination); throw error }
        return destination
    }
    func commit(_ staged: URL, record: OfflineRecord, response: HTTPURLResponse) throws -> (OfflineMediaKind, Int64) {
        let size = Int64(try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size > 12, response.expectedContentLength < 0 || response.expectedContentLength == size,
              response.value(forHTTPHeaderField: "Content-Range") == nil else { throw OfflineFailure.invalidMedia }
        let handle = try FileHandle(forReadingFrom: staged); defer { try? handle.close() }
        let header = try handle.read(upToCount: 16) ?? Data()
        let kind: OfflineMediaKind
        if header.count >= 8 && Array(header[4..<8]) == Array("ftyp".utf8) { kind = .mp4 }
        else if header.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { kind = .webm }
        else { throw OfflineFailure.invalidMedia }
        var candidate = record; candidate.kind = kind
        let target = file(for: candidate)!
        if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
        try files.moveItem(at: staged, to: target)
        do { try protect(target) } catch { try? files.removeItem(at: target); throw error }
        return (kind, size)
    }
    func discard(_ staged: URL) { try? files.removeItem(at: staged) }
    func remove(_ record: OfflineRecord) throws {
        if let url = file(for: record), files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
        for kind in OfflineArtworkKind.allCases {
            let url = artworkFile(record.id, kind: kind)
            if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
        }
    }
    private func artworkFile(_ id: UUID, kind: OfflineArtworkKind) -> URL {
        artwork.appendingPathComponent(id.uuidString + "-" + kind.rawValue + ".jpg")
    }
    func artworkURL(_ id: UUID, kind: OfflineArtworkKind) -> URL? {
        let url = artworkFile(id, kind: kind)
        return files.fileExists(atPath: url.path) ? url : nil
    }
    func saveArtwork(_ data: Data, id: UUID, kind: OfflineArtworkKind) throws {
        guard data.count <= 4 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: kind == .thumbnail ? 1024 : 160,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw OfflineFailure.invalidMedia }
        // Re-encode only pixels, without remote metadata or EXIF fields.
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { throw OfflineFailure.storage }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw OfflineFailure.storage }
        let target = artworkFile(id, kind: kind)
        try (jpeg as Data).write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try protect(target)
    }
    func cleanOrphans(keeping records: [OfflineRecord]) throws {
        let keep = Set(records.filter { $0.status == .ready }.compactMap { file(for: $0)?.lastPathComponent })
        for url in try files.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) { try files.removeItem(at: url) }
        for url in try files.contentsOfDirectory(at: media, includingPropertiesForKeys: nil) where !keep.contains(url.lastPathComponent) {
            try files.removeItem(at: url)
        }
        let artworkKeep = Set(records.flatMap { record in OfflineArtworkKind.allCases.map { artworkFile(record.id, kind: $0).lastPathComponent } })
        for url in try files.contentsOfDirectory(at: artwork, includingPropertiesForKeys: nil) where !artworkKeep.contains(url.lastPathComponent) {
            try files.removeItem(at: url)
        }
    }
}
