# Unified Library and Downloads playback

Built on released Queue fix `9d5dcb0b492dbe4c65bd191d79041f3cfe98e915`. Work and validation use an isolated checkout; the original checkout, user edits, signing, icon, schemes and Xcode Cloud workflows are preserved.

## Resulting behavior

Library, continue watching, channel, playlist, search, similar-video and Downloads routes resolve one real video identity. The identity contains the canonical server installation (including base path), verified public account ID and video ID; it contains no credentials or token hash. A validated, completed matching local copy is selected before detail preloading or stream creation. Missing, partial or invalid copies fall back to streaming when available without deleting bytes or history. Converted native-compatible files retain their real video identity.

A separate observable durable journal projects the same position/watched state into both surfaces. Native and VLC playback report genuine progress, pause, seek, rewind, close, background and completion actions into that journal. Monotonic revisions and player-generation/observation guards preserve the latest local action, including zero and backwards seeks, rather than the maximum position. VLC seek confirmation accounts only for actual playing time, so stale pre-seek notifications cannot undo a paused seek and coalesced clock delivery cannot freeze progress indefinitely. Native AVKit remains system-owned.

History persists before it is published. Storage failures are visible and do not acknowledge unsaved state; damaged/future archives are preserved. Removing a local download has no history-deletion operation. Server deletion has no local-file deletion operation. Account/session changes invalidate old player and sync generations. Account associations restored offline are reverified before server import or synchronization; a transient outage can still read the already-scoped offline copy. A different account cannot download/retry another account's record or expire its own session through that mismatch.

New downloads retain verified ownership and initial progress. Existing files and private bookmarks survive unchanged. Legacy bytes may be reused after authenticated ID/origin/media-path matching, without adopting their unowned bookmark. An explicit history-link choice retains the prior device bookmark separately, with an action to resume it. Ownership is never guessed from server origin or the current login alone. Local artwork is reused by shared cards; refreshed metadata retains playlist and SponsorBlock information.

## Synchronization and honest limits

An account-scoped coalesced outbox uses existing server APIs, retains failures, bounds each drain and throttles retries. Every mutation checks the captured authorization ID/account; an old response cannot acknowledge a newer action. Watched mutations precede progress reset and position writes. Foreground/connectivity changes retry pending work. A pending-sync message explains when the device has saved progress but the server has not accepted it.

Upstream TubeArchivist source was inspected at `feec5b8f6fc5537088b77b4648439b0acba248a3`, not the owner's physical server:

