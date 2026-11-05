# Fold for Mac

The Mac version uses Mac Catalyst and the same SwiftUI screens, design assets,
repositories, Keychain sessions, download library and playback coordinator as iOS.
It requires macOS 15 or later. The iOS deployment target remains iOS 17.

## Build and launch

Use Xcode 26.4 or later (SwiftVLC requires Swift 6.3). Open `Fold.xcodeproj`,
select **Fold → My Mac (Mac Catalyst)** and use your Apple Development team.
Both Debug and Release can be built locally. The Release archive is also used for TestFlight:

```sh
./scripts/build-mac.sh
open .build/mac/Build/Products/Release-maccatalyst/Fold.app
```

The project uses the existing `LUZS336ZHP` development team. Change the team,
Mac bundle identifier and iOS settings when building for another developer.
Debug Mac builds use `com.jacobcampbell.ta-client.mac` so local development
is separate from TestFlight. Release uses the existing Fold identifier,
`com.jacobcampbell.ta-client`, allowing the Mac build to join the same App Store
Connect record and TestFlight listing as iOS. Sign in on this Mac; downloads are
stored in the Mac app's own sandbox. The first TestFlight install does not migrate
the separate local development app's session.

A development profile must include this Mac. If Xcode says the Mac is not
registered, register it through Xcode after approving the account change. A
correct development signature and the matching app-only Keychain access group
are required. An ad-hoc signature builds and launches but cannot save Catalyst
Keychain items (`errSecMissingEntitlement`, -34018), preventing sign-in.

## Platform choices

- The interface keeps the iPad layout and Fold's existing assets and controls.
  Window resizing uses the existing adaptive grids and reading widths.
- H.264/HEVC/AV1 use AVKit. The Mac-only VP8/VP9/WebM backend is SwiftVLC 1.0.0;
  iOS keeps MobileVLCKit 3.7.3. Both use Fold's existing VLC controls and progress
  callbacks. Full-screen presentations reuse the same player and drawable.
- Mac full-screen uses the window's geometry. iPhone/iPad landscape rotation is
  unchanged and Mac skips iOS-only orientation requests.
- The iOS share extension is excluded from the Mac build. Queue URLs can be
  added from Fold's Queue screen.
- Downloads stay private to Fold's sandbox. Conversion uses the same validation
  and capacity limits; Mac reads profile/rotation safety fields from libVLC.
- Local builds use development signing. TestFlight archives use Release and
  App Store Connect distribution. See `NOTICE` and [library rebuild sources](RELINKING.md)
  for the Mac VLC dependency.

## Tests

Core tests use the **Fold** scheme and Mac Catalyst destination. The
**FoldMacUI** scheme selects Mac-specific UI tests. Use
`FOLD_MAC_BUNDLE_SUFFIX=.qa` to give the test app a distinct bundle identity.

```sh
python3 Tests/Fixtures/playback_parity_server.py
python3 Tests/Fixtures/streaming_server.py
xcodebuild test -project Fold.xcodeproj -scheme FoldMacUI \
  -destination 'platform=macOS,variant=Mac Catalyst' FOLD_MAC_BUNDLE_SUFFIX=.qa \
  -only-testing:FoldUITests/MacCompatibilityUITests
```

macOS must authorize the Xcode test runner for UI testing. If it reports
“Not authorized for performing UI testing actions,” the automated UI result
is a test-environment failure; inspect the app manually or authorize the runner.
Synthetic DEBUG fixtures also run on Catalyst with the existing
`--streaming-fixture` / `--playback-fixture` launch arguments. Release builds
cannot enter these fixtures. No real server credentials are needed for them.
