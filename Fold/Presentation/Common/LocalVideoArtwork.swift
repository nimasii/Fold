import Foundation

/// Explicit local sources; a missing image never falls back to remote artwork in Downloads.
struct LocalVideoArtwork {
    var thumbnail: URL?
    var channel: URL?
    var revision = 0
}
