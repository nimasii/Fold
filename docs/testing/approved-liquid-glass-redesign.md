# Approved Fold cinema redesign

Base: `00d7455cf9825a136db07af443cbfdc9322f028c`, verified identical tree to `790bf2a`.
Design: `b28136369a7a9155b6b6596c9afda69420913482`, all 77 boards rendered and visually reviewed in four PDF contact sheets. Design PDFs remain outside this checkout and must not be merged into main.

Task checkout: `/Users/jake/Documents/Codex/2026-10-20/task-6/Fold`, branch `codex/approved-liquid-glass`. The original user checkout remains untouched, including its two untracked recovery/workflow files.

## Implementation

Shared cinema colors adapt to light/dark. Actual native `glass`, `glassProminent`, `GlassEffectContainer`, and `glassEffect` are gated to iOS 26+, with bordered/opaque fallbacks and reduced-transparency/contrast handling. Native tabs, navigation, menus, sheets, confirmation dialogs, AVKit and the external server sign-in webpage retain system ownership. Existing iOS 17 deployment support, TAClient scheme, signing and cloud workflows are unchanged. The approved app icon files are unchanged.

Library, search, channel, collections, video detail, local playback, Queue, Downloads, connection, settings/licenses and share-extension presentation use the shared hierarchy. Featured Play/Resume now requests real playback on detail navigation. New playlist creation uses one native sheet. Technical metadata stays available below description content. Queue remains server acquisition and Downloads remains private local media.

Artwork recovery normalizes legacy server paths, tries bounded same-origin server thumbnail routes and persists only private artwork/metadata. Saved video bytes are never replaced for artwork migration. Local image decoding is bounded and moved off the main actor. Queue list polling and row identity contracts remain intact.

Decorative connection artwork was generated with the built-in image tool and saved as `Fold/Assets.xcassets/ConnectionOcean.imageset/ocean.png`. Prompt: quiet cinematic low-angle open ocean, blue/teal rolling waves, pale sky and warm horizon, realistic editorial photography, no objects, text, UI, logos or watermark. It is not sample user-library media. Actual library thumbnails remain server/local sourced.

## Validation record

All media and acquisition mutations in UI tests use loopback-only fixture servers and an in-memory account. No real library data was deleted. Xcode 27.0, iOS 26.5 Simulator: iPhone 17 Pro and iPad Pro 13-inch (M5). Release targets iOS 17.0+ and includes the share extension.

- Final full unit suite: `unit-serialized-final.xcresult`, **779 passed, 0 failed, 0 skipped** (118.9s including build/run overhead). The earlier `unit-complete.xcresult` also passed all 779.
- Latest unsigned generic iOS **Release / TAClient passed** (`release-validated.xcresult`). Simulator builds and actual fixture launches passed throughout UI testing.
- Native and VLC streaming playback, pause, seek, fullscreen, pinning, and converted private offline playback passed (`player-create-ui.xcresult`, `accessibility-diagnosis.xcresult`). VLC testing exposed a real constant slider binding and paused-control visibility issue; both were fixed and the full flow passed.
- Login/token keyboard and failures, trusted server sign-in, blocked redirects, independent tab stacks, search return/cancel, empty/loading/error matrices and iPhone light/dark/large-type captures passed in `states-login-ui.xcresult` (**7/7**).
- iPad responsive light/dark/large-type matrix passed (`ipad-ui.xcresult`); six-screen landscape navigation passed (`ipad-landscape.xcresult`). A settled manual landscape Library screenshot confirmed the layout after rotation.
- **Settings, Queue and detail accessibility audits pass**, covering contrast, hit region, sufficient description and clipping (`accessibility-expand-controls.xcresult`). The handler collects every issue and fails if any are present; no issues are waived. Neutral native selected tabs and bottom scroll-edge handling avoid low contrast against glass. Queue row semantics, input growth, toolbar size and saved-host description were corrected from actual audit findings.
- Final `ui-complete.xcresult`: **7 passed, 1 failed**, zero skips. About/licenses/logout cancel, channel selection/batch-delete cancel, hero direct/repeated playback, playlist creation/local-remove cancel, responsive light/dark/large type, offline artwork repair/relaunch, and Queue acquisition/ignore/swipe/delete cancel/private playback/logout were executed. The one collection-to-channel assertion selected an offscreen duplicate channel label with XCTest firstMatch after lazy scroll restoration. The test now selects a fully visible link; the dedicated collection and channel-selection rerun **passed 2/2**, zero skips (`collection-verified.xcresult`), including actual metadata expansion. No shipping navigation change was needed.

