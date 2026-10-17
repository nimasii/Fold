# Streaming interface review

This branch reorganizes the existing archive around Watch, Search, Library and private Downloads. Watch features the first video in the current default archive response, progress-bearing videos from that loaded response, and recently archived videos. These shelves do not claim to be personalized recommendations or a complete watch-history service. Changing filters keeps the normal complete archive grid and its existing pagination.

Each tab owns a native navigation stack. `AppRouter.path` continues to target the active tab so existing view models and route actions work unchanged; tab paths and selection reset on logout, session expiry and a new sign-in. Named `*Screen` wrappers continue owning their view models. Native AVKit/VLC, media authorization, server login, session restoration and private download conversion retain their existing implementations.

Content uses opaque adaptive system surfaces with system navigation supplying glass. Artwork has bounded aspect ratios, responsive grids and native text styles. Decorative images ignore hit testing, since clipping a portrait bitmap does not constrain SwiftUI hit regions; controls beside cropped artwork remain reachable. Accessibility sizes use stacked Watch filters and a separate image/text hero. Video and channel actions are distinct real buttons; selection has a named VoiceOver action and selected traits, with touch long press retained. Reduce Motion disables card scaling and explicit queue animations. Image decoding happens in the image-cache actor, limits remote artwork to 1280 pixels and charges the cache for decoded bytes. Queue polling and mutation reconciliation remain unchanged; banners and the filter remain safe-area insets around the stable list.

## Isolated shipping-target fixtures

Run `python3 Tests/Fixtures/streaming_server.py` locally. It binds only `127.0.0.1:18084`, requires a public synthetic fixture token, and serves credited NASA test stills plus the generated twelve-second `Tests/Fixtures/media/parity-h264.mp4` clip. It supports byte ranges, read-only `/counts` and a test-only `POST /mode` with `{"offline": true/false}`. The generated clip is already tracked in the repository. No owner server or credentials are used.

Launch the production app with `--streaming-fixture`. This branch is compiled only in Debug for Simulator and replaces dependencies before persistent owner credentials are loaded. Its account, preferences suite and private download directory are isolated. It uses production screens, player and private download/preparation services. `--streaming-fixture-reset` removes only the fixture download directory. Optional flags select light/dark, accessibility text, a sixty-item archive or the connection form:

- `--streaming-fixture-light`, `--streaming-fixture-dark`
- `--streaming-fixture-accessibility`
- `--streaming-fixture-long-list`
- `--streaming-fixture-login`

The fixture banner and metadata identify the illustrative library. Credits and exact sources are in `Tests/Fixtures/streaming-art/credits.json`; these stills are not bundled into release builds.

## Validation

Run unit tests through scheme `TAClient`; UI tests use `ConnectionFlow`. `StreamingRedesignUITests` checks production routes, manual Play, advancing native playback, fullscreen/return, local playback with the server unavailable and no new media requests, both appearances, logout/token fallback, accessibility-sized selection, archive scrolling and tab state. `ServerConnectionUITests` and `SessionPersistenceUITests` use the separate loopback connection fixture for gateway/app-login separation, blocked external redirects, relaunch, temporary outages and real expiry.

Simulator checks do not establish physical-device performance, battery cost, AirPlay, Picture in Picture, background audio, device rotation behavior or an owner server's live sign-in. Those retain the existing implementations and require normal owner/device testing before release. This change is for review; it does not merge or distribute a build.

### Recorded local result (17 October 2026)

- All **766 unit tests passed**, including independent tab-path/expiry reset and bounded image-decoding checks.
- All **four redesign UI tests passed together on iPhone 17e / iOS 26.5**. This includes short tap versus long press, one detail push per activation, accessibility-sized filters/selection, scroll retention after native tab transitions, light/dark screens, fullscreen return, channel/collection/search routes and native private playback while the server is unavailable. The private-playback media-request count remained unchanged.
- The same production-screen main flow and accessibility/scroll checks also passed on iPhone 17 Pro. Server-owned sign-in/logout with blocked external redirects passed, and saved sessions survived process termination, maintenance and loss of network; real expiry returned to sign-in.
- Initial failures distinguished test issues (hiding native fullscreen controls, ambiguous Downloads selector, checking hittability during a tab transition) from product issues (portrait artwork intercepting neighboring touches and gesture priority consuming a short tap). The latter are fixed and covered by the final UI pass.
- Actual fixture screenshots: [design overview](../screenshots/streaming-redesign.png). These contain synthetic metadata and credited test stills; they are not evidence of a live owner sign-in or physical-device performance.
