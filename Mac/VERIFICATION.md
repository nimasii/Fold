# Mac verification — 2026-11-05

Baseline: `e84fd33445ea9b1ae49047d70708097db0831b47` from `main`.
Initial local branch: `mac-support`. This report records local verification before the subsequent request to merge and distribute through TestFlight.

## Deliverable

`/Users/jake/Documents/Codex/2026-11-05/task-2/Deliverables/Fold.app`

- Universal arm64 / x86_64, macOS 15+; runtime inspected on this Apple silicon Mac.
- Development-signed with the existing Apple Development identity for team
  `LUZS336ZHP`, using the Mac Catalyst development profile.
- `codesign --verify --deep --strict --verbose=2` reports valid on disk and
  satisfies its Designated Requirement when run with the normal trust services.
- App identifier and Keychain group both resolve to
  `LUZS336ZHP.com.jacobcampbell.ta-client.mac`.
- Sandbox retained, client networking for the user's server, listener networking
  for the app's existing authenticated loopback media proxy. No shared iOS
  Keychain group or iOS share extension is embedded in the Mac app.
- Quit an earlier Fold copy before opening the delivered app so Launch Services
  does not activate an already-running older build.

## Sign-in diagnosis and fix

The initial ad-hoc Mac build launched and loaded the server-owned browser, but
Catalyst Keychain writes failed. A synthetic save/reload test reproduced OSStatus
`-34018` (`errSecMissingEntitlement`) without reading the owner's credentials.
The initial Mac plist did not contain the iOS access group: the missing valid
application identity/profile was the relevant failure in this build.

The Mac build now uses Apple Development signing, a development profile including
this Mac, and matching app-only Keychain entitlements/plist access group. The
owner explicitly approved registering the Mac and creating the development
profile after automatic review initially blocked that external account action.
That retry succeeded; no registration/profile approval remains pending.

The production AuthState/LoginViewModel path now distinguishes a verified server
session that cannot be stored securely from a server-verification failure.
Diagnostic logs include a stage marker and numeric OSStatus, never cookie/token
values or passwords. No cookie boundary or CSRF checks were relaxed.

Manual Computer Use verification in a separately named, signed test copy:
server address → Umbrel-style loopback handoff → synthetic Tube Archivist
sign-in → Finish → authenticated Library → Quit → Relaunch → still authenticated.
Only dummy cookies and loopback servers were used. Jake's real server sign-in
should be retried in the delivered app; no live credential values were inspected.

## Automated checks

Final source passed:

- Signed universal Release Mac build: `mac-release-final.log`.
- iOS Simulator build (iOS 17 deployment target retained): `ios-final-build.log`.
- Combined signed Mac tests: **36 tests in 6 suites passed**,
  `MacFinalVerification.xcresult` / `mac-final-verification.log`.
  Suites include MacCompatibility, ServerConnection, LocalPlaybackParity,
  LoginViewModel and OfflineMediaPreparation (ServerConnection is nested in
  DataLayerSuite).
- `git diff --check` passed.

The tests cover real Keychain save/reload, authenticated ping/session boundaries,
CSRF/origin constraints, private playback selection, safety/capacity failures,
and complete conversion validation. VP9/WebM and VP9/MP4, one/two-minute sources,
AV1/Opus, silent video, H.264, known HDR/high-bit-depth behavior and native
post-conversion playback/seeking were exercised. Mac conversion uses libVLC 4's
avformat MP4 muxer with a 1500ms mux cache: zero caching could write the header
before AAC was announced. iOS's existing VLC 3 conversion path remains unchanged.

## Manual UI inspection

- Library, Downloads and Queue layouts retain Fold's existing assets and visual
  design; the final app uses Mac-specific download/device wording.
- VP9 rendering, pause, seek, end/replay, three full-screen entry/exit cycles,
  Escape exit, and leaving/reopening an active player were exercised.
- H.264 rendered through the existing AVKit controller; Mac window full screen
  entered and exited. The AVKit player-specific fullscreen/transport controls
  were not fully exercised through automation and remain a manual check.

## Verification gaps

The dedicated Mac UI test scheme compiles, but its final execution was blocked
by macOS: “Not authorized for performing UI testing actions” for the Xcode test
runner. Its failed xcresult is not a passing UI test result. Manual Computer Use
inspection was used instead; no accessibility permissions were broadened.

Intel runtime, AirPlay, Picture-in-Picture, physical audio-route interruptions,
long-duration playback and a real-server login on the final packaged binary were
not independently verified. The iOS simulator build passed; the prior task's
rotation tests were not rerun or changed.

This is a local development build, not a notarized distribution. The Mac iOS
share extension is excluded; use the Queue screen to add URLs. `NOTICE` and the
bundled MIT license identify the new Mac VLC dependency. Public distribution
would require the static libVLC LGPL relinking materials.
