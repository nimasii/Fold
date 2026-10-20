# Fold streaming layout and durable thumbnail recovery

20 October 2026. Base: `790bf2a92fc5662ab3cfcc94cf6263ff4756bce4` (the approved, centered Fold icon).

Library keeps the three useful destinations—Library, Downloads and Queue—and the native search affordance. Its feature uses landscape YouTube artwork, an adaptive fade, title/channel/duration and one clear action. Continue watching and recent shelves follow; collections no longer precede the feature. Downloads has a compact on-device summary and artwork beside active/interrupted transfers. Queue uses a large native title; its inset backgrounds respect the navigation safe area so they cannot cover that title. It retains the stable list, safe-area progress header, privilege checks, swipe confirmations and pagination/polling behavior.

The composition adapts Apple TV's artwork-first hierarchy and streaming shelves to YouTube's landscape stills and channel metadata. It does not introduce recommendations, auto-play, new destinations or playback behavior.

## Thumbnail diagnosis and changes

The previous thumbnail URL handling concatenated strings. A server URL ending in `/` and a root-relative image produced a doubled separator; a cache-relative image could produce an invalid host/path combination. Missing Queue URLs had no recovery path. Tube Archivist versions have used both `/cache/videos/<first lowercase character>/<youtubeID>.jpg` and `/media/thumb/video/<youtubeID>.jpg`; its API can also return no thumbnail metadata.

`ServerArtwork` normalizes root-relative, cache-relative and same-origin absolute image paths. Queue and library metadata use this resolver. If a valid eleven-character YouTube ID has missing artwork, or the supplied Queue image fails, bounded modern/legacy server routes are tried. Foreign, credential-bearing, signed, protocol-relative and traversal paths are rejected. The image loader continues using scoped server authorization and the existing negative cache. No request with server credentials goes to YouTube's thumbnail CDN.

Private downloaded artwork remains sanitized JPEG data under Application Support, separate from purgeable URL/image caches. A confirmed repair gap was that a nonempty saved artwork path returning 404 never triggered a metadata reread. Missing/corrupt local images now first try saved paths and compatible routes, then refresh stale metadata when necessary. Older copies without metadata can still recover a cached thumbnail even when their archived video detail is unavailable. Existing origin/revocation checks, bounded image transport, backup exclusion and retry throttling remain. Repair modifies metadata/artwork only and preserves already-good local images and every saved video byte. The manifest format and media preparation/playback are unchanged.

## Verification

Final unit verification: **778 passed, 0 failed** on iPhone 17 Pro / iOS 26.5 (`TAClient`, `TZ=UTC`). The final production Release iOS build also succeeded with signing disabled for local compile verification. The earlier full run had one unchanged cache timing failure, which passed alone and then passed in this final complete run. The fixture account and storage are isolated from owner credentials and media. Queue fixtures now pass through the production DTO mapper, including a trailing-slash server and a bare relative artwork path, rather than constructing domain rows directly.

The original eight feature/navigation UI scenarios all passed across the completed initial and focused repeat runs. Four native-control failures on iPhone 17e passed unchanged on the existing iPhone 17 Pro rerun; those initial automation failures remain documented in the result bundles. The first checks after the Queue title correction passed compact Queue loading/control states. Two further failures captured native controls still in their previous state after synthesized taps (Library remained selected after a Queue tap; Search remained focused after a Close tap). The UI harness now verifies selection/dismissal and makes at most one additional tap when the native transition has not completed; all destination/content assertions remain. A direct native drag also verified Ignore/Delete in the live simulator. The test now waits for keyboard dismissal, drags across the full visible row, and waits for the native action. Final focused results: compact Queue controls/loading **1/1 passed**, native plus legacy accessibility/search **1/1 passed** (three text/navigation configurations), Queue actions/private offline playback/logout **1/1 passed**. No destination, persistence, media-request or confirmation assertions were removed.

Regression tests cover path normalization, missing Queue metadata, origin/traversal boundaries, stale404 metadata repair, cache-only legacy recovery after detail404, media-byte preservation, private image persistence across signed-out restart, corrupt/missing artwork, failures/cooldowns, authorization changes and cancellation. Existing download tests cover repeated requests, interrupted transfers, retries and local playback. Production-screen UI checks cover online images, offline/relaunch persistence and repair, native playback, Queue transitions, light/dark, large text, scrolling, independent navigation and search.

Simulator tests do not establish physical-device airplane-mode behavior, file protection, VoiceOver, AirPlay, battery/performance or a live owner-server sign-in. No icon, app identity, authorization, owner data, playback implementation or Cloud workflow settings are changed. The pre-existing untracked Cloud manifest is excluded from this change.

## Official references inspected

- [Apple TV app](https://www.apple.com/apple-tv-app/) — current artwork hierarchy and shelves, inspected visually.
- [Apple TV iPhone screenshots](https://apps.apple.com/us/app/apple-tv/id1174078549) — current native navigation and content presentation, inspected visually.
- [Prime Video iPhone screenshots](https://apps.apple.com/us/app/amazon-prime-video/id545519333) — compact download summary, thumbnail rows and streaming content hierarchy, inspected visually.
- [YouTube iPhone app](https://apps.apple.com/us/app/youtube/id544007664) and [YouTube You tab](https://support.google.com/youtube/answer/9209643?hl=en) — watched/saved/downloaded content and channel-oriented browsing.
- [Tube Archivist response processing](https://github.com/tubearchivist/tubearchivist/blob/master/backend/common/src/search_processor.py) and [thumbnail storage](https://github.com/tubearchivist/tubearchivist/blob/master/backend/download/src/thumbnails.py) — thumbnail metadata, current authenticated route and older cache layout.
- [Apple image guidance](https://developer.apple.com/design/human-interface-guidelines/images) — aspect ratios, placeholders and adaptive content.

## Review captures

Actual shipping views under the isolated synthetic fixture account, with credited NASA stills.

- [Library, dark appearance](../screenshots/streaming-recovery/library-dark.png)
- [Queue, light appearance](../screenshots/streaming-recovery/queue-light.png)
- [Accessibility text with fallback navigation](../screenshots/streaming-recovery/accessibility-fallback.png)
- [Queue title and thumbnails, dark appearance](../screenshots/streaming-recovery/queue-dark.png)
- [Downloaded artwork after offline relaunch](../screenshots/streaming-recovery/downloads-offline.png)

## Reproduction and retained results

- Units: `TAClient`, `FoldTests`, serial testing, `TZ=UTC` — `FoldVerifiedUnit.xcresult` (778/778).
- Final UI: `ConnectionFlow`, iPhone 17 Pro / iOS 26.5 — `FoldVerifiedUI.xcresult` (compact Queue pass; initial two automation failures), `FoldVerifiedNavigation.xcresult` (accessibility pass; initial swipe failure), `FoldVerifiedQueue.xcresult` (complete Queue scenario pass after gesture correction).
- Existing recovery evidence: `FoldUI.xcresult` and `FoldUIRepeat.xcresult`; all eight original scenarios have successful runs. Initial failures remain retained rather than being reported as a clean single run.
- Final Simulator build and unsigned Release iOS device compile both passed. Release log ends `BUILD SUCCEEDED`.
- Test bundles and logs are retained in the local task evidence. The screenshot links above are committed review copies.

The approved centered icon at base `790bf2a` is unchanged. The compatibility `TAClient` scheme and automatic Cloud workflow settings are unchanged. This commit is intended for the already-authorized main release; automatic archive and internal TestFlight outcomes are recorded separately after the push.