- [Video progress API](https://github.com/tubearchivist/tubearchivist/blob/feec5b8f6fc5537088b77b4648439b0acba248a3/backend/video/views.py) ignores POST positions at five seconds or less and exposes no modification timestamp or conditional-write version. A genuine first-seconds rewind/reset DELETEs stale server progress while retaining the exact local point; it cannot make the server retain an unsupported precise point.
- [Watched implementation](https://github.com/tubearchivist/tubearchivist/blob/feec5b8f6fc5537088b77b4648439b0acba248a3/backend/common/src/watched.py) clears progress when watched changes. Watched is shared server metadata; resume progress is user scoped. Ordering preserves both intents.
- [Completion rules](https://github.com/tubearchivist/tubearchivist/blob/feec5b8f6fc5537088b77b4648439b0acba248a3/backend/common/src/helper.py) use half of videos shorter than a minute, 90% through 15 minutes, and all but the final three minutes thereafter. Finished timelines resume at zero; a partial rewatch retains its position even when watched remains true.

Because the server provides no genuine action clock/CAS and can expire progress, a local viewing action stays authoritative on this device even after an acknowledgement/echo. Unversioned refreshes cannot safely prove that a different position is newer. Remote progress seeds videos with no local action. This delivers reliable same-device Library/Downloads continuity and supported outgoing synchronization; perfect cross-device latest-action merging is not claimed. No backend/security changes were made.

## Validation

All HTTP/UI fixtures use synthetic credentials, loopback ports and isolated app storage. The 72-second native/VP9 clips are generated in a temporary directory by looping existing small test assets; no new sample media is included in the shipping app. No real user library data is deleted or credentials reset.

| Check | Result/evidence outside repository |
| --- | --- |
| Final full unit suite | **832 passed, 0 failed, 0 skipped**: `../evidence/unified-history-final-units.xcresult` (37 more than released baseline795) |
| Earlier full suite | 830 passed, 0 failed/skipped: `unified-history-full-unit-retry.xcresult`; precedes final seek gate/account retry regressions |
| Native HTTP UI | `testLibraryDownloadSharedResumeOfflineRelaunchAndReconnect` passed in `unified-history-ui-zero-and-vlc.xcresult`. Actual native advancement/pause, Library local selection, Downloads equal point, offline relaunch, genuine backwards/zero engine/journal equality, reconnect reset, and zero extra media requests after download. The other older VLC test in that bundle failed and was subsequently repaired. |
| VLC HTTP UI | 1 passed, 0 failed/skipped: `unified-history-vlc-coalesced-clock.xcresult`. Real VP9 playback, paused forward/back seeks confirmed against engine plus actual playing clock, converted download reopening natively at the same point, zero extra media requests. |
| iPad landscape/light/large type | 1 passed, 0 failed/skipped: `unified-history-ipad-final.xcresult`. Library/Downloads same seeded point, offline relaunch, hit regions/descriptions/clipping and contrast audit with independently measured contrast described below. |
| Final Release | **BUILD SUCCEEDED**, unsigned generic iOS Release with unchanged TAClient scheme: `../evidence/unified-history-final-release.xcresult` and `.log`. Signing configuration untouched. |

The 37 added unit/integration cases cover server/account/base-path separation and persistence, wrong-account retry, account revalidation, storage error/retry/corrupt archives, cancelled and stale sync, overlapping reads and acknowledgements, rewind/reset/completion thresholds, legacy adoption and bytes reuse, signed-out scoped local actions, missing/corrupt/partial-file fallback, metadata, all collection projections and local source selection across all six route families without detail/preloader/stream requests. The final full count is verified from the actual runner, not inferred from the prior baseline. Non-failing runner warnings: actor-isolated test helper default initialization (one new helper and existing ObserverBag helper), plus the existing VLCKit dav1d tile option. No test failed or was skipped.

### Accessibility audit discrepancy

On the iOS 26.5 iPad simulator, the native contrast audit flagged the resume caption and channel text even after both rendered black on the light canvas. Full-screen screenshots and individual element captures establish a native false positive: the repeated element captures measure **19.2507:1** ink/canvas contrast (minimum required 4.5:1). The original secondary resume caption was strengthened to the semantic label color.

The UI test independently measures actual screenshot pixels only for those two reproduced nodes on iOS 26.5; it still fails if measurement is unavailable or below 4.5:1. Every other contrast finding, and every other audit type on these nodes, remains a failure. The raw native reports, measured values and cropped element screenshots are attached to the passing result and exported under `../evidence/unified-ipad-final-shots/`. No unexplained finding is waived. Test-only numeric engine probes are absent from the accessibility scenario and compiled out of Release.

### Visual evidence

Reviewed genuine runtime captures preserve the approved artwork-led hierarchy, native glass navigation/actions, reading width, typography and responsive layout. Synthetic artwork/diagnostic probes in test captures are fixture evidence, not shipping library content. Representative exports:

- `../evidence/unified-history-ui-zero-vlc-shots/`: native Library/Downloads/offline/reconnect captures (manifest maps original names).
- `../evidence/unified-vlc-final-shots/`: paused VLC rewind and native local resume.
- `../evidence/unified-ipad-final-shots/`: Library, Downloads and offline relaunch in landscape/light/large type; exact contrast evidence.

## Verification limits

No physical iPhone or physical user server reproduction is claimed. Only iOS 26.5 simulator runtime is installed; iOS 17 availability support compiles but was not run on an iOS 17 simulator. Termination/relaunch persistence, background reconnect and both engines were exercised as above; abrupt OS power loss, actual cellular reconnection, physical AirPlay/PiP and cross-device conflict resolution are not claimed by this enhancement. The prior redesign's separate UI inventory/QA report remains at `approved-liquid-glass-redesign.md`.

After successful validation, publish only this scoped change, verify the exact remote commit and automatic Xcode Cloud action. Do not manually trigger a duplicate. Archive success alone does not prove TestFlight processing or tester availability; the existing App Store Connect session previously required login.

## Task process cleanup

After runtime/unit validation, the exact fixture server PID53514 was verified and stopped with SIGTERM; it had no child processes. Both task-only simulators were shut down by their exact UUIDs. `simctl list devices booted` returned no booted devices. No fixture, test runner, media generator, diagnostic Swift process or log stream remained; the final Release compiler was retained until its successful exit, then also exited. Shared app-managed MCP tool services and unrelated user applications were not terminated. No virtual desktop/display was created or user windows moved.

Release compiler warnings: one unused immutable history binding in the coordinator guard, the unchanged AuthProxy weak-capture warning, and expected skipped App Intents metadata extraction without an AppIntents dependency. No compiler error.
