import Foundation

/// Owns only its private directory. File paths use UUIDs and a closed extension enum.
nonisolated final class OfflineDiskStore: @unchecked Sendable {
    let root: URL
    private let files: FileManager
    private var manifest: URL { root.appendingPathComponent("library.json") }
    private var media: URL { root.appendingPathComponent("Media", isDirectory: true) }
    private var staging: URL { root.appendingPathComponent("Staging", isDirectory: true) }

    init(root: URL, files: FileManager = .default) throws {
        self.root = root; self.files = files
        for url in [root, media, staging] {
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
        guard let url = file(for: record), files.fileExists(atPath: url.path) else { return }
        try files.removeItem(at: url)
    }
    func cleanOrphans(keeping records: [OfflineRecord]) throws {
        let keep = Set(records.filter { $0.status == .ready }.compactMap { file(for: $0)?.lastPathComponent })
        for url in try files.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) { try files.removeItem(at: url) }
        for url in try files.contentsOfDirectory(at: media, includingPropertiesForKeys: nil) where !keep.contains(url.lastPathComponent) {
            try files.removeItem(at: url)
        }
    }
}
