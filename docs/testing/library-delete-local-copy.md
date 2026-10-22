# Library deletion and linked local-copy removal

Base: latest main/icon commit `4f3500ccd13e4934466965fe5f032b3afaf7c3ed`. Prepared on isolated branch `codex/library-delete-local`. Publication is not authorized for this change; no push or Xcode Cloud trigger is part of this preparation.

## Behavior

Confirmed video deletion through detail (including Delete and ignore), Library selection or channel selection also removes that account's matching linked local downloads on this device. Matching uses canonical server installation/base path, verified account ID and real video ID. The same video ID belonging to another account, server or base-path installation is preserved.

The server must return an actual successful DELETE response first. Network failure, cancellation without a confirmed response, authentication/permission failure, not-found and other server errors keep the local copy and resume history. There is no queued offline server-deletion request. A success already returned for the captured connection can finish cleanup for that original account after an account switch; it cannot navigate or mark deletion in the replacement account's UI. Ordinary API response/authentication checks remain unchanged.

After confirmation, matching playback is stopped, active transfers/conversions/artwork work are cancelled, media/artwork/manifest metadata are removed, and the shared resume/watched bookmark and outgoing progress work are removed. A durable scoped deletion marker rejects stale pre-delete reads and player callbacks. New authoritative server retrieval after reacquisition can establish new history. Continue watching cannot retain a deleted local item. Video cache invalidation targets the deleted video and still-active captured authorization instead of clearing a different cached video.

A successfully persisted marker also retries interrupted local cleanup at launch/foreground. If journal or disk/manifest cleanup fails, the app reports that server deletion succeeded but local cleanup is pending, blocks late progress resurrection in the active session, and retries; Downloads still offers manual local removal. If the journal itself cannot be written and the app closes before storage recovers, that confirmation cannot be recovered from an unwritten marker; the retained copy may require manual removal in Downloads. Existing bytes are preserved in that failure case. A server success is not falsely presented as a server failure simply because local cleanup needs retry.

If the separate ignore request fails after successful deletion, Library and Downloads still reflect the completed deletion and the ignore error stays visible.

### Preserved boundaries

- Downloads-only removal retains shared Library history and never issues server deletion.
- Older device-only downloads without an account owner are **not automatically removed**. Their ownership cannot safely be inferred from a matching ID/origin or whichever account is currently signed in. The confirmation explicitly says linked downloads are removed and unlinked device-only copies are kept. They remain removable from Downloads or can be explicitly linked through the existing account-history action.
- This change covers explicit video deletion paths. Removing a video from a custom playlist and deleting a playlist retain their existing separate semantics.
- No signing, workflow, credentials, permissions, icon or unrelated UI redesign changes.

## Validation

All destructive tests operate on disposable app-private fixture directories or the synthetic loopback server. No user videos, account credentials or real server library contents are deleted for validation.

| Check | Result |
| --- | --- |
| Focused deletion + journal tests | 25 passed, 0 failed/skipped, `../evidence/library-delete-focused-retry.xcresult` |
| Expanded deletion + shared-progress races | 31 passed, 0 failed/skipped, `library-delete-races.xcresult` |
| Full final unit suite | **843 passed, 0 failed, 0 skipped**: `../evidence/library-delete-final-units.xcresult` |
| Native fixture UI | **1 test passed, 0 failed/skipped**, covering both failed and successful server outcomes, confirmation dismissal and offline relaunch: `library-delete-ui-paused.xcresult` |
| Generic iOS Release / TAClient | **BUILD SUCCEEDED**, unsigned generic iOS destination, unchanged TAClient scheme: `../evidence/library-delete-release.xcresult` and `.log` |

The added deletion cases exercise scoped ready-file/artwork/manifest/history removal and relaunch, preservation after 401/403/404/500, offline and interrupted requests, account switch after transmission, active native-player teardown/restart/save guards, cancelled download and conversion late completion, journal and manifest failures/retry, startup cleanup recovery, stale read rejection vs new server reacquisition, delete-and-ignore partial success, and unchanged Downloads-only history/server behavior.

The first full run passed842 tests and failed one existing sync-cancellation test. Investigation found earlier tests could leave a delayed coordinator drain alive against the next test's shared mock handler; the wait also accepted any request as its start signal. Added explicit coordinator shutdown at test boundaries and required the intended old-video request before switching accounts. All original cancellation assertions remain, and the affected31-test run passed. The final full run verifies isolation across the entire suite.

The first compile attempt inferred MainActor isolation for the entire player model from its observer protocol. Isolation was narrowed to the deletion callback; compilation and subsequent focused runs passed. Intentionally invalid-image fixtures can emit ImageIO diagnostics; these are distinct from failing test assertions.

Physical device, physical PiP transition, OS power-loss interruption and Jake's actual server were not exercised. Native/VLC share the same deletion observer/model teardown; native fixture playback and in-flight native conversion are tested, while a physical VLC/PiP deletion transition is not claimed. Only iOS26.5 simulator runtime is installed.

UI harness notes: iOS26 native confirmation renders a popover dismiss region instead of a Cancel row; the test uses that observed native region and verifies zero DELETEs after dismissal. XCTest also waited60sec for active-video/glass-menu animation quiescence; the final UI scenario first verifies real AVKit playing then paused status before reopening the menu. All deletion/copy/outcome assertions remain. Active-player teardown and restart/save rejection are independently covered by the player-model regression.

Reviewed screenshots exported under `../evidence/library-delete-ui-shots/` with manifest: failure retains the3.3MB copy after offline relaunch; confirmed success shows ZeroKB/NoDownloadsYet after offline relaunch. Confirmation screenshots include the local-copy/history disclosure.

Cleanup verified: task fixture PID43664 stopped with SIGTERM; iPhone17Pro simulator already Shutdown at cleanup and booted-device inventory empty. No task xcodebuild, UI runner, media converter or log stream remained. No unrelated applications were opened/closed for this phase. Final Release warnings are the pre-existing unused history binding and AuthProxy weak-capture warning, plus expected skipped AppIntents metadata extraction. No compiler errors.
