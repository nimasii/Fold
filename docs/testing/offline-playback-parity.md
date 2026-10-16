# Offline playback uses the production player

`OfflinePlayerScreen` owns `VideoDetailViewModel` and presents `VideoDetailView`, exactly as the online `VideoDetailScreen` does. `LocalVideoPlayback` supplies a private file URL, saved presentation metadata and private artwork. `LocalVideoRepository` saves viewing progress only in the local library and has no server transport. Local AVPlayer startup joins `beginAVPlayback`; local VLC startup supplies its file to the same `VLCPlayerView` and `VLCPlayerControls`. Online authentication, caching and proxy transport remain in their existing paths.

Previously, downloads used a separate `OfflinePlayback` controller and a separate selector that forced every WebM file into VLC. Online selection used stream codecs. Both now use `CodecSupport`, with the same conservative WebM fallback when stream metadata is absent. Legacy downloads recover stream codecs from their existing manifest; no media migration or redownload is needed. Downloaded AVPlayer media still disables external playback and never starts the cache, auth proxy or an AirPlay transfer. Missing private files fail visibly without a network fallback. Local playback uses the normal Play affordance and shared settings object.

The shared VLC implementation also had an unused fullscreen binding. Fullscreen presentation now publishes ownership before the detail screen disappears and clears it after the screen reappears, preventing the detail lifecycle from stopping the player during the transition.

## Reproduce the production-path comparison

1. Start `python3 Tests/Fixtures/playback_parity_server.py` on the Mac running Simulator. This serves only generated H.264/MP4 and VP9/WebM clips on loopback port 18083, checks a fixed fixture cookie, and implements byte ranges. There are no owner endpoints, credentials or archive writes.
2. Run scheme `ConnectionFlow`, selecting `TAClientUITests/PlaybackParityUITests`, against iPhone Simulator. Both tests target the shipping `TAClient` app including MobileVLCKit, not `UIReviewPreview`.
3. Each test downloads a real private local copy, plays the same bytes online through the normal authenticated cache or proxy, then makes the fixture server return 503 and opens the normal Downloads destination. It checks playback advancement, play/pause, scrubbing, pinning and fullscreen entry/exit for both sources. The media-request count must remain unchanged during local playback. Screenshots and control trees are retained in the xcresult.

The metadata repository in this harness returns a synthetic video and no-ops progress updates. Engine selection, views, controllers, media transport, local downloads and native/VLC decoding are production implementations. The harness is compiled only for Debug Simulator. It uses in-memory authentication and its own library and settings domains, never persisted owner credentials or downloads.

The clips are procedural FFmpeg `testsrc2` output (640×360, 24 fps, 12 seconds, no audio): H.264 using `libx264 -preset fast -crf 30 -movflags +faststart`, VP9 using `libvpx-vp9 -b:v 0 -crf 42 -deadline realtime -cpu-used 8`.

## Verification limits

Unit coverage includes codec parity, legacy metadata, missing-file failure, local-only progress, shared settings, ordinary AVPlayer item configuration, end/retry handling, no proxy startup and fullscreen ownership. Simulator UI tests establish both actual engine/control paths. They do not establish physical-device hardware decoding, headphones/interruptions, lock-screen audio, PiP, or owner media behavior. Those require a subsequent approved device/TestFlight check. The existing normal VLC player has no PiP or lock-screen remote controls; this change preserves its capabilities for both sources. SponsorBlock segments are not in existing offline snapshots, so offline playback does not invent segment data.