Historical failures were investigated: the first 778-test unit run had one timezone-dependent epoch assertion, now comparing local Unix/ISO epoch consistently; one old collection row identifier and case-sensitive test label were corrected; the first orientation predicate was replaced by a Swift frame predicate. A concurrent final unit run reported one .invalidMedia result for the one-second VP9/Opus-in-MP4 conversion fixture. The entire suite then passed serialized without concurrent media UI tests; this is recorded as a non-reproduced resource-contention failure, not hidden. None of the earlier failed runs are counted as all-pass runs.

## Visual review and intentional adaptations

All 77 approved boards were rendered and reviewed before implementation. Final fixture captures were compared with the corresponding connection, library, collection, channel, detail, player, Downloads, Queue and settings families. Actual artwork and metadata come from each account's library; the fixture's credited media and synthetic test clip do not ship as production sample content.

Native Liquid Glass tab/search/navigation chrome, menus, sheets and confirmation dialogs take their system dimensions rather than the static mockup geometry. Selected native tabs use neutral ink for contrast; Fold red remains restrained in content actions. Forms use native controls and scrolling, with opaque reading surfaces. AVKit, PiP and server-owned login HTML retain their original system/server interfaces. The connected-server row displays the actual host rather than illustrative account data. iPad preserves landscape art and caps inline player/detail width instead of stretching phone controls.

## Screenshot evidence

Representative final production-view fixture captures: [Library](screenshots/library.jpg), [connection](screenshots/connection.jpg), [Downloads](screenshots/downloads.jpg), [Queue](screenshots/queue.jpg), [collections](screenshots/collections.jpg), [channel](screenshots/channel.jpg), [selection](screenshots/channel-selection.jpg), [detail](screenshots/video-detail.jpg), [expanded metadata](screenshots/video-metadata.jpg), [playlist sheet](screenshots/playlist-sheet.jpg), [Settings](screenshots/settings.jpg), [light appearance](screenshots/settings-light.jpg), [large type](screenshots/queue-large-type.jpg). Raw full-resolution captures and recordings remain in the xcresult evidence folder.

## Coverage checklist

Every design family maps to shipping implementation below. “Runtime family” means the relevant navigation/actions were executed; it does not imply every conditional substate was forced. Explicit source/unit-only and unavailable runtime checks remain listed.

| ID | Design family | Implementation | Current QA |
| --- | --- | --- | --- |
| 01 | Launch / restoring session | `Fold/FoldApp.swift`, `Fold/Presentation/Common/SplashView.swift` | Unit/source review; runtime detail pending |
| 02 | Connect to server | `Fold/Presentation/Login/LoginView.swift` | PASS LoginInterfaceUITests + ServerConnectionUITests |
| 03 | API token connection | `Fold/Presentation/Login/LoginView.swift` | PASS LoginInterfaceUITests + ServerConnectionUITests |
| 04 | Server sign-in sheet | `Fold/Presentation/Login/ServerSignInView.swift` | PASS LoginInterfaceUITests + ServerConnectionUITests |
| 05 | Library / discovery | `Fold/Presentation/VideoList/VideoListView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 06 | Library filters and sorting | `Fold/Presentation/Common/SectionMenu.swift`, `Fold/Presentation/VideoList/SortFilterBar.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 07 | Library multi-selection | `Fold/Presentation/VideoList/VideoListView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 08 | Search introduction / editing | `Fold/Presentation/Search/SearchView.swift`, `Fold/Presentation/Search/BottomLibrarySearch.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 09 | Search results | `Fold/Presentation/Search/SearchView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 10 | Channel detail | `Fold/Presentation/ChannelDetail/ChannelDetailView.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 11 | Channel About expanded | `Fold/Presentation/ChannelDetail/ChannelDetailView.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 12 | Channel multi-selection | `Fold/Presentation/ChannelDetail/ChannelDetailView.swift` | Selection and batch-delete cancellation passed in final regression |
| 13 | Playlists / collections | `Fold/Presentation/Playlist/PlaylistListView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 14 | Playlist filter | `Fold/Presentation/Playlist/PlaylistListView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 15 | Create playlist dialog | `Fold/Presentation/Playlist/PlaylistListView.swift`, `Fold/Presentation/VideoDetail/AddToPlaylistSheet.swift` | Native creation/keyboard/confirmation cancellation passed in final-ui.xcresult |
| 16 | Regular playlist detail | `Fold/Presentation/Playlist/PlaylistDetailView.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 17 | Custom playlist detail | `Fold/Presentation/Playlist/PlaylistDetailView.swift` | Responsive runtime capture plus playlist VM/unit coverage |
| 18 | Video detail / Description | `Fold/Presentation/VideoDetail/VideoDetailView.swift`, `Fold/Presentation/VideoDetail/VideoInfoSection.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 19 | Video technical details expanded | `Fold/Presentation/VideoDetail/VideoInfoSection.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 20 | Video comments and replies | `Fold/Presentation/VideoDetail/VideoDetailView.swift`, `Fold/Presentation/VideoDetail/CommentRow.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 21 | Similar videos | `Fold/Presentation/VideoDetail/SimilarVideosSection.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 22 | Add to playlist sheet | `Fold/Presentation/VideoDetail/AddToPlaylistSheet.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 23 | Add to playlist empty | `Fold/Presentation/VideoDetail/AddToPlaylistSheet.swift` | Source/VM branches preserved; exact runtime subvariant not separately forced |
| 24 | Native fullscreen playback | `Fold/Presentation/VideoDetail/VideoDetailView.swift`, `Fold/Presentation/Common/VideoPlayerSurface.swift` | Native/VLC playback/seek/fullscreen/pinning passed; actual system PiP transition unverified |
| 25 | VLC fullscreen playback | `Fold/Presentation/VideoDetail/VLCPlayerView.swift`, `Fold/Presentation/VideoDetail/VLCPlayerControls.swift` | Native/VLC playback/seek/fullscreen/pinning passed; actual system PiP transition unverified |
| 26 | Picture in Picture / pinned playback | `Fold/Presentation/VideoDetail/VideoDetailView.swift`, `Fold/Presentation/Common/VideoPlayerSurface.swift` | Native/VLC playback/seek/fullscreen/pinning passed; actual system PiP transition unverified |
| 27 | Downloads / ready on device | `Fold/Presentation/Offline/OfflineDownloadsView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 28 | Downloads / active transfers | `Fold/Presentation/Offline/OfflineDownloadsView.swift` | Transfer/filter actions and full offline unit suite passed; every progress substate not separately captured |
| 29 | Downloads information sheet | `Fold/Presentation/Offline/OfflineDownloadsView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 30 | Offline video detail / playback | `Fold/Presentation/Offline/OfflineDownloadsView.swift`, `Fold/Presentation/VideoDetail/VideoDetailView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 31 | Queue / pending | `Fold/Presentation/DownloadQueue/DownloadQueueView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 32 | Queue / ignored | `Fold/Presentation/DownloadQueue/DownloadQueueView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 33 | Queue / running task | `Fold/Presentation/DownloadQueue/DownloadQueueView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 34 | Queue / add link editing | `Fold/Presentation/DownloadQueue/DownloadQueueView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 35 | Queue item swipe actions | `Fold/Presentation/DownloadQueue/DownloadQueueView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 36 | Settings / playback preferences | `Fold/Presentation/Settings/SettingsView.swift` | Runtime settings/about/license navigation passed; full unit settings suite passed |
| 37 | Seek interval picker | `Fold/Presentation/Settings/SettingsView.swift` | Runtime settings/about/license navigation passed; full unit settings suite passed |
| 38 | About | `Fold/Presentation/Settings/AboutView.swift` | Runtime settings/about/license navigation passed; full unit settings suite passed |
| 39 | MobileVLCKit license | `Fold/Presentation/Settings/AboutView.swift` | Runtime settings/about/license navigation passed; full unit settings suite passed |
| 40 | Fold license | `Fold/Presentation/Settings/AboutView.swift` | Runtime settings/about/license navigation passed; full unit settings suite passed |
| 41 | Share extension / sending | `ShareExtension/ShareViewController.swift` | Release compilation and source/logic review; host-app extension invocation not executed |
| 42 | Share extension / success | `ShareExtension/ShareViewController.swift` | Release compilation and source/logic review; host-app extension invocation not executed |
| 43 | Share extension / errors | `ShareExtension/ShareViewController.swift` | Release compilation and source/logic review; host-app extension invocation not executed |
| 44 | Delete server video confirmation | `Fold/Presentation/VideoDetail/VideoDetailView.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 45 | Delete selected videos confirmation | `Fold/Presentation/VideoList/VideoListView.swift`, `Fold/Presentation/ChannelDetail/ChannelDetailView.swift` | Channel batch confirmation/cancel runtime passed; Library shares preserved logic/unit coverage |
| 46 | Delete queue item confirmation | `Fold/Presentation/DownloadQueue/DownloadQueueView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 47 | Delete playlist detail confirmation | `Fold/Presentation/Playlist/PlaylistDetailView.swift` | Runtime family passed in final-ui.xcresult; final collection regression in collection-verified.xcresult |
| 48 | Delete playlist from list confirmation | `Fold/Presentation/Playlist/PlaylistListView.swift` | Native creation/keyboard/confirmation cancellation passed in final-ui.xcresult |
| 49 | Remove local copy confirmation | `Fold/Presentation/Offline/OfflineDownloadsView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 50 | Sign out confirmation | `Fold/Presentation/Settings/SettingsView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 51 | Connection state board | `Fold/Presentation/Login/LoginView.swift`, `Fold/Presentation/Login/ServerSignInView.swift` | PASS LoginInterfaceUITests + ServerConnectionUITests |
| 52 | Library state board | `Fold/Presentation/VideoList/VideoListView.swift` | PASS CinemaState loading/error/empty screen families; not every subvariant forced |
| 53 | Search state board | `Fold/Presentation/Search/SearchView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 54 | Channel state board | `Fold/Presentation/ChannelDetail/ChannelDetailView.swift` | PASS CinemaState loading/error/empty screen families; not every subvariant forced |
| 55 | Playlist states board | `Fold/Presentation/Playlist/PlaylistListView.swift`, `Fold/Presentation/Playlist/PlaylistDetailView.swift` | PASS CinemaState loading/error/empty screen families; not every subvariant forced |
| 56 | Video content states board | `Fold/Presentation/VideoDetail/VideoDetailView.swift`, `Fold/Presentation/VideoDetail/CommentsSection.swift`, `Fold/Presentation/VideoDetail/SimilarVideosSection.swift` | PASS CinemaState loading/error/empty screen families; not every subvariant forced |
| 57 | Downloads empty / filtering / storage | `Fold/Presentation/Offline/OfflineDownloadsView.swift` | PASS relevant StreamingRedesign/InlineSearchArtwork family; see evidence limits below |
| 58 | Transfer failure / recovery states | `Fold/Data/Offline/OfflineRecord.swift`, `Fold/Presentation/Offline/OfflineDownloadsView.swift` | Full 779-test suite passed, including transfer failure/recovery cases |
| 59 | Queue loading / empty / failures | `Fold/Presentation/DownloadQueue/DownloadQueueView.swift` | PASS CinemaState loading/error/empty screen families; not every subvariant forced |
| 60 | Player overlays / download CTA states | `Fold/Presentation/Common/VideoPlayerSurface.swift`, `Fold/Presentation/VideoDetail/VideoDetailView.swift`, `Fold/Presentation/Offline/OfflineDownloadButton.swift` | Player/download unit suite and fullscreen runtime passed; skipped SponsorBlock overlay not forced |

## Runtime limits

- An actual iOS 17 runtime is not installed. Deployment/availability compilation and forced legacy navigation were verified; actual iOS 17 execution was unavailable.
- Host-app share-extension sending/success/error presentation, an actual system PiP transition, and SponsorBlock skip/Undo overlay were not forced at runtime. Their shipping logic is retained; extension compilation, player delegates and SponsorBlock unit coverage are not substitutes for those runtime checks.
- Add-to-playlist exact empty substate, launch restoration animation and every permission/storage/error combination were reviewed in source and covered by applicable unit/state tests, but not all were separately captured at runtime.
- Device signing, credentials, account access, cloud workflows, TAClient compatibility scheme and approved centered app icon were not changed. Local Release verification is unsigned; Apple distribution status is recorded separately after publication.

## Publication

Prepared as a fast-forward change from verified remote main `00d7455cf9825a136db07af443cbfdc9322f028c`. Commit and exact automatic Xcode Cloud outcome are reported with the delivery; no cloud workflow or build trigger is modified. No manual build trigger is used. App Store Connect currently redirects to an authentication-failed login page, so TestFlight distribution must be verified separately if that session remains unavailable.

All raw xcresults and exported screenshots are in the isolated task evidence folder at `/Users/jake/Documents/Codex/2026-10-20/task-6/evidence`. Design PDFs/rendered boards remain outside the repository under sibling `design-reference`.
